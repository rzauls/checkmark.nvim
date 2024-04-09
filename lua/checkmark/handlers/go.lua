local treesitter = require("checkmark.treesitter")

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

local M = {}

function M.make_key(entry)
	assert(entry.Package, "must have Package:" .. vim.inspect(entry))
	if not entry.Test then
		-- TODO: figure out when test-less package names are spit out by go test
		return entry.Package
	end
	return string.format("%s/%s", entry.Package, entry.Test)
end

---@param state cmState
---@param entry cmGoTestOutputRow
function M.add_golang_test(state, entry)
	state.tests[M.make_key(entry)] = {
		name = entry.Test,
		line = treesitter.find_test_line(state.bufnr, entry.Test),
		output = {},
	}
end

---@param state cmState
---@param entry cmGoTestOutputRow
function M.add_golang_output(state, entry)
	-- TODO: group tests by package and rewrite this
	assert(state.tests, vim.inspect(state))
	local key = M.make_key(entry)
	state.tests[key] = vim.tbl_extend("force", state.tests[key], {
		output = vim.trim(entry.Output),
		package = vim.trim(entry.Package),
	})
end

---@param state cmState
---@param entry cmGoTestOutputRow
function M.mark_success(state, entry)
	if state.tests[M.make_key(entry)] then
		state.tests[M.make_key(entry)].success = entry.Action == "pass"
	end
end

---@param key string
---@param test cmTestCase
---@param state cmState
function M.append_to_parent_test(key, test, state)
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

return M
