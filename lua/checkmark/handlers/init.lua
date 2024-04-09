local go = require("checkmark.handlers.go")
local M = {}

--- set namespace id for submodule
---@param ns number
function M.set_namespace(ns)
	M.namespace_id = ns
end

function M.set_logger(logger)
	M.logger = logger
end

function M.on_stdout(state, _, data)
	if not data then
		return
	end

	for _, line in ipairs(data) do
		---@type boolean, cmGoTestOutputRow
		if line == "" then -- skip empty lines
			goto continue
		end
		local ok, decoded = pcall(vim.json.decode, line)
		if not ok then
			vim.print("failed to decode line:", vim.inspect(line))
			goto continue
		elseif decoded then
			if decoded.Action == "run" then
				-- TODO: group tests by package and rewrite this
				go.add_golang_test(state, decoded)
			elseif decoded.Action == "output" then
				-- some 'output' rows contain only metadata without references to any tests
				if decoded.Test then
					go.add_golang_output(state, decoded)
				end
			elseif decoded.Action == "pass" or decoded.Action == "fail" then
				go.mark_success(state, decoded)

				local test = state.tests[go.make_key(decoded)]
				if test then -- TODO: probabbly just shouldnt try to read non-test package entries
					if test.success then
						local text = { "✅ pass" }
						if test.line then
							vim.api.nvim_buf_set_extmark(state.bufnr, M.namespace_id, test.line, 0, {
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
end

function M.on_stderr(state, _, data)
	M.logger.debug("on_stderr: " .. vim.inspect(data))
	if not data == "" then
		M.logger.error("failed to run tests: " .. vim.inspect(data))
	end
end

function M.on_exit(state)
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
				go.append_to_parent_test(key, test, state)
			end
		end
	end

	vim.diagnostic.set(M.namespace_id, state.bufnr, failed)
	M.logger.debug("on_exit state: " .. vim.inspect(state))
end

return M
