local treesitter = require("checkmark.treesitter")
local config = require("checkmark.config")

local M = {}
function M.setup(opts)
	--TODO: do some setup-ing
	print("called setup with opts", vim.inspect(opts))
	M._config = config.get_default_values()
end

-- TODO:: move these somewhere more fitting

---@class cmTestCase
---@field name string
---@field package string
---@field line number
---@field output table
---@field success boolean

---@alias cmGoTestAction
---| '"start"'
---| '"run"'
---| '"cont"'
---| '"pause"'
---| '"skip"'
---| '"output"'
---| '"pass"'
---| '"fail"'

---@class cmGoTestOutputRow
---@field Test string?
---@field Time string
---@field Package string
---@field Action cmGoTestAction
---@field Output string?
---@field Elapsed number?

---@class cmState
---@field tests table
---@field bufnr number

local function make_key(entry)
	assert(entry.Package, "must have Package:" .. vim.inspect(entry))
	if not entry.Test then
		-- TODO: figure out when test-less package names are spit out by go test
		return entry.Package
	end
	return string.format("%s/%s", entry.Package, entry.Test)
end

---@param state cmState
---@param entry cmGoTestOutputRow
local function add_golang_test(state, entry)
	state.tests[make_key(entry)] = {
		name = entry.Test,
		line = treesitter.find_test_line(state.bufnr, entry.Test),
		output = {},
	}
end

---@param state cmState
---@param entry cmGoTestOutputRow
local function add_golang_output(state, entry)
	-- TODO: group tests by package and rewrite this
	assert(state.tests, vim.inspect(state))
	local key = make_key(entry)
	state.tests[key] = vim.tbl_extend("force", state.tests[key], {
		output = vim.trim(entry.Output),
		package = vim.trim(entry.Package),
	})
end

---@param state cmState
---@param entry cmGoTestOutputRow
local function mark_success(state, entry)
	if state.tests[make_key(entry)] then
		state.tests[make_key(entry)].success = entry.Action == "pass"
	end
end

---@param key string
---@param test cmTestCase
---@param state cmState
local function append_to_parent_test(key, test, state)
	-- TODO: group tests by package and rewrite this
	local parent_key = test.package

	-- build the <package>/<test-function-name> lookup key
	-- TODO: parent key needs 3 parts if the package is nested
	for part in test.name:gmatch("[^/]+") do
		parent_key = table.concat({ parent_key, part }, "/")
		break
	end

	vim.print(string.format("build parent_key: %s for %s", parent_key, test.name))

	-- look for <parent_key> in previous tests to find the diagnostic root
	for pt_key, _ in pairs(state.tests) do
		vim.print(string.format("test_key: %s parent_key: %s", parent_key, pt_key))
		if parent_key == pt_key then
			local existing_output
			if type(state.tests[pt_key].output) == "string" then
				existing_output = state.tests[pt_key].output -- in case there already are failed tests in this root tests
			else
				existing_output = table.unpack(state.tests[pt_key].output)
			end

			local existing_test_output
			if type(test.output) == "string" then
				-- in case there already are failed tests in this root tests
				existing_test_output = test.output
			else
				existing_test_output = table.unpack(test.output)
			end

			vim.print(string.format("appending %s output to %s", test.name, pt_key))
			state.tests[pt_key].output = table.concat({
				existing_output,
				"",
				existing_test_output,
			}, "\n")
			return
		end
	end
	vim.print("couldnd find parent", vim.inspect(test))
end

-- returns group, ns pair
-- TODO: learn how luadocs work and type them out
local function init_plugin_namespace()
	return vim.api.nvim_create_augroup("checkmark.nvim-auto", { clear = true }),
		vim.api.nvim_create_namespace("checkmark.nvim")
end

local group, ns = init_plugin_namespace()

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
	vim.api.nvim_buf_clear_namespace(init_state.bufnr, ns, 0, -1)

	-- initialize state since we are re-running tests
	local state = {
		bufnr = tonumber(init_state.bufnr),
		tests = {},
	}

	vim.fn.jobstart(command, {
		stdout_buffered = true,
		on_stdout = function(_, data)
			if not data then
				return
			end

			for _, line in ipairs(data) do
				---@type boolean, cmGoTestOutputRow
				local ok, decoded = pcall(vim.json.decode, line)
				if not ok then
					vim.print("failed to decode line:", vim.inspect(line))
					goto continue
				elseif decoded then
					if decoded.Action == "run" then
						-- TODO: group tests by package and rewrite this
						add_golang_test(state, decoded)
					elseif decoded.Action == "output" then
						-- some 'output' rows contain only metadata without references to any tests
						if decoded.Test then
							add_golang_output(state, decoded)
						end
					elseif decoded.Action == "pass" or decoded.Action == "fail" then
						mark_success(state, decoded)

						local test = state.tests[make_key(decoded)]
						if test then -- TODO: probabbly just shouldnt try to read non-test package entries
							if test.success then
								local text = { "✅ pass" }
								if test.line then
									vim.api.nvim_buf_set_extmark(state.bufnr, ns, test.line, 0, {
										virt_text = { text },
										-- TODO: figure out why highlight group doesnt work. maybe namespace issue?
										hl_group = "comment",
									})
								end
							end
						end
					elseif
						decoded.Action == "pause"
						or decoded.Action == "cont"
						or decoded.Action == "skip"
						or decoded.Action == "start"
					then
					-- Do nothing
					else
						error("failed to handle" .. vim.inspect(line))
					end
				end
				::continue::
			end
		end,

		on_exit = function()
			local failed = {}
			for key, test in pairs(state.tests) do
				if test.line then
					if not test.success then
						local message = ""
						if test.output then
							if type(test.output) == "string" then
								message = test.output
							elseif type(test.output) == "table" then
								message = table.concat(test.output, "\n")
							else
								error("some weird thing in test state" .. vim.inspect(test.output))
							end
						end
						table.insert(failed, {
							bufnr = state.bufnr,
							lnum = test.line,
							col = 0,
							severity = vim.diagnostic.severity.ERROR,
							source = "go-test",
							message = message,
							user_data = {
								test = test,
								short_message = "❌ fail",
							},
						})
					end
				else
					if not test.success then
						append_to_parent_test(key, test, state)
					end
				end
			end

			vim.print(vim.inspect(state))
			vim.diagnostic.set(ns, state.bufnr, failed)
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
		group = group,
		pattern = "*.go",
		callback = function()
			state = run_tests(state, command)
		end,
	})
end

M.test_on_save = function()
	init_plugin_namespace() -- init augroup (so it deletes the previous one also)
	attach_to_buffer(vim.api.nvim_get_current_buf(), M._config.command)
end

M.run_tests = function()
	run_tests({
		bufnr = vim.api.nvim_get_current_buf(),
		tests = {},
	}, M._config.command)
end

vim.api.nvim_create_user_command("GoTestOnSave", function()
	M.test_on_save()
end, {})

vim.api.nvim_create_user_command("GoTestCheckmarks", function()
	M.run_tests()
end, {})

return M
