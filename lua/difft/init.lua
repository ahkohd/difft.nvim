-- luacheck: globals vim

--- A Neovim plugin for viewing difftastic output with ANSI color parsing
--- @class Difft
local M = {}

local parser = require("difft.lib.parser")
local renderer = require("difft.lib.renderer")
local navigation = require("difft.lib.navigation")
local buffer = require("difft.lib.buffer")
local file_jump = require("difft.lib.file_jump")
local highlight = require("difft.lib.highlight")

highlight.setup_difft_highlights()

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
	command = "GIT_EXTERNAL_DIFF='difft --color=always' git diff",
	auto_jump = true,
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
		highlights = highlight.build_default_diff_highlights(),
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

--- Get the active config (normalized if setup() was called, otherwise default)
--- @return table Active configuration
local function get_active_config()
	return M._normalized_config or config
end

--- Track which highlight keys were provided by user (not defaults)
local user_provided_highlights = {}

--- Setup custom header highlight group if configured
local function setup_header_highlight()
	local hl_config = config.header.highlight
	if not hl_config or not (hl_config.link or hl_config.fg or hl_config.bg) then
		return
	end

	if hl_config.link then
		vim.api.nvim_set_hl(0, "DifftFileHeader", { link = hl_config.link })
		local linked_hl = vim.api.nvim_get_hl(0, { name = hl_config.link, link = false })
		if linked_hl.bg then
			vim.api.nvim_set_hl(0, "DifftFileHeaderBg", { bg = linked_hl.bg })
		end
		return
	end

	local hl_opts = {}
	local bg_only = {}

	if hl_config.fg then
		if type(hl_config.fg) == "table" and hl_config.fg.link then
			local linked_hl = vim.api.nvim_get_hl(0, { name = hl_config.fg.link })
			if linked_hl.fg then
				hl_opts.fg = linked_hl.fg
			end
		else
			hl_opts.fg = hl_config.fg
		end
	end

	if hl_config.bg then
		if type(hl_config.bg) == "table" and hl_config.bg.link then
			local linked_hl = vim.api.nvim_get_hl(0, { name = hl_config.bg.link })
			if linked_hl.bg then
				hl_opts.bg = linked_hl.bg
				bg_only.bg = linked_hl.bg
			end
		else
			hl_opts.bg = hl_config.bg
			bg_only.bg = hl_config.bg
		end
	end

	if next(hl_opts) then
		vim.api.nvim_set_hl(0, "DifftFileHeader", hl_opts)
	end

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
--- Dynamically creates highlight groups that inherit from base with bold/italic/underline
--- @param base_hl string Base highlight group name
--- @param bold boolean Apply bold formatting
--- @param italic boolean Apply italic formatting
--- @param dim boolean Apply dim formatting (handled via base_hl)
--- @param underline boolean Apply underline formatting
--- @return string Highlight group name

--- Set cursor position while preserving goal column (Vim-style behavior)
--- @param line number Target line number
local function set_cursor_with_goal_column(line)
	-- Always update goal_column from current cursor position
	-- This picks up manual cursor movements (h, l, $, ^, etc.) between navigations
	local current_pos = vim.api.nvim_win_get_cursor(state.win)
	state.goal_column = current_pos[2]

	local line_text = vim.api.nvim_buf_get_lines(state.buf, line - 1, line, false)[1] or ""
	local line_length = #line_text

	local col = math.min(state.goal_column, line_length)

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
			if state.win and vim.api.nvim_win_is_valid(state.win) then
				state.last_cursor = vim.api.nvim_win_get_cursor(state.win)
				vim.api.nvim_win_hide(state.win)
				state.win = nil -- Clear win reference so it's detected as hidden
			end
		end
	end

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

	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	return renderer.render_custom_headers(buf, lines, state.changes, config, state.ns)
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

	vim.api.nvim_buf_clear_namespace(buf, state.ns, 0, -1)

	vim.api.nvim_buf_set_option(buf, "modifiable", true)

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { config.loading_message })

	local columns = "10000" -- Default fallback
	if win and vim.api.nvim_win_is_valid(win) then
		columns = tostring(vim.api.nvim_win_get_width(win))
	end

	vim.fn.jobstart(cmd or config.command, {
		env = {
			COLUMNS = columns,
		},
		stdout_buffered = true,
		on_stdout = function(_, data)
			if not data then
				return
			end

			if data[#data] == "" then
				table.remove(data)
			end

			vim.schedule(function()
				if not vim.api.nvim_buf_is_valid(buf) then
					return
				end

				-- Ensure buffer is modifiable (protects against race conditions on rapid resizes)
				vim.api.nvim_buf_set_option(buf, "modifiable", true)

				if #data == 0 or (#data == 1 and data[1] == "") then
					vim.api.nvim_buf_set_lines(buf, 0, -1, false, { config.no_diff_message })
					vim.api.nvim_buf_set_option(buf, "modifiable", false)
					return
				end

					-- Use lib/buffer to setup the buffer with ANSI parsing, rendering, and navigation
					local result = buffer.setup_from_ansi_lines(buf, data, get_active_config(), state.ns, {
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

					state.changes = result.headers

					vim.api.nvim_buf_set_option(buf, "modifiable", false)

					-- Restore last cursor position if available (for all modes), otherwise use auto_jump logic
					if state.last_cursor then
						local total_lines = vim.api.nvim_buf_line_count(buf)
						if state.last_cursor[1] <= total_lines then
							pcall(vim.api.nvim_win_set_cursor, win, state.last_cursor)
						else
							vim.api.nvim_win_set_cursor(win, { total_lines, 0 })
						end
						vim.cmd("normal! zz")
					elseif config.auto_jump and #state.changes > 0 then
						vim.api.nvim_win_set_cursor(win, { state.changes[1].line, 0 })
						vim.cmd("normal! zz")
					else
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

	local win_config
	if config.layout == "float" then
		win_config = get_float_layout()
	elseif config.layout == "ivy_taller" then
		win_config = get_ivy_taller_layout()
	else
		return
	end

	vim.api.nvim_win_set_config(state.win, win_config)
end

--- Setup buffer-local keymaps for non-navigation actions (close, refresh, jump)
--- Navigation keymaps (next/prev/first/last) are handled by lib/navigation.setup()
--- @param buf number Buffer handle
--- @param is_floating boolean Whether this is a floating window
local function setup_keymaps(buf, is_floating)
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
		local win_config
		if layout == "float" then
			win_config = get_float_layout()
		else -- ivy_taller
			win_config = get_ivy_taller_layout()
		end

		local win = vim.api.nvim_open_win(state.buf, true, win_config)
		state.win = win

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

	-- Setup default Difft* highlight groups (with fallback links)
	highlight.setup_difft_highlights()

	config = vim.tbl_deep_extend("force", config, opts)

	-- Track which highlights were provided by user
	if opts.diff and opts.diff.highlights then
		for key, value in pairs(opts.diff.highlights) do
			-- Replace (not merge) user-provided highlights
			config.diff.highlights[key] = value
			user_provided_highlights[key] = true
		end
	end

	-- Normalize diff highlights and initialize ANSI color mapping
	local normalized_highlights = highlight.normalize_diff_highlights(config.diff.highlights)
	local normalized_config = vim.tbl_deep_extend("force", config, {
		diff = { highlights = normalized_highlights }
	})
	parser.init_ansi_mapping(normalized_config)

	-- Store normalized config for later use
	M._normalized_config = normalized_config

	-- Setup custom header highlight if configured
	setup_header_highlight()

	-- Clear highlight cache when colorscheme changes
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("difft_colorscheme", { clear = true }),
		callback = function()
			parser.clear_hl_cache()

			-- Re-setup Difft* highlight groups for new colorscheme (force recreation)
			highlight.setup_difft_highlights(true)

			-- Rebuild defaults for highlights not provided by user
			local rebuilt_highlights = highlight.build_default_diff_highlights()
			for key, value in pairs(user_provided_highlights) do
				if value then
					-- Keep user-provided highlight
					rebuilt_highlights[key] = config.diff.highlights[key]
				end
			end
			config.diff.highlights = rebuilt_highlights

			-- Recreate custom highlights on colorscheme change
			local norm_highlights = highlight.normalize_diff_highlights(config.diff.highlights)
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

return M

-- vim:noet:ts=4:sts=4:sw=4:
