local M = {}

---@class CheckmarkConfig checkmark.nvim configuration settings
---@field command table<string>

---@return CheckmarkConfig
function M.get_default_values()
	return {
		command = { "go", "test", "-v", "-json", [[./...]] },
	}
end

M.values = M.get_default_values()

return M
