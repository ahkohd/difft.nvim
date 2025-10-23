-- luacheck: globals vim

--- Renderer module for difft.nvim
--- Handles applying highlights and custom header rendering to buffers

local M = {}

--- Apply highlights to a buffer line using extmarks
--- Sets both gutter line number color and text highlights
--- @param buf number Buffer handle
--- @param line_num number Line number (0-indexed)
--- @param highlights table List of highlight regions with col, length, and hl_group
--- @param ns number Namespace for extmarks
--- @param opts? table Optional settings: { line_number_coloring = boolean, empty_line_support = boolean }
function M.apply_line_highlights(buf, line_num, highlights, ns, opts)
	opts = opts or {}
	local enable_line_numbers = opts.line_number_coloring ~= false -- default true
	local empty_line_support = opts.empty_line_support ~= false -- default true

	local line_content = vim.api.nvim_buf_get_lines(buf, line_num, line_num + 1, false)[1] or ""
	local is_empty_line = #line_content == 0

	if enable_line_numbers then
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

		if line_number_hl then
			pcall(vim.api.nvim_buf_set_extmark, buf, ns, line_num, 0, {
				end_col = #line_content,
				number_hl_group = line_number_hl,
				priority = 50,
			})
		end
	end

	for _, hl in ipairs(highlights) do
		if hl.hl_group then
			local extmark_opts = {
				hl_group = hl.hl_group,
				priority = 110,
			}

			if empty_line_support and is_empty_line and hl.length > 0 then
				extmark_opts.end_row = line_num + 1
				extmark_opts.end_col = 0
			else
				extmark_opts.end_col = hl.col + hl.length
			end

			pcall(vim.api.nvim_buf_set_extmark, buf, ns, line_num, hl.col, extmark_opts)
		end
	end
end

--- Apply custom header content if configured
--- Replaces header lines with custom content from user function
--- @param buf number Buffer handle
--- @param lines table Clean text lines
--- @param headers table Array of header info from parser.parse_headers()
--- @param config table User configuration with header.content function
--- @param ns number Namespace for extmarks
--- @return table Set of line numbers that have custom highlights (for avoiding double-highlighting)
function M.render_custom_headers(buf, lines, headers, config, ns)
	if not config.header or not config.header.content or type(config.header.content) ~= "function" then
		return {}
	end

	local has_custom_highlights = {}

	for _, header_info in ipairs(headers) do
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
			vim.api.nvim_buf_set_lines(buf, line_num - 1, line_num, false, { result })

		elseif type(result) == "table" then
			local text_parts = {}
			local highlights = {}
			local col = 0

			for _, item in ipairs(result) do
				if type(item) ~= "table" or #item < 1 then
					goto continue_item
				end

				local text = tostring(item[1] or "")
				local hl_group = item[2]

				table.insert(text_parts, text)

				if #text > 0 then
					local final_hl = hl_group or "DifftFileHeader"
					table.insert(highlights, {
						col = col,
						end_col = col + #text,
						hl_group = final_hl,
					})
				end

				col = col + #text
				::continue_item::
			end

			local full_text = table.concat(text_parts)
			vim.api.nvim_buf_set_lines(buf, line_num - 1, line_num, false, { full_text })

			for _, hl in ipairs(highlights) do
				pcall(vim.api.nvim_buf_set_extmark, buf, ns, line_num - 1, hl.col, {
					end_col = hl.end_col,
					hl_group = hl.hl_group,
					priority = 150, -- Higher priority for custom headers
				})
			end

			has_custom_highlights[line_num] = true
		end

		::continue::
	end

	return has_custom_highlights
end

--- Apply header highlight to file header lines
--- @param buf number Buffer handle
--- @param line_num number Line number (1-indexed) to apply highlight
--- @param line_text string Clean text of the line
--- @param has_custom_highlights boolean Whether this line already has custom highlights from content function
--- @param config table User configuration with header.highlight settings
--- @param ns number Namespace for extmarks
function M.apply_header_highlight(buf, line_num, line_text, has_custom_highlights, config, ns)
	local hl_config = config.header and config.header.highlight

	if has_custom_highlights then
		return
	end

	local extmark_opts = {
		priority = 150, -- Higher than ANSI highlights (110)
		hl_group = "DifftFileHeader",
	}

	if hl_config and hl_config.full_width then
		extmark_opts.end_col = 0
		extmark_opts.end_row = line_num -- Next line (1-indexed becomes 0-indexed)
		extmark_opts.hl_eol = true
	else
		extmark_opts.end_col = #line_text
	end

	pcall(vim.api.nvim_buf_set_extmark, buf, ns, line_num - 1, 0, extmark_opts)
end

return M
