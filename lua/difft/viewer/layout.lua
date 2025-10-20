--- Window and buffer layout management for diff viewer
--- Uses a dedicated tab like diffview.nvim for clean isolation
local M = {}

--- @class ViewerLayout
--- @field tabpage number Tab handle for the diff viewer
--- @field file_list_win number Window handle for file list
--- @field file_list_buf number Buffer handle for file list
--- @field file_list_width number Width of file list window
--- @field diff_pane_win number Window handle for diff pane
--- @field diff_pane_buf number Buffer handle for diff pane
--- @field original_tabpage number Original tab to return to on close

--- Create side-by-side layout in a dedicated tab: file list (left) | diff pane (right)
--- @param opts? table Options: { file_list_width = number }
--- @return ViewerLayout
function M.create_layout(opts)
	opts = opts or {}
	local file_list_width = opts.file_list_width or 40

	-- Save original tabpage
	local original_tabpage = vim.api.nvim_get_current_tabpage()

	-- Create new tab
	vim.cmd("tabnew")
	local tabpage = vim.api.nvim_get_current_tabpage()

	-- Create file list buffer
	local file_list_buf = vim.api.nvim_create_buf(false, true)  -- unlisted, scratch
	vim.api.nvim_buf_set_option(file_list_buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(file_list_buf, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(file_list_buf, "swapfile", false)
	vim.api.nvim_buf_set_name(file_list_buf, "difft://files")

	-- Create diff pane buffer
	local diff_pane_buf = vim.api.nvim_create_buf(false, true)  -- unlisted, scratch
	vim.api.nvim_buf_set_option(diff_pane_buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(diff_pane_buf, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(diff_pane_buf, "swapfile", false)
	vim.api.nvim_buf_set_name(diff_pane_buf, "difft://diff")

	-- Set file list buffer in current window
	vim.api.nvim_win_set_buf(0, file_list_buf)
	local file_list_win = vim.api.nvim_get_current_win()

	-- Set window options for file list
	vim.api.nvim_win_set_option(file_list_win, "number", false)
	vim.api.nvim_win_set_option(file_list_win, "relativenumber", false)
	vim.api.nvim_win_set_option(file_list_win, "signcolumn", "no")
	vim.api.nvim_win_set_option(file_list_win, "foldcolumn", "0")

	-- Split vertically for diff pane (create split to the RIGHT)
	vim.cmd("rightbelow vsplit")
	local diff_pane_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(diff_pane_win, diff_pane_buf)

	-- Set window options for diff pane
	vim.api.nvim_win_set_option(diff_pane_win, "number", false)
	vim.api.nvim_win_set_option(diff_pane_win, "relativenumber", false)

	-- Set file list width
	vim.api.nvim_win_set_width(file_list_win, file_list_width)

	-- Make both buffers readonly
	vim.api.nvim_buf_set_option(file_list_buf, "modifiable", false)
	vim.api.nvim_buf_set_option(diff_pane_buf, "modifiable", false)

	-- Focus on file list initially
	vim.api.nvim_set_current_win(file_list_win)

	return {
		tabpage = tabpage,
		file_list_win = file_list_win,
		file_list_buf = file_list_buf,
		file_list_width = file_list_width,
		diff_pane_win = diff_pane_win,
		diff_pane_buf = diff_pane_buf,
		original_tabpage = original_tabpage,
	}
end

--- Close the viewer layout and return to original tab
--- @param layout ViewerLayout
function M.close_layout(layout)
	if not vim.api.nvim_tabpage_is_valid(layout.tabpage) then
		return
	end

	-- Switch back to original tab before closing
	if vim.api.nvim_tabpage_is_valid(layout.original_tabpage) then
		vim.api.nvim_set_current_tabpage(layout.original_tabpage)
	end

	-- Close the diff viewer tab (this will clean up all windows/buffers)
	vim.cmd("tabclose " .. vim.api.nvim_tabpage_get_number(layout.tabpage))
end

--- Check if layout is valid (tab and windows still exist)
--- @param layout ViewerLayout
--- @return boolean
function M.is_valid(layout)
	return vim.api.nvim_tabpage_is_valid(layout.tabpage)
		and vim.api.nvim_win_is_valid(layout.file_list_win)
		and vim.api.nvim_win_is_valid(layout.diff_pane_win)
		and vim.api.nvim_buf_is_valid(layout.file_list_buf)
		and vim.api.nvim_buf_is_valid(layout.diff_pane_buf)
end

return M
