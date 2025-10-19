-- luacheck: globals vim

--- Buffer module for difft.nvim
--- High-level API for setting up difft buffers with parsing, rendering, and navigation

local parser = require("difft.lib.parser")
local renderer = require("difft.lib.renderer")
local navigation = require("difft.lib.navigation")

local M = {}

--- Setup a buffer with difftastic content, highlights, and navigation
--- This is the main entry point for preparing any buffer to display difft output
--- @param buf number Buffer handle
--- @param opts table Options:
---   - lines: table - Clean text lines (required)
---   - highlights: table - Map of line_num -> highlight array (required)
---   - config: table - User configuration (required)
---   - namespace: number - Namespace for extmarks (required)
---   - custom_headers: boolean - Whether to apply custom header rendering (default: true)
---   - navigation: table|boolean - Navigation options or false to disable:
---       - enabled: boolean - Enable navigation (default: true)
---       - keymaps: table - Keymap configuration
---       - auto_jump: boolean - Auto jump to first change
---   - renderer_opts: table - Options for renderer.apply_line_highlights():
---       - line_number_coloring: boolean - Enable line number coloring (default: true)
---       - empty_line_support: boolean - Enable empty line highlight support (default: true)
function M.setup_difft_buffer(buf, opts)
	if not vim.api.nvim_buf_is_valid(buf) then
		vim.notify("[difft] Invalid buffer handle", vim.log.levels.ERROR)
		return
	end

	-- Extract options
	local lines = opts.lines or {}
	local all_highlights = opts.highlights or {}
	local config = opts.config
	local ns = opts.namespace
	local enable_custom_headers = opts.custom_headers ~= false -- default true
	local nav_opts = opts.navigation
	local renderer_opts = opts.renderer_opts or {}

	if not config then
		vim.notify("[difft] Config is required", vim.log.levels.ERROR)
		return
	end

	if not ns then
		vim.notify("[difft] Namespace is required", vim.log.levels.ERROR)
		return
	end

	-- Parse headers from lines
	local headers, header_set = parser.parse_headers(lines)

	-- Set buffer lines
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	-- Apply line highlights
	for line_num, highlights in pairs(all_highlights) do
		renderer.apply_line_highlights(buf, line_num - 1, highlights, ns, renderer_opts)
	end

	-- Apply custom header rendering if enabled
	local has_custom_highlights = {}
	if enable_custom_headers then
		has_custom_highlights = renderer.render_custom_headers(buf, lines, headers, config, ns)
	end

	-- Apply header highlighting (background/border)
	if config.header and config.header.highlight then
		for _, header_info in ipairs(headers) do
			local line_num = header_info.line
			local line_text = lines[line_num]
			local has_custom_hl = has_custom_highlights[line_num]
			renderer.apply_header_highlight(buf, line_num, line_text, has_custom_hl, config, ns)
		end
	end

	-- Setup navigation if enabled
	if nav_opts ~= false then
		local nav_config = type(nav_opts) == "table" and nav_opts or {}
		local enable_nav = nav_config.enabled ~= false -- default true

		if enable_nav then
			navigation.setup(buf, {
				headers = headers,
				keymaps = nav_config.keymaps or config.keymaps,
				auto_jump = nav_config.auto_jump,
			})
		end
	end

	return {
		headers = headers,
		header_set = header_set,
	}
end

--- Parse ANSI lines and prepare data for setup_difft_buffer
--- This is a helper that combines ANSI parsing with buffer setup
--- @param buf number Buffer handle
--- @param raw_lines table Lines with ANSI escape codes
--- @param config table User configuration
--- @param ns number Namespace for extmarks
--- @param opts? table Additional options (same as setup_difft_buffer)
function M.setup_from_ansi_lines(buf, raw_lines, config, ns, opts)
	opts = opts or {}

	-- Parse ANSI codes from all lines
	local clean_lines = {}
	local all_highlights = {}

	for i, line in ipairs(raw_lines) do
		if line:find("\27%[") then
			local clean_text, highlights = parser.parse_ansi_line(line)
			clean_lines[i] = clean_text
			all_highlights[i] = highlights
		else
			clean_lines[i] = line
		end
	end

	-- Merge parsed data into opts
	opts.lines = clean_lines
	opts.highlights = all_highlights
	opts.config = config
	opts.namespace = ns

	return M.setup_difft_buffer(buf, opts)
end

return M
