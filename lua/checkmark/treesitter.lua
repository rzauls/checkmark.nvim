---Supported language test lookup
---@alias cmLanguage
---| '"go"' # golang
---| string # any custom language can be added with appropriate treesitter query

---Treesitter module for test lookup
---@class cmTreesitterModule
---@field language cmLanguage
---@field queries table<string>
local M = {
	language = "go",
	queries = {},
}

-- NOTE: im unsure if i want to support other languages,
-- but lets leave it like this for now
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

M.queries = {
	["go"] = go_query,
}

---Get treesitter query string for a language, if it exists
---@package
---@return string
local function get_query_for_language(language)
	for key, value in pairs(M.queries) do
		if key == language then
			return value
		else
			error(string.format("no query defined for '%s' language", language))
		end
	end
end

---Set active language for the test lookup module
---@param language cmLanguage
function M.set_language(language)
	local ok, _ = pcall(get_query_for_language, language)
	if not ok then
		error("cannot set a language without defining a treesitter query first")
	end
	M.language = language
end

---Add language query to find tests in buffer
---@param language cmLanguage
---@param query string
function M.add_language(language, query)
	-- TODO: check if treesitter has a parser for the specified language
	M.queries[language] = query
end

---Find line number of a test case in specified buffer
---@param bufnr number Buffer ID
---@param name string Test case name
---@return number|nil
function M.find_test_line(bufnr, name)
	local formatted = string.format(get_query_for_language(M.language), name)
	local query = vim.treesitter.query.parse(M.language, formatted)
	local parser = vim.treesitter.get_parser(bufnr, M.language, {})
	local tree = parser:parse()[1]

	for id, node in query:iter_captures(tree:root(), bufnr, 0, -1) do
		if id == 1 then
			local range = { node:range() }
			return range[1]
		end
	end
end

return M
