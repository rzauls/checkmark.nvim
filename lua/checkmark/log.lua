local log = require("plenary.log")

local M = {}

function M.new(lvl)
	local log_lvl = "info"
	if lvl then
		log_lvl = lvl
	end
	return log.new({
		plugin = "checkmark",
		use_console = "async",
		use_file = false,
		level = log_lvl,
	}, false)
end

return M
