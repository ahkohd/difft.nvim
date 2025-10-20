--- Main diff viewer orchestrator
local M = {}

local git = require("difft.viewer.git")
local layout = require("difft.viewer.layout")
local file_list = require("difft.viewer.file_list")
local diff_pane = require("difft.viewer.diff_pane")

--- @class ViewerState
--- @field layout ViewerLayout|nil
--- @field files table Array of file entries
--- @field current_file_index number Currently selected file index
--- @field config table Difft configuration
--- @field ns number Highlight namespace
--- @field diff_cache table Cache of diff outputs keyed by "path:staged"

local state = {
	layout = nil,
	files = {},
	current_file_index = 1,
	config = nil,
	ns = vim.api.nvim_create_namespace("difft_viewer"),
	diff_cache = {},
}

--- Open the diff viewer
--- @param config table Difft configuration
--- @param opts? table Options: { staged = bool, unstaged = bool }
function M.open(config, opts)
	opts = opts or {}
	state.config = config

	-- Check if in git repo
	if not git.is_git_repo() then
		vim.notify("Not in a git repository", vim.log.levels.WARN)
		return
	end

	-- Get changed files
	local files, err = git.get_changed_files(opts)
	if err then
		vim.notify("Failed to get changed files: " .. err, vim.log.levels.ERROR)
		return
	end

	if #files == 0 then
		vim.notify("No changes found", vim.log.levels.INFO)
		return
	end

	state.files = files
	state.current_file_index = 1
	state.diff_cache = {} -- Clear cache on open

	-- Create layout
	state.layout = layout.create_layout()

	-- Render file list
	file_list.render(state.layout.file_list_buf, state.files, {
		current_index = state.current_file_index
	})

	-- Setup file list navigation
	file_list.setup_keymaps(state.layout.file_list_buf, {
		on_select = function(index)
			M.select_file(index)
		end,
		on_close = function()
			M.close()
		end,
		on_focus_diff = function()
			M.focus_diff_pane()
		end,
		on_refresh = function()
			M.refresh_current_file()
		end,
	})

	-- Setup diff pane keymaps (once at initialization)
	diff_pane.setup_keymaps(state.layout.diff_pane_buf, {
		on_close = function()
			M.close()
		end,
		on_focus_list = function()
			M.focus_file_list()
		end,
		on_refresh = function()
			M.refresh_current_file()
		end,
	})

	-- Show first file
	M.select_file(1)
end

--- Select and display a file
--- @param index number File index to select
function M.select_file(index)
	if not state.layout or not layout.is_valid(state.layout) then
		return
	end

	state.current_file_index = index
	local file = state.files[index]
	if not file then
		return
	end

	-- Update file list highlight
	file_list.render(state.layout.file_list_buf, state.files, {
		current_index = index,
		ns = state.ns,
	})

	-- Check cache first
	local cache_key = file.path .. ":" .. tostring(file.staged)
	local cached_diff = state.diff_cache[cache_key]

	if cached_diff then
		-- Use cached diff immediately
		diff_pane.render(state.layout.diff_pane_buf, cached_diff, state.config, state.ns)
		return
	end

	-- Track if loading is still in progress
	local loading_timer = nil
	local is_loading = true

	-- Show loading indicator only after 200ms delay
	loading_timer = vim.defer_fn(function()
		if not is_loading then
			return
		end
		if not state.layout or not layout.is_valid(state.layout) then
			return
		end
		local loading_lines = {
			"",
			"  Loading diff...",
			"",
			"  File: " .. file.path,
			"  " .. (file.staged and "[Staged]" or "[Unstaged]"),
		}
		vim.api.nvim_buf_set_option(state.layout.diff_pane_buf, "modifiable", true)
		vim.api.nvim_buf_set_lines(state.layout.diff_pane_buf, 0, -1, false, loading_lines)
		vim.api.nvim_buf_set_option(state.layout.diff_pane_buf, "modifiable", false)
	end, 200)

	-- Get and render diff asynchronously
	git.get_file_diff(file.path, { staged = file.staged }, function(diff_output, err)
		is_loading = false

		if not state.layout or not layout.is_valid(state.layout) then
			return
		end

		if err then
			vim.notify("Failed to get diff: " .. err, vim.log.levels.ERROR)
			-- Show error in buffer
			local error_lines = { "", "  Error loading diff:", "  " .. err }
			vim.api.nvim_buf_set_option(state.layout.diff_pane_buf, "modifiable", true)
			vim.api.nvim_buf_set_lines(state.layout.diff_pane_buf, 0, -1, false, error_lines)
			vim.api.nvim_buf_set_option(state.layout.diff_pane_buf, "modifiable", false)
			return
		end

		-- Cache the result
		state.diff_cache[cache_key] = diff_output

		-- Render diff (difftastic handles side-by-side formatting internally)
		diff_pane.render(state.layout.diff_pane_buf, diff_output, state.config, state.ns)
	end)
end

--- Focus the diff pane window
function M.focus_diff_pane()
	if not state.layout or not layout.is_valid(state.layout) then
		return
	end
	vim.api.nvim_set_current_win(state.layout.diff_pane_win)
end

--- Focus the file list window
function M.focus_file_list()
	if not state.layout or not layout.is_valid(state.layout) then
		return
	end
	vim.api.nvim_set_current_win(state.layout.file_list_win)
end

--- Refresh the current file (clear cache and reload)
function M.refresh_current_file()
	if not state.layout or not layout.is_valid(state.layout) then
		return
	end

	local file = state.files[state.current_file_index]
	if not file then
		return
	end

	-- Clear cache for this file
	local cache_key = file.path .. ":" .. tostring(file.staged)
	state.diff_cache[cache_key] = nil

	-- Reload the file
	M.select_file(state.current_file_index)
end

--- Close the diff viewer
function M.close()
	if state.layout then
		layout.close_layout(state.layout)
		state.layout = nil
	end
end

--- Check if viewer is open
--- @return boolean
function M.is_open()
	return state.layout ~= nil and layout.is_valid(state.layout)
end

return M
