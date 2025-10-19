-- luacheck: globals vim

--- Column splitting utilities for side-by-side difftastic output
local M = {}

--- Check if there's a gutter (whitespace gap) at the split position across all lines
--- @param lines table List of lines to check
--- @param start_line number Start line index
--- @param end_line number End line index
--- @param split_col number The split column to check
--- @return boolean true if ALL lines have whitespace at split_col
local function has_gutter_at_split(lines, start_line, end_line, split_col)
	for i = start_line, end_line do
		local line = lines[i]
		if line and #line >= split_col then
			-- Check if the character at split_col is whitespace
			local char = line:sub(split_col, split_col)
			if not char:match("%s") then
				return false  -- Found non-whitespace, not side-by-side
			end
		end
	end
	return true  -- All lines have whitespace at split_col
end

--- Determine split column for a section
--- @param lines table List of lines
--- @param start_line number Section start line
--- @param end_line number Section end line
--- @param max_width number Max width in this section
--- @param width number The difftastic width
--- @return number Split column (0 if single-column)
local function determine_split_column(lines, start_line, end_line, max_width, width)
	local width_half = math.floor(width / 2)

	-- First check if column width/2 has gutter
	if has_gutter_at_split(lines, start_line, end_line, width_half) then
		return width_half
	end

	-- Check if max_width/2 has gutter
	local max_half = math.floor(max_width / 2)
	if has_gutter_at_split(lines, start_line, end_line, max_half) then
		return max_half
	end

	-- No gutter found, single-column
	return 0
end

--- Calculate split columns per section (between headers)
--- Each section gets its own split column based on its max width
--- @param lines table List of clean text lines
--- @param header_lines table Set of header line numbers
--- @param width number The difftastic width (default: 100)
--- @return table Map of line number to split column
function M.calculate_split_columns_per_section(lines, header_lines, width)
	width = width or 100
	local split_columns = {}
	local current_section_start = nil
	local current_section_max_width = 0

	for i, line in ipairs(lines) do
		if header_lines[i] then
			-- Found a header - finalize previous section if exists
			if current_section_start then
				local split_col = determine_split_column(lines, current_section_start, i - 1, current_section_max_width, width)
				-- Apply split column to all lines in the section
				for j = current_section_start, i - 1 do
					split_columns[j] = split_col
				end
			end

			-- Start a new section
			current_section_start = i + 1  -- Section starts after header
			current_section_max_width = 0
		elseif not line:match("^%s*$") then  -- Skip empty lines when calculating max width
			-- Content line - update max width for current section
			if not current_section_start then
				current_section_start = i  -- First line before any header
			end
			if #line > current_section_max_width then
				current_section_max_width = #line
			end
		end
	end

	-- Finalize last section
	if current_section_start then
		local split_col = determine_split_column(lines, current_section_start, #lines, current_section_max_width, width)
		for j = current_section_start, #lines do
			split_columns[j] = split_col
		end
	end

	return split_columns
end

--- Split side-by-side lines into left and right columns
--- @param lines table List of clean text lines
--- @param split_columns table Map of line number to split column
--- @param header_lines table|nil Set of header line numbers (1-indexed) to skip splitting
--- @return table left_lines Lines for left pane
--- @return table right_lines Lines for right pane
--- @return table trim_info Info about trimming: {left_trim, right_trim} per line
function M.split_lines(lines, split_columns, header_lines)
	local left_lines = {}
	local right_lines = {}
	local trim_info = {}
	header_lines = header_lines or {}

	for i, line in ipairs(lines) do
		-- Check if this is a header line
		if header_lines[i] then
			-- Headers go to both left and right (for navigation support on both sides)
			table.insert(left_lines, line)
			table.insert(right_lines, line)
			trim_info[i] = {left_trim = 0, right_trim = 0}
		else
			-- Get split column for this line
			local split_column = split_columns[i] or 0

			if split_column == 0 or #line < split_column then
				-- No split column or line too short - go entirely to left
				table.insert(left_lines, line)
				table.insert(right_lines, "")
				trim_info[i] = {left_trim = 0, right_trim = 0}
			else
				-- Split the line at the section's split column
				local left = line:sub(1, split_column)
				local right = line:sub(split_column + 1)

				-- Count how much whitespace we'll trim
				local left_before_trim = #left
				local right_before_trim = #right

				-- Trim trailing whitespace from left (removes the gutter)
				left = left:gsub("%s+$", "")
				local left_trimmed = left_before_trim - #left

				-- Trim leading whitespace from right (clean up the split)
				local right_leading_spaces = right:match("^(%s+)")
				local right_trimmed = right_leading_spaces and #right_leading_spaces or 0
				right = right:gsub("^%s+", "")

				table.insert(left_lines, left)
				table.insert(right_lines, right)
				trim_info[i] = {left_trim = left_trimmed, right_trim = right_trimmed}
			end
		end
	end

	return left_lines, right_lines, trim_info
end

--- Split highlights between left and right columns
--- @param highlights table Map of line number to highlights array
--- @param split_columns table Map of line number to split column
--- @param trim_info table Map of line number to {left_trim, right_trim}
--- @param header_lines table|nil Set of header line numbers to skip splitting
--- @return table left_highlights Highlights for left pane
--- @return table right_highlights Highlights for right pane
function M.split_highlights(highlights, split_columns, trim_info, header_lines)
	local left_highlights = {}
	local right_highlights = {}
	header_lines = header_lines or {}

	for i, line_highlights in pairs(highlights) do
		if header_lines[i] then
			-- Headers: highlights go to left only (or both if needed)
			left_highlights[i] = line_highlights
		else
			local split_col = split_columns[i] or 0
			local info = trim_info[i] or {left_trim = 0, right_trim = 0}

			if split_col > 0 then
				local left_hl = {}
				local right_hl = {}

				for _, hl in ipairs(line_highlights) do
					local hl_start = hl.col
					local hl_end = hl.col + hl.length

					if hl_end <= split_col then
						-- Highlight is entirely in left column
						local left_content_len = split_col - info.left_trim
						local kept_end = math.min(hl_end, left_content_len)

						if hl_start < kept_end then
							table.insert(left_hl, {
								col = hl.col,
								length = kept_end - hl.col,
								hl_group = hl.hl_group,
							})
						end
					elseif hl_start >= split_col then
						-- Highlight is entirely in right column
						local untrimmed_start = hl.col - split_col
						local untrimmed_end = hl_end - split_col

						local kept_start = math.max(untrimmed_start, info.right_trim)
						local kept_end = math.max(untrimmed_end, info.right_trim)

						if kept_start < kept_end then
							local adjusted_col = kept_start - info.right_trim
							local adjusted_len = kept_end - kept_start
							table.insert(right_hl, {
								col = adjusted_col,
								length = adjusted_len,
								hl_group = hl.hl_group,
							})
						end
					else
						-- Highlight spans the split column - split it
						local left_content_len = split_col - info.left_trim
						local left_hl_end = math.min(split_col, left_content_len)

						-- Left portion
						if hl.col < left_hl_end then
							table.insert(left_hl, {
								col = hl.col,
								length = left_hl_end - hl.col,
								hl_group = hl.hl_group,
							})
						end

						-- Right portion
						local right_len = hl_end - split_col
						table.insert(right_hl, {
							col = 0,
							length = right_len,
							hl_group = hl.hl_group,
						})
					end
				end

				if #left_hl > 0 then
					left_highlights[i] = left_hl
				end
				if #right_hl > 0 then
					right_highlights[i] = right_hl
				end
			else
				-- No split - all highlights go to left
				left_highlights[i] = line_highlights
			end
		end
	end

	return left_highlights, right_highlights
end

return M
