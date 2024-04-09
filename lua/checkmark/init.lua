local treesitter = require("checkmark.treesitter")
local config = require("checkmark.config")
local handlers = require("checkmark.handlers")
local augroup = require("checkmark.augroup")
local ns = require("checkmark.namespace")

local M = {}

---@class cmSetupOpts Options available when initalizing the plugin
---@field log_lvl? string log msg level
---@field command? table<string> override default command that gets executed when running tests

---Configure and initialize the plugin
---@param opts cmSetupOpts
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", config.get_default_values(), opts)
	M.logger = require("checkmark.log").new(M.config.log_lvl)
	treesitter.set_language(M.config.language)
	handlers.set_logger(M.logger)
	M.logger.debug("plugin successfully initialized")
end

---@class cmState
---@field tests table
---@field bufnr number

---initializes and returns plugin augroup, and namespace ID pair
local function init_plugin_namespace()
	if M.logger then
		M.logger.debug("initialized namespaces and augroup")
	end
	handlers.set_namespace(ns)
end

init_plugin_namespace()

vim.diagnostic.config({
	virtual_text = {
		format = function(diagnostic)
			return diagnostic.user_data.short_message
		end,
	},
}, ns)

---@param init_state cmState
---@param command table
local function run_tests(init_state, command)
	M.logger.debug("running tests: ", command)
	vim.api.nvim_buf_clear_namespace(init_state.bufnr, ns, 0, -1)

	-- initialize state since we are re-running tests
	local state = {
		bufnr = tonumber(init_state.bufnr),
		tests = {},
	}

	vim.fn.jobstart(command, {
		stdout_buffered = true,
		on_stdout = function(_, data)
			M.logger.debug("handling std_out")
			handlers.on_stdout(state, _, data)
		end,
		on_stderr = function(_, data)
			M.logger.debug("handling std_err")
			handlers.on_stderr(state, _, data)
		end,
		on_exit = function()
			M.logger.debug("handling exit")
			handlers.on_exit(state)
		end,
	})
	return state
end

local function attach_to_buffer(bufnr, command)
	local state = {
		bufnr = bufnr,
		tests = {},
	}

	vim.api.nvim_buf_create_user_command(bufnr, "GoTestLineDiag", function()
		local line = vim.fn.line(".") - 1
		for _, test in pairs(state.tests) do
			if test.line == line then
				vim.cmd.new()
				vim.api.nvim_buf_set_lines(vim.api.nvim_get_current_buf(), 0, -1, false, test.output)
			end
		end
	end, {})

	vim.api.nvim_create_autocmd("BufWritePost", {
		group = augroup,
		pattern = "*.go",
		callback = function()
			state = run_tests(state, command)
		end,
	})
end

M.test_on_save = function()
	init_plugin_namespace() -- init augroup (so it deletes the previous one also)
	attach_to_buffer(vim.api.nvim_get_current_buf(), M.config.command)
end

M.run_tests = function()
	-- TODO: this breaks if the vim cwd isnt a module root (for golang)
	run_tests({
		bufnr = vim.api.nvim_get_current_buf(),
		tests = {},
	}, M.config.command)
end

vim.api.nvim_create_user_command("GoTestOnSave", function()
	M.test_on_save()
end, {})

vim.api.nvim_create_user_command("GoTestCheckmarks", function()
	M.run_tests()
end, {})

return M
