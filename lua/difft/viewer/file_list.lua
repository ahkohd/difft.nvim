--- File list rendering and navigation
local M = {}

--- Status code to display character mapping
local status_chars = {
	M = "Modified",
	A = "Added",
	D = "Deleted",
	R = "Renamed",
	C = "Copied",
	U = "Updated",
	["?"] = "Untracked",
	["!"] = "Ignored",
}

--- Render file list to buffer
--- @param buf number Buffer handle
--- @param files table Array of {path, status, staged}
--- @param opts? table Options: { current_index = number, ns = number }
function M.render(buf, files, opts)
	opts = opts or {}
	local current_index = opts.current_index or 1
	local ns = opts.ns or vim.api.nvim_create_namespace("difft_file_list")

	-- Clear existing highlights
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

	-- Build lines
	local lines = {}
	for i, file in ipairs(files) do
		local status_char = file.status
		local status_text = status_chars[status_char] or status_char
		local staged_marker = file.staged and "[S] " or "[U] "
		local line = string.format("%s[%s] %s", staged_marker, status_char, file.path)
		table.insert(lines, line)
	end

	-- Set lines (make buffer modifiable temporarily)
	vim.api.nvim_buf_set_option(buf, "modifiable", true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(buf, "modifiable", false)

	-- Highlight current selection
	if current_index >= 1 and current_index <= #files then
		vim.api.nvim_buf_add_highlight(buf, ns, "CursorLine", current_index - 1, 0, -1)
	end

	-- Add syntax highlighting for status
	for i, file in ipairs(files) do
		local line_num = i - 1 -- 0-indexed
		local status = file.status

		-- Highlight status character based on type
		local hl_group
		if status == "M" then
			hl_group = "DiffChange"
		elseif status == "A" or status == "?" then
			hl_group = "DiffAdd"
		elseif status == "D" then
			hl_group = "DiffDelete"
		else
			hl_group = "Comment"
		end

		-- Highlight the "[X]" part
		local status_start = file.staged and 4 or 4 -- After "[S] " or "[U] "
		local status_end = status_start + 3 -- "[X]"
		vim.api.nvim_buf_add_highlight(buf, ns, hl_group, line_num, status_start, status_end)

		-- Dim the staged/unstaged marker
		vim.api.nvim_buf_add_highlight(buf, ns, "Comment", line_num, 0, 4)
	end
end

--- Setup navigation keymaps for file list
--- @param buf number Buffer handle
--- @param callbacks table Callbacks: { on_select, on_close, on_focus_diff, on_refresh }
function M.setup_keymaps(buf, callbacks)
	local opts = { buffer = buf, noremap = true, silent = true }
	local on_select = callbacks.on_select
	local on_close = callbacks.on_close
	local on_focus_diff = callbacks.on_focus_diff
	local on_refresh = callbacks.on_refresh

	-- Navigation: j/k or up/down
	vim.keymap.set("n", "j", function()
		local line = vim.fn.line(".")
		local max_line = vim.fn.line("$")
		if line < max_line then
			vim.cmd("normal! j")
			on_select(line + 1)
		end
	end, opts)

	vim.keymap.set("n", "k", function()
		local line = vim.fn.line(".")
		if line > 1 then
			vim.cmd("normal! k")
			on_select(line - 1)
		end
	end, opts)

	vim.keymap.set("n", "<Down>", function()
		local line = vim.fn.line(".")
		local max_line = vim.fn.line("$")
		if line < max_line then
			vim.cmd("normal! j")
			on_select(line + 1)
		end
	end, opts)

	vim.keymap.set("n", "<Up>", function()
		local line = vim.fn.line(".")
		if line > 1 then
			vim.cmd("normal! k")
			on_select(line - 1)
		end
	end, opts)

	-- Select file and focus diff: Enter
	vim.keymap.set("n", "<CR>", function()
		local line = vim.fn.line(".")
		on_select(line)
		on_focus_diff()
	end, opts)

	-- Navigate to diff pane: l or <C-l>
	vim.keymap.set("n", "l", on_focus_diff, opts)
	vim.keymap.set("n", "<C-l>", on_focus_diff, opts)

	-- Close viewer: q or Esc
	vim.keymap.set("n", "q", on_close, opts)
	vim.keymap.set("n", "<Esc>", on_close, opts)

	-- Refresh current file: r
	if on_refresh then
		vim.keymap.set("n", "r", on_refresh, opts)
	end
end

return M
