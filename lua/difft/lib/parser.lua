-- luacheck: globals vim

--- Parser module for difft.nvim
--- Handles parsing of difftastic headers and ANSI color codes

local M = {}

-- ANSI code to highlight group mapping (initialized by init_ansi_mapping)
local ansi_to_hl = {}

-- Cache for formatted highlight groups
local hl_cache = {}

--- Initialize ANSI color mapping based on config
--- @param config table User configuration with diff.highlights table
function M.init_ansi_mapping(config)
	ansi_to_hl = {
		["30"] = config.diff.highlights.dim, -- Black/dark gray
		["31"] = config.diff.highlights.delete, -- Red
		["32"] = config.diff.highlights.add, -- Green
		["33"] = config.diff.highlights.change, -- Yellow
		["34"] = config.diff.highlights.info, -- Blue
		["35"] = config.diff.highlights.hint, -- Magenta
		["36"] = config.diff.highlights.info, -- Cyan
		["37"] = config.diff.highlights.dim, -- White/light gray
		["90"] = config.diff.highlights.dim, -- Bright black/gray
		["91"] = config.diff.highlights.delete, -- Bright red
		["92"] = config.diff.highlights.add, -- Bright green
		["93"] = config.diff.highlights.change, -- Bright yellow
		["94"] = config.diff.highlights.info, -- Bright blue
		["95"] = config.diff.highlights.hint, -- Bright magenta
		["96"] = config.diff.highlights.info, -- Bright cyan
		["97"] = config.diff.highlights.dim, -- Bright white
	}
end

--- Clear the highlight cache (call on colorscheme change)
function M.clear_hl_cache()
	hl_cache = {}
end

--- Get or create a formatted highlight group
--- @param base_hl string Base highlight group name
--- @param bold boolean Whether to apply bold
--- @param italic boolean Whether to apply italic
--- @param dim boolean Whether to apply dim
--- @param underline boolean Whether to apply underline
--- @return string Highlight group name
local function get_highlight_with_format(base_hl, bold, italic, dim, underline)
	if not bold and not italic and not dim and not underline then
		return base_hl
	end

	local key = base_hl .. (bold and "_bold" or "") .. (italic and "_italic" or "") .. (dim and "_dim" or "") .. (underline and "_underline" or "")

	if hl_cache[key] then
		return hl_cache[key]
	end

	-- Get the base highlight properties (link=false to get actual colors, not follow links)
	local base_props = vim.api.nvim_get_hl(0, { name = base_hl, link = false })

	local format_attrs = {}
	if bold then
		format_attrs.bold = true
	end
	if italic then
		format_attrs.italic = true
	end
	if underline then
		format_attrs.underline = true
	end
	-- Dim is handled by using Comment for base_hl, so we don't need to set it here

	local new_props = vim.tbl_extend("force", base_props, format_attrs)

	vim.api.nvim_set_hl(0, key, new_props)

	hl_cache[key] = key

	return key
end

--- Parse ANSI escape codes from a line and return clean text + highlights
--- @param line string Raw line with ANSI escape codes
--- @return string clean_text Text with ANSI codes stripped
--- @return table highlights List of highlight regions with col, length, and hl_group
function M.parse_ansi_line(line)
	local text_parts = {}
	local highlights = {}
	local current_hl = nil
	local bold = false
	local italic = false
	local dim = false
	local underline = false
	local col = 0
	local pos = 1

	while pos <= #line do
		local esc_start, esc_end, codes = line:find("\27%[([%d;]+)m", pos)

		if not esc_start then
			local text_chunk = line:sub(pos)
			if #text_chunk > 0 then
				table.insert(text_parts, text_chunk)
				if current_hl then
					table.insert(highlights, {
						col = col,
						length = #text_chunk,
						hl_group = get_highlight_with_format(current_hl, bold, italic, dim),
					})
				end
			end
			break
		end

		local text_chunk = line:sub(pos, esc_start - 1)
		if #text_chunk > 0 then
			table.insert(text_parts, text_chunk)
			if current_hl then
				table.insert(highlights, {
					col = col,
					length = #text_chunk,
					hl_group = get_highlight_with_format(current_hl, bold, italic, dim, underline),
				})
			end
			col = col + #text_chunk
		end

		for code in codes:gmatch("%d+") do
			if code == "0" then
				current_hl = nil
				bold = false
				italic = false
				dim = false
				underline = false
			elseif code == "1" then
				bold = true
			elseif code == "2" then
				dim = true
				-- Also set to Comment if no other color is set
				if not current_hl then
					current_hl = "Comment"
				end
			elseif code == "3" then
				italic = true
			elseif code == "4" then
				underline = true
			elseif ansi_to_hl[code] then
				current_hl = ansi_to_hl[code]
			end
		end

		pos = esc_end + 1
	end

	return table.concat(text_parts), highlights
end

--- Parse file change headers from diff output
--- Detects difftastic file headers (e.g., "path/to/file.lua --- 1/2 --- Lua")
--- @param lines table List of clean text lines
--- @return table headers Array of header info: {{line=number, filename=string, language=string, step={current, of}|nil}, ...}
--- @return table header_set Set of header line numbers (1-indexed) for quick lookup: {[line]=true, ...}
function M.parse_headers(lines)
	local headers = {}
	local header_set = {}

	for i, line in ipairs(lines) do
		-- Only process lines that contain "---" to avoid matching plain numbers
		if not line:match("%-%-%-%s+") then
			goto continue
		end

		-- Try pattern with step info first: "filename --- 1/10 --- language"
		local pattern_with_step = "^(.-)%s+%-%-%-%s+(%d+)/(%d+)%s+%-%-%-%s+(.+)$"
		local filename, step_current, step_of, language = line:match(pattern_with_step)

		if filename and step_current and step_of and language then
			-- Validate: filename should contain a path separator or extension or start with uppercase
			-- Language should not be just digits
			-- More strict: extension should be dot followed by alphanumeric, not just any dot
			local has_extension = filename:match("%.[%w]+$") or filename:match("%.[%w]+/")
			local has_path = filename:match("/")
			local starts_upper = filename:match("^%u")
			local valid_filename = has_extension or has_path or starts_upper
			local valid_language = not language:match("^%d+$")
			if valid_filename and valid_language then
				table.insert(headers, {
					line = i,
					filename = vim.trim(filename),
					language = vim.trim(language),
					step = {
						current = tonumber(step_current),
						of = tonumber(step_of),
					},
				})
				header_set[i] = true
			end
		else
			-- Try without step info: "filename --- language"
			local pattern_no_step = "^(.-)%s+%-%-%-%s+(.+)$"
			filename, language = line:match(pattern_no_step)
			if filename and language then
				-- Validate: filename should contain a path separator or extension or start with uppercase
				-- Language should not be just digits
				-- More strict: extension should be dot followed by alphanumeric, not just any dot
				local has_extension = filename:match("%.[%w]+$") or filename:match("%.[%w]+/")
				local has_path = filename:match("/")
				local starts_upper = filename:match("^%u")
				local valid_filename = has_extension or has_path or starts_upper
				local valid_language = not language:match("^%d+$")
				if valid_filename and valid_language then
					table.insert(headers, {
						line = i,
						filename = vim.trim(filename),
						language = vim.trim(language),
						step = nil,
					})
					header_set[i] = true
				end
			end
		end

		::continue::
	end

	return headers, header_set
end

return M
