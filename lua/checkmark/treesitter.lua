local M = {}

local go_query = [[
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

-- NOTE: im unsure if i want to support other languages,
-- but lets leave it like this for now
local queries = {
	["go"] = go_query,
}

---@return string
function M.get_query_for_language(language)
	for key, value in pairs(queries) do
		if key == language then
			return value
		else
			error(string.format("no query defined for '%s' language", language))
		end
	end
end

function M.find_test_line(bufnr, name)
	-- TODO: hardcoded language sorta
	local formatted = string.format(M.get_query_for_language("go"), name)
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

return M
