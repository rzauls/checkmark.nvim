local M = {}

---checkmark.nvim configuration settings
---@class cmConfig
---@field command table<string>
---@field language cmLanguage
---@field log_lvl string

---Get default configuration values
---@return cmConfig
function M.get_default_values()
	return {
		command = { "go", "test", "-v", "-json", [[./...]] },
		language = "go",
		log_lvl = "error",
	}
end

M.values = M.get_default_values()

return M
