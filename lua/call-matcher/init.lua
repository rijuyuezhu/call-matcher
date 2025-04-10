local M = {}

-- Clean whitespace and normalize strings
-- Handles newlines, consecutive spaces, and trims leading/trailing whitespace
-- For parameters, also removes leading commas
local function clean_whitespace(str, is_param)
	-- Remove \\\n pattern, and newlines and consecutive whitespace outside of double-quoted strings
	str = str:gsub("\\\n", "")

	local result = {}
	local i = 1
	local n = #str

	while i <= n do
		if str:sub(i, i) == '"' and (i == 1 or str:sub(i - 1, i - 1) ~= "\\") then
			table.insert(result, '"')
			i = i + 1

			while i <= n do
				local char = str:sub(i, i)
				table.insert(result, char)

				if char == '"' and (i == 1 or str:sub(i - 1, i - 1) ~= "\\") then
					i = i + 1
					break
				end
				i = i + 1
			end
		else
			if str:sub(i, i):match("%s") then
				table.insert(result, " ")
				while i <= n and str:sub(i, i):match("%s") do
					i = i + 1
				end
			else
				table.insert(result, str:sub(i, i))
				i = i + 1
			end
		end
	end

	str = table.concat(result)

	-- If it's a parameter, first remove leading comma + any whitespace
	if is_param then
		str = str:gsub("^%s*,%s*", ""):gsub("^,", "")
	end
	-- Remove leading/trailing whitespace
	return str:gsub("^%s*(.-)%s*$", "%1")
end

-- Setup autocmd to detect and process C/C++ files
-- Triggers on buffer enter, write, and text changes
local function setup_autocmd()
	vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "TextChanged", "TextChangedI" }, {
		group = vim.api.nvim_create_augroup("CallMatcherAuto", { clear = true }),
		callback = function()
			if vim.bo.filetype == "c" or vim.bo.filetype == "cpp" or vim.bo.filetype == "h" then
				M.find_calls()
			end
		end,
	})
end

M.setup = function()
	setup_autocmd()
end
local ns_id = vim.api.nvim_create_namespace("call_matcher")

-- Check if current buffer is a C/C++ file
-- Returns true for .c, .cpp, and .h filetypes
local function is_c_file()
	local ft = vim.bo.filetype
	return ft == "c" or ft == "cpp" or ft == "h"
end

-- Display virtual text annotations
-- Shows method calls and signatures inline with the code
-- Format varies based on call type (CALL, NSCALL, MTD, NSMTD)
local function show_virtual_text(bufnr, line, col, item)
	local virt_lines = {}

	if item.type == "CALL" then
		virt_lines = {
			{
				{ string.rep(" ", col), "Normal" },
				{ "(", "Bold" },
				{ item.class, "Bold" },
				{ "&)", "Bold" },
				{ item.name, "Underlined" },
				{ string.format(".%s(%s)", item.method, item.params), "Normal" },
			},
		}
	elseif item.type == "NSCALL" then
		virt_lines = {
			{
				{ string.rep(" ", col), "Normal" },
				{ item.class, "Bold" },
				{ "::", "Bold" },
				{ string.format("%s(%s)", item.name, item.params), "Normal" },
			},
		}
	elseif item.type == "MTD" then
		virt_lines = {
			{
				{ string.rep(" ", col), "Normal" },
				{ item.class, "Bold" },
				{ ".", "Bold" },
				{ item.method, "Underlined" },
				{ string.format("(%s)", item.params), "Normal" },
			},
		}
	elseif item.type == "NSMTD" then
		virt_lines = {
			{
				{ string.rep(" ", col), "Normal" },
				{ item.class, "Bold" },
				{ "::", "Bold" },
				{ item.method, "Underlined" },
				{ string.format("(%s)", item.params), "Normal" },
			},
		}
	end

	vim.api.nvim_buf_set_extmark(bufnr, ns_id, line, col, {
		virt_lines = virt_lines,
		hl_mode = "replace",
	})
end

-- Clear all virtual text annotations
-- Removes all call matcher highlights from buffer
local function clear_virtual_text(bufnr)
	vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
end

local function find_first_of(content, patterns, start_pos)
	local firstPos = math.huge -- Initialize to a very large number
	local lastPos = 0
	local foundType = nil
	local hasMatch = false

	for _, pattern in ipairs(patterns) do
		local start, finish, nowtype = content:find(pattern, start_pos)
		if start and start < firstPos then
			firstPos = start
			lastPos = finish
			foundType = nowtype
			hasMatch = true
		end
	end

	if hasMatch then
		return firstPos, lastPos, foundType
	end
	return nil -- No matches found
end

-- Main matching function for call patterns
-- Processes C/C++ buffers to find and highlight:
-- 1. Object method calls (CALL)
-- 2. Namespace function calls (NSCALL)
-- 3. Method definitions (MTD)
-- 4. Namespace method definitions (NSMTD)
function M.find_calls()
	if not is_c_file() then
		vim.notify("Not a C/C++ file", vim.log.levels.WARN)
		return
	end

	-- Get current file content
	local content = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")

	-- Improved CALL pattern matching function, handles nested parentheses
	local results = {}
	local pos = 1
	local len = #content

	while pos <= len do
		local pattern_start, pattern_end, pattern_type =
			find_first_of(content, { "(CALL)%(", "(NSCALL)%(", "(MTD)%(", "(NSMTD)%(" }, pos)
		if not pattern_start then
			break
		end

		-- Find matching closing parenthesis
		local depth = 1
		local i = pattern_end + 1
		while i <= len and depth > 0 do
			local char = content:sub(i, i)
			if char == "(" then
				depth = depth + 1
			elseif char == ")" then
				depth = depth - 1
			end
			i = i + 1
		end

		if depth == 0 then
			local full_match = content:sub(pattern_start, i - 1)
			-- Process based on pattern type
			if pattern_type == "CALL" then
				-- CALL pattern processing - improved version, handles nested parentheses
				local parts = {}
				local current_pos = 6 -- Skip "CALL("
				local depth = 0

				-- Extract class
				while current_pos <= #full_match do
					local char = full_match:sub(current_pos, current_pos)
					if char == "," and depth == 0 then
						break
					end
					if char == "(" then
						depth = depth + 1
					end
					if char == ")" then
						depth = depth - 1
					end
					current_pos = current_pos + 1
				end
				local raw_class = full_match:sub(6, current_pos - 1)

				-- Extract name
				current_pos = current_pos + 1 -- Skip comma
				local name_start = current_pos
				while current_pos <= #full_match do
					local char = full_match:sub(current_pos, current_pos)
					if char == "," and depth == 0 then
						break
					end
					if char == "(" then
						depth = depth + 1
					end
					if char == ")" then
						depth = depth - 1
					end
					current_pos = current_pos + 1
				end
				local raw_name = full_match:sub(name_start, current_pos - 1)

				-- Extract method
				current_pos = current_pos + 1 -- Skip comma
				local method_start = current_pos
				while current_pos <= #full_match do
					local char = full_match:sub(current_pos, current_pos)
					if char == "," and depth == 0 then
						break
					end
					if char == "(" then
						depth = depth + 1
					end
					if char == ")" then
						depth = depth - 1
					end
					current_pos = current_pos + 1
				end
				local raw_method = full_match:sub(method_start, current_pos - 1)

				-- Find slash position
				local slash_pos = full_match:find("/", current_pos + 1)
				if slash_pos then
					local raw_params = full_match:sub(slash_pos + 1, -2)

					local class = clean_whitespace(raw_class)
					local name = clean_whitespace(raw_name)
					local method = clean_whitespace(raw_method)
					local params = clean_whitespace(raw_params, true)

					table.insert(results, {
						type = "CALL",
						class = class,
						name = name,
						method = method,
						params = params,
						line = #vim.split(content:sub(1, pattern_start), "\n", { plain = true }),
						endline = #vim.split(content:sub(1, i - 1), "\n", { plain = true }),
					})
				end
			elseif pattern_type == "MTD" then
				-- MTD pattern processing
				local current_pos = 5 -- Skip "MTD("
				local depth = 0

				-- Extract class
				while current_pos <= #full_match do
					local char = full_match:sub(current_pos, current_pos)
					if char == "," and depth == 0 then
						break
					end
					if char == "(" then
						depth = depth + 1
					end
					if char == ")" then
						depth = depth - 1
					end
					current_pos = current_pos + 1
				end
				local raw_class = full_match:sub(5, current_pos - 1)

				-- Extract method
				current_pos = current_pos + 1 -- Skip comma
				local method_start = current_pos
				while current_pos <= #full_match do
					local char = full_match:sub(current_pos, current_pos)
					if char == "," and depth == 0 then
						break
					end
					if char == "(" then
						depth = depth + 1
					end
					if char == ")" then
						depth = depth - 1
					end
					current_pos = current_pos + 1
				end
				local raw_method = full_match:sub(method_start, current_pos - 1)

				-- Find slash position
				local slash_pos = full_match:find("/", current_pos + 1)
				if slash_pos then
					local raw_params = full_match:sub(slash_pos + 1, -2)

					local class = clean_whitespace(raw_class)
					local method = clean_whitespace(raw_method)
					local params = clean_whitespace(raw_params, true)

					table.insert(results, {
						type = "MTD",
						class = class,
						method = method,
						params = params,
						line = #vim.split(content:sub(1, pattern_start), "\n", { plain = true }),
						endline = #vim.split(content:sub(1, i - 1), "\n", { plain = true }),
					})
				end
			elseif pattern_type == "NSCALL" then
				-- NSCALL pattern processing - improved version, handles nested parentheses
				local parts = {}
				local current_pos = 8 -- Skip "NSCALL("
				local depth = 0

				-- Extract class
				while current_pos <= #full_match do
					local char = full_match:sub(current_pos, current_pos)
					if char == "," and depth == 0 then
						break
					end
					if char == "(" then
						depth = depth + 1
					end
					if char == ")" then
						depth = depth - 1
					end
					current_pos = current_pos + 1
				end
				local raw_class = full_match:sub(8, current_pos - 1)

				-- Extract name
				current_pos = current_pos + 1 -- Skip comma
				local name_start = current_pos
				while current_pos <= #full_match do
					local char = full_match:sub(current_pos, current_pos)
					if char == "," and depth == 0 then
						break
					end
					if char == "(" then
						depth = depth + 1
					end
					if char == ")" then
						depth = depth - 1
					end
					current_pos = current_pos + 1
				end
				local raw_name = full_match:sub(name_start, current_pos - 1)

				-- Find slash position
				local slash_pos = full_match:find("/", current_pos + 1)
				if slash_pos then
					local raw_params = full_match:sub(slash_pos + 1, -2)

					local class = clean_whitespace(raw_class)
					local name = clean_whitespace(raw_name)
					local params = clean_whitespace(raw_params, true)

					table.insert(results, {
						type = "NSCALL",
						class = class,
						name = name,
						params = params,
						line = #vim.split(content:sub(1, pattern_start), "\n", { plain = true }),
						endline = #vim.split(content:sub(1, i - 1), "\n", { plain = true }),
					})
				end
			elseif pattern_type == "NSMTD" then
				-- NSMTD pattern processing - similar to MTD but shows as def method(parameter)
				local current_pos = 7 -- Skip "NSMTD("
				local depth = 0

				-- Extract class
				while current_pos <= #full_match do
					local char = full_match:sub(current_pos, current_pos)
					if char == "," and depth == 0 then
						break
					end
					if char == "(" then
						depth = depth + 1
					end
					if char == ")" then
						depth = depth - 1
					end
					current_pos = current_pos + 1
				end
				local raw_class = full_match:sub(7, current_pos - 1)

				-- Extract method
				current_pos = current_pos + 1 -- Skip comma
				local method_start = current_pos
				while current_pos <= #full_match do
					local char = full_match:sub(current_pos, current_pos)
					if char == "," and depth == 0 then
						break
					end
					if char == "(" then
						depth = depth + 1
					end
					if char == ")" then
						depth = depth - 1
					end
					current_pos = current_pos + 1
				end
				local raw_method = full_match:sub(method_start, current_pos - 1)

				-- Find slash position
				local slash_pos = full_match:find("/", current_pos + 1)
				if slash_pos then
					local raw_params = full_match:sub(slash_pos + 1, -2)

					local class = clean_whitespace(raw_class)
					local method = clean_whitespace(raw_method)
					local params = clean_whitespace(raw_params, true)

					table.insert(results, {
						type = "NSMTD",
						class = class,
						method = method,
						params = params,
						line = #vim.split(content:sub(1, pattern_start), "\n", { plain = true }),
						endline = #vim.split(content:sub(1, i - 1), "\n", { plain = true }),
					})
				end
			end
		end

		pos = i
	end

	local bufnr = vim.api.nvim_get_current_buf()
	clear_virtual_text(bufnr)

	if #results > 0 then
		for _, item in ipairs(results) do
			local line_content = vim.api.nvim_buf_get_lines(bufnr, item.line - 1, item.line, false)
			if #line_content == 0 then
				vim.notify(string.format("[CALL Matcher] Empty line at %d", item.line), vim.log.levels.WARN)
				break
			end
			local pattern_start = line_content[1]:find(item.type .. "%(")

			if pattern_start then
				-- Show virtual text (only once)
				show_virtual_text(bufnr, item.endline - 1, pattern_start - 1, item)
			end
		end
	end
end

return M
