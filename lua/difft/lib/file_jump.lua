-- luacheck: globals vim

--- File jumping utilities for difft
--- Provides line number extraction and file opening from difftastic output
local M = {}

--- Extract line number from a difftastic line
--- Handles multiple formats:
--- - Two-column: "number content ... number content"
--- - Ellipsis: ".. 20", "... 645"
--- - Single dot: ". 10"
--- - Side-by-side at start: "580 642"
--- - Single number: "6 import ..."
--- @param line_text string The line text to extract from
--- @param cursor_col number|nil Optional cursor column (0-indexed) for two-column detection
--- @return number|nil Extracted line number or nil
function M.extract_line_number(line_text, cursor_col)
	if not line_text or line_text == "" then
		return nil
	end

	-- Skip PURE ellipsis lines (just dots without a number)
	if line_text:match("^%s*%.%.+%s*$") then
		return nil
	end

	-- If cursor position provided, try to detect two-column format
	-- Format: "number content ... number content"
	if cursor_col then
		-- Try to find two separate "number + content" sections
		-- Pattern: number at start, then after some content, another number appears
		local left_num, left_end_pos = line_text:match("^%s*(%d+)%s+()")
		if left_num then
			-- Look for a second number that appears later in the line (potential right column)
			-- Skip past the left content and look for: multiple spaces + number
			-- We need at least 2 spaces as separator to distinguish from side-by-side numbers
			local remaining = line_text:sub(left_end_pos)
			local right_match_start, _, _, right_num = remaining:find("(%s%s+)(%d+)%s+")
			if right_num then
				-- Found two-column format: determine which column cursor is in
				-- Calculate absolute position of right column start (1-indexed)
				local right_col_start = left_end_pos - 1 + right_match_start
				-- Convert cursor_col from 0-indexed (Neovim API) to 1-indexed (Lua strings)
				local cursor_pos_1indexed = cursor_col + 1
				if cursor_pos_1indexed >= right_col_start then
					-- Cursor in right column
					return tonumber(right_num)
				else
					-- Cursor in left column
					return tonumber(left_num)
				end
			end
		end
	end

	-- Handle ellipsis with number: ".. 20", "... 645", ".... 2000"
	local ellipsis_num = line_text:match("^%s*%.%.+%s+(%d+)")
	if ellipsis_num then
		return tonumber(ellipsis_num)
	end

	-- Handle single dot with number (context line): ". 10", ". 123"
	local single_dot_num = line_text:match("^%s*%.%s+(%d+)")
	if single_dot_num then
		return tonumber(single_dot_num)
	end

	-- Try to match two numbers at the start (side-by-side format): "580 642"
	-- This is different from two-column - both numbers are at the line start
	local first_num, second_num = line_text:match("^%s*(%d+)%s+(%d+)")
	if first_num and second_num then
		-- Prefer the second (later/right) number
		return tonumber(second_num)
	end

	-- Single line number format: "6 import ..."
	local single_num = line_text:match("^%s*(%d+)%s")
	if single_num then
		return tonumber(single_num)
	end

	return nil
end

--- Find the nearest file header above the current line
--- Searches backwards through headers array to find the most recent header
--- @param headers table Array of header info {line, filename, language, step}
--- @param current_line number Line number (1-indexed) to search from
--- @return table|nil Header info {line, filename, language, step} or nil if not found
function M.find_header_above(headers, current_line)
	if not headers or #headers == 0 then
		return nil
	end

	-- Search backwards through headers to find the most recent one before current_line
	local nearest_header = nil
	for _, header_info in ipairs(headers) do
		if header_info.line < current_line then
			nearest_header = header_info
		else
			-- Headers are in ascending order, so we can stop once we pass current_line
			break
		end
	end

	return nearest_header
end

--- Parse first changed line number from diff content after a header
--- Looks for lines with green (DiffAdd) or red (DiffDelete) highlighting
--- @param buf number Buffer handle
--- @param start_line number Line number (1-indexed) to start scanning from
--- @param namespace number Namespace ID for extmarks
--- @return number|nil First line number found, or nil if not found
function M.parse_first_line_number(buf, start_line, namespace)
	-- Scan up to 50 lines forward looking for highlighted changes
	local max_lines = 50
	local total_lines = vim.api.nvim_buf_line_count(buf)
	local end_line = math.min(start_line + max_lines, total_lines)

	for line_num = start_line, end_line do
		-- Check if this line has DiffAdd or DiffDelete highlights using extmarks
		local extmarks = vim.api.nvim_buf_get_extmarks(
			buf,
			namespace,
			{ line_num - 1, 0 },
			{ line_num - 1, -1 },
			{ details = true }
		)

		-- Look for extmarks with DiffAdd or DiffDelete highlighting
		local is_changed_line = false
		for _, mark in ipairs(extmarks) do
			local details = mark[4]
			if details and details.hl_group then
				local hl = details.hl_group
				-- Check if highlight is DiffAdd or DiffDelete (including formatted variants like DiffAdd_bold)
				if hl:match("^DiffAdd") or hl:match("^DiffDelete") then
					is_changed_line = true
					break
				end
			end
		end

		-- If this is a changed line, extract the line number from the difftastic format
		if is_changed_line then
			local line = vim.api.nvim_buf_get_lines(buf, line_num - 1, line_num, false)[1]
			if line then
				-- After ANSI stripping, difftastic shows:
				-- Single number at start: " 6     import { ..." (added/modified line)
				-- Note: there may be leading whitespace before the line number
				local line_number = line:match("^%s*(%d+)%s")
				if line_number then
					return tonumber(line_number)
				end
			end
		end
	end

	return nil
end

--- Resolve file path from filename
--- Tries multiple resolution strategies:
--- 1. Check if file exists relative to current working directory
--- 2. Find VCS root (.git or .jj) and try relative to that
--- @param filename string The filename to resolve
--- @return string|nil Absolute filepath or nil if not found
function M.resolve_filepath(filename)
	-- Try multiple resolution strategies:
	-- 1. Check if file exists relative to current working directory
	if vim.fn.filereadable(filename) == 1 then
		-- File exists relative to CWD, make it absolute
		return vim.fn.fnamemodify(filename, ":p")
	end

	-- 2. Find VCS root and try relative to that
	local found = vim.fs.find(".git", { path = vim.fn.getcwd(), upward = true })
	if #found == 0 then
		found = vim.fs.find(".jj", { path = vim.fn.getcwd(), upward = true })
	end

	if #found > 0 then
		-- Get the directory containing .git or .jj
		local root_dir = vim.fs.dirname(found[1])
		local root_path = root_dir .. "/" .. filename

		if vim.fn.filereadable(root_path) == 1 then
			return root_path
		end
	end

	return nil
end

--- Open file from diff buffer at specified line
--- @param opts table Options:
---   - buf: number - Buffer containing diff
---   - win: number - Window containing diff
---   - headers: table - Array of header info {line, filename, language, step}
---   - namespace: number - Namespace ID for extmarks
---   - current_line: number - Current cursor line (1-indexed)
---   - cursor_col: number - Current cursor column (0-indexed)
---   - mode: string - Open mode: "edit", "vsplit", "split", or "tabedit"
---   - on_before_open: function|nil - Optional callback to call before opening file (e.g., close diffview)
---   - is_floating: boolean|nil - Whether the current window is floating (for context switching)
---   - line_number_settings: table|nil - Optional {number = bool, relativenumber = bool} to restore
--- @return boolean Success
function M.open_file_from_diff(opts)
	local buf = opts.buf
	local headers = opts.headers
	local namespace = opts.namespace
	local current_line = opts.current_line
	local cursor_col = opts.cursor_col
	local mode = opts.mode
	local on_before_open = opts.on_before_open
	local is_floating = opts.is_floating
	local line_number_settings = opts.line_number_settings

	-- Check if current line is a header
	local header_info = nil
	local line_num = nil
	for _, info in ipairs(headers) do
		if info.line == current_line then
			header_info = info
			break
		end
	end

	if header_info then
		-- On a header line - find first changed line
		line_num = M.parse_first_line_number(buf, current_line + 1, namespace)
	else
		-- Not on a header - extract line number from current line and find header above
		local line_text = vim.api.nvim_buf_get_lines(buf, current_line - 1, current_line, false)[1]
		if line_text then
			-- Pass cursor column for two-column detection
			line_num = M.extract_line_number(line_text, cursor_col)
			if line_num then
				header_info = M.find_header_above(headers, current_line)
			end
		end
	end

	if not header_info then
		return false
	end

	-- Get filename and resolve path
	local filename = header_info.filename
	local filepath = M.resolve_filepath(filename)

	-- Check if file was found
	if not filepath then
		vim.notify("File not found: " .. filename, vim.log.levels.WARN)
		return false
	end

	-- If in floating mode, we need to switch context to open file outside the float
	if is_floating then
		-- For splits, we need to ensure we're working in a regular window first
		-- Get the first valid non-floating window, or create one
		local target_win = nil
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			local win_config = vim.api.nvim_win_get_config(win)
			if win_config.relative == "" then -- Not a floating window
				target_win = win
				break
			end
		end

		-- If no regular window exists, create one by editing a buffer
		if not target_win then
			vim.cmd("enew")
		else
			vim.api.nvim_set_current_win(target_win)
		end
	end

	-- Call before-open callback (e.g., close diffview tab)
	if on_before_open then
		on_before_open()
	end

	-- Schedule the file opening to happen after diffview is fully closed
	vim.schedule(function()
		-- Open file with specified mode
		vim.cmd(mode .. " " .. vim.fn.fnameescape(filepath))

		-- Restore line number settings
		local current_win = vim.api.nvim_get_current_win()
		if vim.api.nvim_win_is_valid(current_win) then
			if line_number_settings then
				-- Use provided settings from caller
				vim.api.nvim_win_set_option(current_win, "number", line_number_settings.number)
				vim.api.nvim_win_set_option(current_win, "relativenumber", line_number_settings.relativenumber)
			else
				-- Fallback: check other normal buffers for user preference
				local found_reference = false
				for _, win in ipairs(vim.api.nvim_list_wins()) do
					if win ~= current_win then
						local win_buf = vim.api.nvim_win_get_buf(win)
						local buftype = vim.api.nvim_buf_get_option(win_buf, "buftype")
						if buftype == "" then
							local ref_number = vim.api.nvim_win_get_option(win, "number")
							local ref_relativenumber = vim.api.nvim_win_get_option(win, "relativenumber")
							vim.api.nvim_win_set_option(current_win, "number", ref_number)
							vim.api.nvim_win_set_option(current_win, "relativenumber", ref_relativenumber)
							found_reference = true
							break
						end
					end
				end

				-- Default to number = true if no reference found
				if not found_reference then
					vim.api.nvim_win_set_option(current_win, "number", true)
					vim.api.nvim_win_set_option(current_win, "relativenumber", false)
				end
			end
		end

		-- Jump to line number if found
		if line_num then
			-- Validate that line number exists in the opened file
			local current_buf = vim.api.nvim_get_current_buf()
			local total_lines = vim.api.nvim_buf_line_count(current_buf)

			if line_num <= total_lines then
				pcall(function()
					current_win = vim.api.nvim_get_current_win()
					if vim.api.nvim_win_is_valid(current_win) then
						vim.api.nvim_win_set_cursor(current_win, { line_num, 0 })
						vim.cmd("normal! zz")
					end
				end)
			end
			-- If line is out of bounds, silently do nothing (file might have changed since diff)
		end
	end)

	return true
end

return M
