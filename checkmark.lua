-- -- TODO: write a proper plugin for this
local test_function_query_string = [[
(
 (function_declaration
  name: (identifier) @name
  parameters:
    (parameter_list
     (parameter_declaration
      name: (identifier)
      type: (pointer_type
          (qualified_type
           package: (package_identifier) @_package_name
           name: (type_identifier) @_type_name)))))

 (#eq? @_package_name "testing")
 (#eq? @_type_name "T")
 (#eq? @name "%s")
)
]]

local find_test_line = function(bufnr, name)
	local formatted = string.format(test_function_query_string, name)
	local query = vim.treesitter.query.parse("go", formatted)
	local parser = vim.treesitter.get_parser(bufnr, "go", {})
	local tree = parser:parse()[1]
	local root = tree:root()

	for id, node in query:iter_captures(root, bufnr, 0, -1) do
		if id == 1 then
			local range = { node:range() }
			return range[1]
		end
	end
end

local make_key = function(entry)
	assert(entry.Package, "must have Package:" .. vim.inspect(entry))
	if not entry.Test then
		-- TODO: figure out when test-less package names are spit out by go test
		return entry.Package
	end
	return string.format("%s/%s", entry.Package, entry.Test)
end

local add_golang_test = function(state, entry)
	state.tests[make_key(entry)] = {
		name = entry.Test,
		line = find_test_line(state.bufnr, entry.Test),
		output = {},
	}
end

local add_golang_output = function(state, entry)
	-- TODO: group tests by package and rewrite this
	assert(state.tests, vim.inspect(state))
	local key = make_key(entry)
	state.tests[key] = vim.tbl_extend("force", state.tests[key], {
		output = vim.trim(entry.Output),
		package = vim.trim(entry.Package),
	})
end

local mark_success = function(state, entry)
	if state.tests[make_key(entry)] then
		state.tests[make_key(entry)].success = entry.Action == "pass"
	end
end

local append_to_parent_test = function(key, test, state)
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
			local existing_output = "-"
			if type(state.tests[pt_key].output) == "string" then
				existing_output = state.tests[pt_key].output -- in case there already are failed tests in this root tests
			else
				existing_output = table.unpack(state.tests[pt_key].output)
			end

			local existing_test_output = "-"
			if type(test.output) == "string" then
				existing_test_output = test.output -- in case there already are failed tests in this root tests
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
local init_plugin_namespace = function()
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

local run_tests = function(init_state, command)
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

local attach_to_buffer = function(bufnr, command)
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

vim.api.nvim_create_user_command("GoTestOnSave", function()
	init_plugin_namespace() -- init augroup (so it deletes the previous one also)
	attach_to_buffer(vim.api.nvim_get_current_buf(), { "go", "test", "-v", "-json", [[./...]] })
end, {})

vim.api.nvim_create_user_command("GoTestCheckmarks", function()
	run_tests({
		bufnr = vim.api.nvim_get_current_buf(),
		tests = {},
	}, { "go", "test", "-v", "-json", [[./...]] })
end, {})
