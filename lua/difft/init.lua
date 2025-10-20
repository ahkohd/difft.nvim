-- luacheck: globals vim

--- A Neovim plugin for viewing difftastic output with ANSI color parsing
--- @class Difft
local M = {}

-- Import lib modules
local parser = require("difft.lib.parser")
local renderer = require("difft.lib.renderer")
local navigation = require("difft.lib.navigation")
local buffer = require("difft.lib.buffer")
local file_jump = require("difft.lib.file_jump")

--- Default configuration options
--- @class DifftConfig
--- @field keymaps table Keybindings for diff navigation
--- @field window table Window display options
--- @field command string Default diff command to execute
--- @field auto_jump boolean Auto jump to first change on open
--- @field layout string|nil Window layout: nil (buffer), "float", or "ivy_taller"
--- @field no_diff_message string Message to display when there are no changes
--- @field loading_message string Message to display while diff is loading
--- @field header table File header configuration
--- @field jump table File jump configuration: { enabled = boolean, ["<key>"] = "mode" }
--- @field diff table Diff configuration: { highlights = { add, delete, change, info, hint, dim } }
local config = {
	keymaps = {
		next = "<Down>",
		prev = "<Up>",
		close = "q",
		refresh = "r",
		first = "gg",
		last = "G",
	},
	window = {
		width = 0.9,
		height = 0.8,
		title = " Difft ",
		number = false,
		relativenumber = false,
		border = "rounded",
	},
	command = "jj diff --no-pager",
	auto_jump = true,
	-- nil (buffer), "float", or "ivy_taller"
	layout = nil,
	no_diff_message = "No changes found",
	loading_message = "Loading diff...",
	header = {
		content = nil, -- function(filename, step, language) -> string | table
		highlight = {
			link = nil,
			fg = nil,
			bg = nil,
			full_width = false,
		},
	},
	jump = {
		enabled = true, -- Try to jump to first changed line
		["<CR>"] = "edit",
		["<C-v>"] = "vsplit",
		["<C-x>"] = "split",
		["<C-t>"] = "tabedit",
	},
	diff = {
		highlights = {
			add = "DiffAdd", -- Highlight group for additions (green)
			delete = "DiffDelete", -- Highlight group for deletions (red)
			change = "DiffChange", -- Highlight group for changes (yellow)
			info = "DiagnosticInfo", -- Highlight group for info (blue/cyan)
			hint = "DiagnosticHint", -- Highlight group for hints (magenta)
			dim = "Comment", -- Highlight group for dim text (gray/white)
		},
	},
}

--- Internal state for the diff viewer
--- @class DifftState
--- @field buf number|nil Buffer handle for diff content
--- @field win number|nil Window handle for floating window
--- @field changes table List of line numbers containing file changes
--- @field current_change number Index of currently focused change
--- @field ns number Namespace ID for highlights
--- @field hl_cache table Cache for dynamically created highlight groups
--- @field is_floating boolean Whether the current diff is in a floating window
--- @field last_cursor table|nil Last cursor position {line, col} - saved on hide/refresh, restored on show/refresh
--- @field goal_column number|nil Desired column position for vertical navigation (Vim-style)
local state = {
	buf = nil,
	win = nil,
	changes = {},
	current_change = 0,
	ns = vim.api.nvim_create_namespace("difft_highlights"),
	hl_cache = {},
	is_floating = false,
	last_cursor = nil,
	goal_column = nil,
}

--- Normalize diff highlights - convert table configs to highlight groups
--- @param highlights table User highlight config (string or table values)
--- @return table Normalized config with group name strings
local function normalize_diff_highlights(highlights)
	local normalized = {}

	for key, value in pairs(highlights) do
		if type(value) == "string" then
			-- Already a group name, use as-is
			normalized[key] = value
		elseif type(value) == "table" then
			-- Create a custom highlight group
			local group_name = "DifftAnsi" .. key:sub(1,1):upper() .. key:sub(2)  -- e.g., "DifftAnsiAdd"

			-- Handle link
			if value.link then
				vim.api.nvim_set_hl(0, group_name, { link = value.link })
				normalized[key] = group_name
				goto continue
			end

			-- Handle direct colors
			local hl_opts = {}
			if value.fg then
				hl_opts.fg = value.fg
			end
			if value.bg then
				hl_opts.bg = value.bg
			end

			-- Set the highlight group (this will overwrite any existing definition)
			if next(hl_opts) then
				-- Clear any existing link first
				vim.api.nvim_set_hl(0, group_name, {})
				vim.api.nvim_set_hl(0, group_name, hl_opts)
				normalized[key] = group_name
			else
				-- No valid properties, skip
				normalized[key] = nil
			end

			::continue::
		end
	end

	return normalized
end

-- Normalize diff highlights and initialize ANSI color mapping
local normalized_highlights = normalize_diff_highlights(config.diff.highlights)
local normalized_config = vim.tbl_deep_extend("force", config, {
	diff = { highlights = normalized_highlights }
})
parser.init_ansi_mapping(normalized_config)

--- Setup custom header highlight group if configured
local function setup_header_highlight()
	local hl_config = config.header.highlight
	if not hl_config or not (hl_config.link or hl_config.fg or hl_config.bg) then
		return
	end

	-- Check if user wants to link to another highlight group (simple link)
	if hl_config.link then
		vim.api.nvim_set_hl(0, "DifftFileHeader", { link = hl_config.link })
		-- Create background-only version for full_width
		local linked_hl = vim.api.nvim_get_hl(0, { name = hl_config.link, link = false })
		if linked_hl.bg then
			vim.api.nvim_set_hl(0, "DifftFileHeaderBg", { bg = linked_hl.bg })
		end
		return
	end

	-- Create highlight group with custom colors or linked colors
	local hl_opts = {}
	local bg_only = {}

	-- Handle fg (can be a color string or { link = "Group" })
	if hl_config.fg then
		if type(hl_config.fg) == "table" and hl_config.fg.link then
			-- Link fg to another highlight group
			local linked_hl = vim.api.nvim_get_hl(0, { name = hl_config.fg.link })
			if linked_hl.fg then
				hl_opts.fg = linked_hl.fg
			end
		else
			-- Direct color value
			hl_opts.fg = hl_config.fg
		end
	end

	-- Handle bg (can be a color string or { link = "Group" })
	if hl_config.bg then
		if type(hl_config.bg) == "table" and hl_config.bg.link then
			-- Link bg to another highlight group
			local linked_hl = vim.api.nvim_get_hl(0, { name = hl_config.bg.link })
			if linked_hl.bg then
				hl_opts.bg = linked_hl.bg
				bg_only.bg = linked_hl.bg
			end
		else
			-- Direct color value
			hl_opts.bg = hl_config.bg
			bg_only.bg = hl_config.bg
		end
	end

	-- Create main highlight with both fg and bg
	if next(hl_opts) then
		vim.api.nvim_set_hl(0, "DifftFileHeader", hl_opts)
	end

	-- Create background-only version for full_width
	if next(bg_only) then
		vim.api.nvim_set_hl(0, "DifftFileHeaderBg", bg_only)
	end
end

--- Get centered floating window layout configuration
--- @return table Window configuration for nvim_open_win
local function get_float_layout()
	local width = math.floor(vim.o.columns * config.window.width)
	local height = math.floor(vim.o.lines * config.window.height)
	local col = math.floor((vim.o.columns - width) / 2)
	local row = math.floor((vim.o.lines - height) / 2)

	return {
		relative = "editor",
		width = width,
		height = height,
		col = col,
		row = row,
		style = "minimal",
		border = config.window.border,
		title = config.window.title,
		title_pos = "center",
	}
end

--- Get ivy-style bottom window layout configuration
--- @return table Window configuration for nvim_open_win
local function get_ivy_taller_layout()
	local width = vim.o.columns
	local height = math.floor(vim.o.lines * config.window.height)
	local col = 0
	local row = vim.o.lines - height

	return {
		relative = "editor",
		width = width,
		height = height,
		col = col,
		row = row,
		style = "minimal",
		border = config.window.border,
		title = config.window.title,
		title_pos = "center",
	}
end

--- Get or create a highlight group with formatting attributes
--- Dynamically creates highlight groups that inherit from base with bold/italic
--- @param base_hl string Base highlight group name
--- @param bold boolean Apply bold formatting
--- @param italic boolean Apply italic formatting
--- @param dim boolean Apply dim formatting (handled via base_hl)
--- @return string Highlight group name
local function get_highlight_with_format(base_hl, bold, italic, dim)
	if not bold and not italic and not dim then
		return base_hl
	end

	-- Create a unique key for this combination
	local key = base_hl .. (bold and "_bold" or "") .. (italic and "_italic" or "") .. (dim and "_dim" or "")

	-- Return cached highlight if it exists
	if state.hl_cache[key] then
		return state.hl_cache[key]
	end

	-- Get the base highlight properties
	local base_props = vim.api.nvim_get_hl(0, { name = base_hl })

	-- Add formatting attributes
	-- Only set attributes that are explicitly enabled (true)
	-- nil or false means "inherit from base", so we don't override
	local format_attrs = {}
	if bold then
		format_attrs.bold = true
	end
	if italic then
		format_attrs.italic = true
	end
	-- Dim is handled by using Comment for base_hl, so we don't need to set it here

	local new_props = vim.tbl_extend("force", base_props, format_attrs)

	-- Create the new highlight group
	vim.api.nvim_set_hl(0, key, new_props)

	-- Cache it
	state.hl_cache[key] = key

	return key
end

--- Parse ANSI escape codes from a line and return clean text + highlights
--- Extracts ANSI color codes and formatting, returns clean text and highlight info
--- @param line string Raw line with ANSI escape codes
--- @return string clean_text Text with ANSI codes stripped
--- @return table highlights List of highlight regions with col, length, and hl_group
local function parse_ansi_line(line)
	local text_parts = {}
	local highlights = {}
	local current_hl = nil
	local bold = false
	local italic = false
	local dim = false
	local col = 0
	local pos = 1

	while pos <= #line do
		-- Try to match ANSI escape sequence: ESC[<numbers>m
		local esc_start, esc_end, codes = line:find("\27%[([%d;]+)m", pos)

		if not esc_start then
			-- No more escape codes, append rest of line
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

		-- Append text before escape code
		local text_chunk = line:sub(pos, esc_start - 1)
		if #text_chunk > 0 then
			table.insert(text_parts, text_chunk)
			if current_hl then
				table.insert(highlights, {
					col = col,
					length = #text_chunk,
					hl_group = get_highlight_with_format(current_hl, bold, italic, dim),
				})
			end
			col = col + #text_chunk
		end

		-- Parse the color code(s)
		for code in codes:gmatch("%d+") do
			if code == "0" then
				-- Reset all
				current_hl = nil
				bold = false
				italic = false
				dim = false
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
			elseif ansi_to_hl[code] then
				current_hl = ansi_to_hl[code]
			end
		end

		pos = esc_end + 1
	end

	return table.concat(text_parts), highlights
end

--- Apply highlights to a buffer line using extmarks
--- Sets both gutter line number color and text highlights
--- @param buf number Buffer handle
--- @param line_num number Line number (0-indexed)
--- @param highlights table List of highlight regions from parse_ansi_line
--- @param line_text string Clean text of the line
local function apply_line_highlights(buf, line_num, highlights, line_text)
	-- Determine line number color based on line type
	-- Check if highlight group starts with a diff type (handles formatted variants)
	local line_number_hl = nil
	for _, hl in ipairs(highlights) do
		local hl_group = hl.hl_group
		if hl_group:find("^DiffAdd") then
			line_number_hl = "DiffAdd"
			break
		elseif hl_group:find("^DiffDelete") then
			line_number_hl = "DiffDelete"
			break
		elseif hl_group:find("^DiffChange") then
			line_number_hl = "DiffChange"
			break
		end
	end

	-- Set Neovim gutter line number color if detected
	if line_number_hl then
		pcall(vim.api.nvim_buf_set_extmark, buf, state.ns, line_num, 0, {
			end_col = #line_text,
			number_hl_group = line_number_hl,
			priority = 50,
		})
	end

	-- Apply text highlights from ANSI codes (includes line numbers and ellipsis)
	for _, hl in ipairs(highlights) do
		if hl.hl_group then
			pcall(vim.api.nvim_buf_set_extmark, buf, state.ns, line_num, hl.col, {
				end_col = hl.col + hl.length,
				hl_group = hl.hl_group,
				priority = 110,
			})
		end
	end
end

--- Apply custom header highlighting to file header lines
--- @param buf number Buffer handle
--- @param line_num number Line number (1-indexed) to apply highlight
--- @param line_text string Clean text of the line
--- @param has_custom_highlights boolean Whether this line already has custom highlights from content function
local function apply_header_highlight(buf, line_num, line_text, has_custom_highlights)
	local hl_config = config.header.highlight
	if not hl_config or not (hl_config.link or hl_config.fg or hl_config.bg) then
		return
	end

	-- Build extmark options
	local extmark_opts = {
		priority = 150, -- Higher than ANSI highlights (110)
	}

	-- If there are no custom highlights from content function, apply text highlights
	if not has_custom_highlights then
		extmark_opts.hl_group = "DifftFileHeader"
		extmark_opts.end_col = math.max(1, #line_text)
	end

	-- Additionally extend background to full window width if configured
	-- Use background-only highlight group to avoid overriding custom icon foreground
	if hl_config.full_width then
		extmark_opts.line_hl_group = "DifftFileHeaderBg"
	end

	-- Only apply if we have something to set
	if extmark_opts.hl_group or extmark_opts.line_hl_group then
		local success, err = pcall(vim.api.nvim_buf_set_extmark, buf, state.ns, line_num - 1, 0, extmark_opts)
		if not success then
			vim.notify("Failed to apply header highlight: " .. tostring(err), vim.log.levels.WARN)
		end
	end
end

--- Parse file change headers from diff output
--- Detects difftastic file headers (e.g., "path/to/file.lua --- 1/2 --- Lua")
--- @param lines table List of clean text lines
--- @return table List of header info: {{line=number, filename=string, language=string, step={current, of}}, ...}
local function parse_changes(lines)
	local changes = {}

	for i, line in ipairs(lines) do
		-- Detect file headers in difftastic format with optional step information
		-- Format: "lua/plugins/diff.lua --- 1/10 --- Lua"
		-- Language can have spaces like "TypeScript TSX"
		-- Headers must contain "---" separator and have both filename and language parts

		-- Only process lines that contain "---" to avoid matching plain numbers
		if not line:match("%-%-%-%s+") then
			goto continue
		end

		local pattern_with_step = "^([%w_/%-%.][^%s]*)%s+%-%-%-%s+(%d+)/(%d+)%s+%-%-%-%s+(.+)$"
		local filename, step_current, step_of, language = line:match(pattern_with_step)

		if filename and step_current and step_of and language then
			-- Validate: filename should contain a path separator or extension or start with uppercase
			-- Language should not be just digits
			local valid_filename = filename:match("[/.]") or filename:match("^%u")
			local valid_language = not language:match("^%d+$")
			if valid_filename and valid_language then
				table.insert(changes, {
					line = i,
					filename = vim.trim(filename),
					language = vim.trim(language),
					step = {
						current = tonumber(step_current),
						of = tonumber(step_of),
					},
				})
			end
		else
			-- Try without step info: "lua/plugins/diff.lua --- Lua" or "file.tsx --- TypeScript TSX"
			local pattern_no_step = "^([%w_/%-%.][^%s]*)%s+%-%-%-%s+(.+)$"
			filename, language = line:match(pattern_no_step)
			if filename and language then
				-- Validate: filename should contain a path separator or extension or start with uppercase
				-- Language should not be just digits
				local valid_filename = filename:match("[/.]") or filename:match("^%u")
				local valid_language = not language:match("^%d+$")
				if valid_filename and valid_language then
					table.insert(changes, {
						line = i,
						filename = vim.trim(filename),
						language = vim.trim(language),
						step = nil,
					})
				end
			end
		end

		::continue::
	end

	return changes
end

--- Set cursor position while preserving goal column (Vim-style behavior)
--- @param line number Target line number
local function set_cursor_with_goal_column(line)
	-- Always update goal_column from current cursor position
	-- This picks up manual cursor movements (h, l, $, ^, etc.) between navigations
	local current_pos = vim.api.nvim_win_get_cursor(state.win)
	state.goal_column = current_pos[2]

	-- Get the length of the target line (0-indexed column count)
	local line_text = vim.api.nvim_buf_get_lines(state.buf, line - 1, line, false)[1] or ""
	local line_length = #line_text

	-- Clamp goal column to line length
	local col = math.min(state.goal_column, line_length)

	-- Set cursor position
	vim.api.nvim_win_set_cursor(state.win, { line, col })
end

--- Navigate to next file change
local function next_change()
	if #state.changes == 0 then
		return
	end

	state.current_change = state.current_change + 1
	if state.current_change > #state.changes then
		state.current_change = 1
	end

	local line = state.changes[state.current_change].line
	set_cursor_with_goal_column(line)
	vim.cmd("normal! zz")
end

--- Navigate to previous file change
local function prev_change()
	if #state.changes == 0 then
		return
	end

	state.current_change = state.current_change - 1
	if state.current_change < 1 then
		state.current_change = #state.changes
	end

	local line = state.changes[state.current_change].line
	set_cursor_with_goal_column(line)
	vim.cmd("normal! zz")
end

--- Navigate to first file change
local function first_change()
	if #state.changes == 0 then
		return
	end

	state.current_change = 1
	local line = state.changes[state.current_change].line
	set_cursor_with_goal_column(line)
	vim.cmd("normal! zz")
end

--- Navigate to last file change
local function last_change()
	if #state.changes == 0 then
		return
	end

	state.current_change = #state.changes
	local line = state.changes[state.current_change].line
	set_cursor_with_goal_column(line)
	vim.cmd("normal! zz")
end

--- Extract line number from a diff line based on cursor position
--- Handles multiple formats:
--- - Two-column: "number content     number content" (cursor-aware)
--- - Side-by-side numbers: "580 642 ..." → 642 (prefers second/right number)
--- - Ellipsis: "... 645" → 645
--- - Single dot: ". 10" → 10 (context line)
--- - Single number: "6 import ..." → 6
--- @param line_text string The line text to parse
--- @param cursor_col number|nil Optional cursor column (0-indexed), for two-column detection
--- @return number|nil Line number if found, nil otherwise

--- Open file from header in specified mode
--- @param mode string Open mode: "edit", "vsplit", "split", or "tabedit"
local function open_file(mode)
	if not config.jump.enabled then
		return
	end

	local cursor = vim.api.nvim_win_get_cursor(state.win)
	local current_line = cursor[1]
	local cursor_col = cursor[2]

	-- If in floating mode, save cursor position before opening file
	local on_before_open = nil
	if state.is_floating then
		on_before_open = function()
			-- Save cursor position before hiding
			if state.win and vim.api.nvim_win_is_valid(state.win) then
				state.last_cursor = vim.api.nvim_win_get_cursor(state.win)
				vim.api.nvim_win_hide(state.win)
				state.win = nil -- Clear win reference so it's detected as hidden
			end
		end
	end

	-- Use lib/file_jump to open file
	file_jump.open_file_from_diff({
		buf = state.buf,
		win = state.win,
		headers = state.changes,
		namespace = state.ns,
		current_line = current_line,
		cursor_col = cursor_col,
		mode = mode,
		on_before_open = on_before_open,
		is_floating = state.is_floating,
	})
end

--- Close the diff window and cleanup state
local function close_diff()
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, true)
	end
	state.buf = nil
	state.win = nil
	state.changes = {}
	state.current_change = 0
	state.hl_cache = {} -- Clear highlight cache
	state.is_floating = false
end

--- Apply custom header content if configured
--- Replaces header lines with custom content from user function
--- @param buf number Buffer handle
--- @return table Set of line numbers that have custom highlights (for avoiding double-highlighting)
local function apply_custom_header_content(buf)
	if not config.header.content or type(config.header.content) ~= "function" then
		return {}
	end

	local has_custom_highlights = {}

	for _, header_info in ipairs(state.changes) do
		-- Use step from difftastic if available, otherwise pass nil
		local step = header_info.step
		local success, result = pcall(config.header.content, header_info.filename, step, header_info.language)

		if not success then
			vim.notify("Error in header.content function: " .. tostring(result), vim.log.levels.ERROR)
			goto continue
		end

		if not result then
			goto continue
		end

		local line_num = header_info.line

		if type(result) == "string" then
			-- Simple string result - replace the line
			vim.api.nvim_buf_set_lines(buf, line_num - 1, line_num, false, { result })

		elseif type(result) == "table" then
			-- Table of {text, hl_group} pairs
			local text_parts = {}
			local highlights = {}
			local col = 0

			-- Check if there's a fallback header highlight configured
			local hl_config = config.header.highlight
			local has_fallback = hl_config and (hl_config.link or hl_config.fg or hl_config.bg)

			for _, item in ipairs(result) do
				if type(item) ~= "table" or #item < 1 then
					goto continue_item
				end

				local text = tostring(item[1] or "")
				local hl_group = item[2]

				table.insert(text_parts, text)

				if #text > 0 then
					-- Use provided highlight group, or fallback to DifftFileHeader if configured
					local final_hl = hl_group or (has_fallback and "DifftFileHeader" or nil)
					if final_hl then
						table.insert(highlights, {
							col = col,
							end_col = col + #text,
							hl_group = final_hl,
						})
					end
				end

				col = col + #text
				::continue_item::
			end

			local full_text = table.concat(text_parts)
			vim.api.nvim_buf_set_lines(buf, line_num - 1, line_num, false, { full_text })

			-- Apply highlights
			for _, hl in ipairs(highlights) do
				pcall(vim.api.nvim_buf_set_extmark, buf, state.ns, line_num - 1, hl.col, {
					end_col = hl.end_col,
					hl_group = hl.hl_group,
					priority = 150, -- Same as header highlights
				})
			end

			-- Mark this line as having custom highlights
			has_custom_highlights[line_num] = true
		end

		::continue::
	end

	return has_custom_highlights
end

--- Load diff output from command and apply highlights
--- Executes diff command, parses ANSI codes, and applies highlights to buffer
--- @param cmd string|nil Optional custom command, uses config.command if nil
local function load_diff(cmd)
	local buf = state.buf
	local win = state.win

	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	-- Clear existing highlights
	vim.api.nvim_buf_clear_namespace(buf, state.ns, 0, -1)

	-- Make buffer modifiable to update content
	vim.api.nvim_buf_set_option(buf, "modifiable", true)

	-- Set loading message
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { config.loading_message })

	-- Calculate COLUMNS based on window width
	local columns = "10000" -- Default fallback
	if win and vim.api.nvim_win_is_valid(win) then
		columns = tostring(vim.api.nvim_win_get_width(win))
	end

	-- Execute diff command
	vim.fn.jobstart(cmd or config.command, {
		env = {
			COLUMNS = columns,
		},
		stdout_buffered = true,
		on_stdout = function(_, data)
			if not data then
				return
			end

			-- Remove empty last line if present
			if data[#data] == "" then
				table.remove(data)
			end

			vim.schedule(function()
				if not vim.api.nvim_buf_is_valid(buf) then
					return
				end

				-- Ensure buffer is modifiable (protects against race conditions on rapid resizes)
				vim.api.nvim_buf_set_option(buf, "modifiable", true)

				-- Check if diff is empty
				if #data == 0 or (#data == 1 and data[1] == "") then
					-- Display custom "no diff" message
					vim.api.nvim_buf_set_lines(buf, 0, -1, false, { config.no_diff_message })
					vim.api.nvim_buf_set_option(buf, "modifiable", false)
					return
				end

				-- Parse ANSI codes and clean text
					-- Use lib/buffer to setup the buffer with ANSI parsing, rendering, and navigation
					local result = buffer.setup_from_ansi_lines(buf, data, config, state.ns, {
						renderer_opts = {
							line_number_coloring = true,
							empty_line_support = true,
						},
						navigation = {
							enabled = true,
							keymaps = config.keymaps,
							auto_jump = false, -- We handle cursor positioning manually below
						},
					})

					-- Store headers for compatibility with existing code
					state.changes = result.headers

					-- Make buffer read-only
					vim.api.nvim_buf_set_option(buf, "modifiable", false)

					-- Restore last cursor position if available (for all modes), otherwise use auto_jump logic
					if state.last_cursor then
						-- Validate the saved position is still valid
						local total_lines = vim.api.nvim_buf_line_count(buf)
						if state.last_cursor[1] <= total_lines then
							pcall(vim.api.nvim_win_set_cursor, win, state.last_cursor)
						else
							-- Fallback to last line if saved position is out of bounds
							vim.api.nvim_win_set_cursor(win, { total_lines, 0 })
						end
						vim.cmd("normal! zz")
					elseif config.auto_jump and #state.changes > 0 then
						-- Jump to first change if available and auto_jump is enabled
						vim.api.nvim_win_set_cursor(win, { state.changes[1].line, 0 })
						vim.cmd("normal! zz")
					else
						-- Jump to top
						vim.api.nvim_win_set_cursor(win, { 1, 0 })
					end
			end)
		end,
		on_stderr = function(_, data)
			if data and #data > 0 and data[1] ~= "" then
				vim.schedule(function()
					vim.notify("Error running diff command: " .. table.concat(data, "\n"), vim.log.levels.ERROR)
				end)
			end
		end,
	})
end

--- Refresh the current diff by reloading
local function refresh_diff()
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end

	-- Save cursor position before refresh (for all modes)
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		state.last_cursor = vim.api.nvim_win_get_cursor(state.win)
	end

	load_diff()
end

--- Resize floating window to match new terminal dimensions
local function resize_float()
	if not state.is_floating or not state.win or not vim.api.nvim_win_is_valid(state.win) then
		return
	end

	-- Get new window configuration based on current layout
	local win_config
	if config.layout == "float" then
		win_config = get_float_layout()
	elseif config.layout == "ivy_taller" then
		win_config = get_ivy_taller_layout()
	else
		return
	end

	-- Update window configuration
	vim.api.nvim_win_set_config(state.win, win_config)
end

--- Setup buffer-local keymaps for non-navigation actions (close, refresh, jump)
--- Navigation keymaps (next/prev/first/last) are handled by lib/navigation.setup()
--- @param buf number Buffer handle
--- @param is_floating boolean Whether this is a floating window
local function setup_keymaps(buf, is_floating)
	-- Only add close keymap for floating windows
	if is_floating then
		vim.keymap.set("n", config.keymaps.close, close_diff, {
			buffer = buf,
			noremap = true,
			silent = true,
			desc = "Close diff",
		})
	end

	vim.keymap.set("n", config.keymaps.refresh, refresh_diff, {
		buffer = buf,
		noremap = true,
		silent = true,
		desc = "Refresh diff",
	})

	-- Setup jump keybinds if enabled
	if config.jump and config.jump.enabled then
		for key, mode in pairs(config.jump) do
			if key ~= "enabled" then
				vim.keymap.set("n", key, function()
					open_file(mode)
				end, {
					buffer = buf,
					noremap = true,
					silent = true,
					desc = "Open file in " .. mode,
				})
			end
		end
	end
end

--- View diff output in a window or buffer
--- Creates a window/buffer and loads diff output from command
--- @param opts table|nil Optional configuration
--- @field cmd string|nil Custom diff command to run (overrides config.command)
--- @usage require("difft").diff()
--- @usage require("difft").diff({cmd = "git diff"})
function M.diff(opts)
	opts = opts or {}

	local layout = config.layout
	local is_floating = (layout == "float" or layout == "ivy_taller")

	-- For floating windows: check if buffer exists and window is hidden
	if is_floating and state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		-- Window is hidden - show the existing buffer with cached content
		local win_config
		if layout == "float" then
			win_config = get_float_layout()
		else -- ivy_taller
			win_config = get_ivy_taller_layout()
		end

		local win = vim.api.nvim_open_win(state.buf, true, win_config)
		state.win = win

		-- Restore cursor position if saved
		if state.last_cursor then
			pcall(vim.api.nvim_win_set_cursor, win, state.last_cursor)
			vim.cmd("normal! zz")
		end

		return
	end

	-- Create buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(buf, "bufhidden", "hide") -- Keep buffer when window is hidden
	vim.api.nvim_buf_set_option(buf, "filetype", "difft")

	local win

	-- Open window based on layout
	if layout == "float" then
		local win_config = get_float_layout()
		win = vim.api.nvim_open_win(buf, true, win_config)
	elseif layout == "ivy_taller" then
		local win_config = get_ivy_taller_layout()
		win = vim.api.nvim_open_win(buf, true, win_config)
	else
		-- Default: open in current window (buffer mode)
		vim.api.nvim_set_current_buf(buf)
		win = vim.api.nvim_get_current_win()
	end

	state.buf = buf
	state.win = win
	state.is_floating = is_floating

	-- Configure line numbers if enabled
	if config.window.number then
		vim.api.nvim_win_set_option(win, "number", true)
	end
	if config.window.relativenumber then
		vim.api.nvim_win_set_option(win, "relativenumber", true)
	end

	-- Setup keymaps
	setup_keymaps(buf, is_floating)

	-- Load diff content with custom command if provided
	load_diff(opts.cmd)
end

--- Close diff window and cleanup state
--- @usage require("difft").close()
function M.close()
	close_diff()
end

--- Hide diff window but keep buffer (floating windows only)
--- @usage require("difft").hide()
function M.hide()
	if not state.is_floating then
		return
	end

	if state.win and vim.api.nvim_win_is_valid(state.win) then
		state.last_cursor = vim.api.nvim_win_get_cursor(state.win)
		vim.api.nvim_win_hide(state.win)
		state.win = nil
	end
end

--- Check if diff buffer exists
--- @return boolean True if diff buffer exists
--- @usage if require("difft").exists() then ... end
function M.exists()
	return state.buf ~= nil and vim.api.nvim_buf_is_valid(state.buf)
end

--- Check if diff window is visible
--- @return boolean True if diff window is currently visible
--- @usage if require("difft").is_visible() then ... end
function M.is_visible()
	return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

--- Refresh the current diff
--- @usage require("difft").refresh()
function M.refresh()
	refresh_diff()
end

--- Setup the plugin with custom configuration
--- Merges user config with defaults and sets up autocommands
--- @param opts DifftConfig|nil User configuration options
--- @usage require("difft").setup({
---   command = "git diff",
---   layout = "ivy_taller",
---   window = {
---     number = true,
---     border = "single",  -- "none", "single", "double", "rounded", "solid", "shadow", or custom array
---   },
---   header = {
---     -- Option 1: Simple string return
---     content = function(filename, step, language)
---       return string.format("[%d/%d] %s (%s)", step.current, step.of, filename, language)
---     end,
---     -- Option 2: Table with custom highlights (for icons, etc)
---     -- content = function(filename, step, language)
---     --   local devicons = require("nvim-web-devicons")
---     --   local icon, hl = devicons.get_icon(filename)
---     --   return {
---     --     {"[" .. step.current .. "/" .. step.of .. "] ", "Comment"},
---     --     {icon .. " ", hl or "Normal"},
---     --     {filename, "Normal"},
---     --     {" --- " .. language, "Comment"},
---     --   }
---     -- end,
---     highlight = {
---       -- Option 1: Link entire highlight to another group
---       link = "FloatTitle",
---       -- Option 2: Custom colors
---       -- fg = "#ffffff",
---       -- bg = "#5c6370",
---       -- Option 3: Link fg and bg separately
---       -- fg = { link = "Statement" },
---       -- bg = { link = "Visual" },
---       -- Option 4: Mix linked and custom colors
---       -- fg = { link = "Statement" },
---       -- bg = "#5c6370",
---       full_width = false,  -- Extend to full window width (default: false)
---     }
---   },
---   jump = {
---     enabled = true,  -- Enable file jump functionality
---     ["<CR>"] = "edit",
---     ["<C-v>"] = "vsplit",
---     ["<C-x>"] = "split",
---     ["<C-t>"] = "tabedit",
---   }
--- })
function M.setup(opts)
	opts = opts or {}
	config = vim.tbl_deep_extend("force", config, opts)

	-- Normalize diff highlights and initialize ANSI color mapping
	local normalized_highlights = normalize_diff_highlights(config.diff.highlights)
	local normalized_config = vim.tbl_deep_extend("force", config, {
		diff = { highlights = normalized_highlights }
	})
	parser.init_ansi_mapping(normalized_config)

	-- Setup custom header highlight if configured
	setup_header_highlight()

	-- Clear highlight cache when colorscheme changes
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("difft_colorscheme", { clear = true }),
		callback = function()
			parser.clear_hl_cache()
			-- Recreate custom highlights on colorscheme change
			local norm_highlights = normalize_diff_highlights(config.diff.highlights)
			local norm_config = vim.tbl_deep_extend("force", config, {
				diff = { highlights = norm_highlights }
			})
			parser.init_ansi_mapping(norm_config)
			setup_header_highlight()
		end,
	})

	-- Auto-resize floating window on terminal resize
	vim.api.nvim_create_autocmd("VimResized", {
		group = vim.api.nvim_create_augroup("difft_resize", { clear = true }),
		callback = function()
			-- Only resize if diff is visible and in floating mode
			if state.is_floating and M.is_visible() then
				resize_float()  -- Resize window to match new terminal dimensions
			end
		end,
	})
end

-- Store globally for access
_G.Difft = {
	diff = M.diff,
	close = M.close,
	hide = M.hide,
	exists = M.exists,
	is_visible = M.is_visible,
	refresh = M.refresh,
}

--- Get current config (always returns the latest config after setup)
--- @return DifftConfig
function M.get_config()
	return config
end

-- Expose internal functions for testing
-- Expose lib modules for testing and internal use (e.g., diffview extension)
M.lib = {
	parser = parser,
	renderer = renderer,
	navigation = navigation,
	buffer = buffer,
}

-- Legacy _test export for backwards compatibility with existing code
M._test = {
	parse_ansi_line = parser.parse_ansi_line,
	parse_changes = parse_changes,
	parse_first_line_number = function(buf, start_line)
		return file_jump.parse_first_line_number(buf, start_line, state.ns)
	end,
	extract_line_number = file_jump.extract_line_number,
	find_header_above = function(current_line)
		return file_jump.find_header_above(state.changes, current_line)
	end,
	state = state,
	config = config,
}

return M

-- vim:noet:ts=4:sts=4:sw=4:
