-- luacheck: globals vim

--- Navigation module for difft.nvim
--- Handles cursor jumping between file changes in difft buffers

local M = {}

-- Buffer-local navigation state storage
-- { [bufnr] = { headers = {...}, current = 0, goal_column = 0 } }
local buffer_state = {}

--- Set cursor position while preserving goal column
--- Also syncs to paired buffer if configured
--- @param buf number Buffer handle
--- @param win number Window handle
--- @param line number Line number to jump to (1-indexed)
local function set_cursor_with_goal_column(buf, win, line)
	local state = buffer_state[buf]
	if not state then
		return
	end

	-- Always update goal_column from current cursor position
	-- This picks up manual cursor movements (h, l, $, ^, etc.) between navigations
	local current_pos = vim.api.nvim_win_get_cursor(win)
	state.goal_column = current_pos[2]

	-- Get the length of the target line (0-indexed column count)
	local line_text = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1] or ""
	local line_length = #line_text

	-- Clamp goal column to line length
	local col = math.min(state.goal_column, line_length)

	-- Set cursor position
	vim.api.nvim_win_set_cursor(win, { line, col })

	-- Sync to paired buffer if configured
	if state.sync_buf and vim.api.nvim_buf_is_valid(state.sync_buf) then
		local sync_wins = vim.fn.win_findbuf(state.sync_buf)
		if #sync_wins > 0 then
			-- Get sync buffer's line text and clamp column
			local sync_line_text = vim.api.nvim_buf_get_lines(state.sync_buf, line - 1, line, false)[1] or ""
			local sync_col = math.min(col, #sync_line_text)
			pcall(vim.api.nvim_win_set_cursor, sync_wins[1], { line, sync_col })
		end
	end
end

--- Navigate to next file change
--- @param buf number Buffer handle
local function next_change(buf)
	local state = buffer_state[buf]
	if not state or #state.headers == 0 then
		return
	end

	-- Get current window
	local wins = vim.fn.win_findbuf(buf)
	if #wins == 0 then
		return
	end
	local win = wins[1]

	state.current = state.current + 1
	if state.current > #state.headers then
		state.current = 1
	end

	local line = state.headers[state.current].line
	set_cursor_with_goal_column(buf, win, line)
	vim.cmd("normal! zz")
end

--- Navigate to previous file change
--- @param buf number Buffer handle
local function prev_change(buf)
	local state = buffer_state[buf]
	if not state or #state.headers == 0 then
		return
	end

	-- Get current window
	local wins = vim.fn.win_findbuf(buf)
	if #wins == 0 then
		return
	end
	local win = wins[1]

	state.current = state.current - 1
	if state.current < 1 then
		state.current = #state.headers
	end

	local line = state.headers[state.current].line
	set_cursor_with_goal_column(buf, win, line)
	vim.cmd("normal! zz")
end

--- Navigate to first file change
--- @param buf number Buffer handle
local function first_change(buf)
	local state = buffer_state[buf]
	if not state or #state.headers == 0 then
		return
	end

	-- Get current window
	local wins = vim.fn.win_findbuf(buf)
	if #wins == 0 then
		return
	end
	local win = wins[1]

	state.current = 1
	local line = state.headers[state.current].line
	set_cursor_with_goal_column(buf, win, line)
	vim.cmd("normal! zz")
end

--- Navigate to last file change
--- @param buf number Buffer handle
local function last_change(buf)
	local state = buffer_state[buf]
	if not state or #state.headers == 0 then
		return
	end

	-- Get current window
	local wins = vim.fn.win_findbuf(buf)
	if #wins == 0 then
		return
	end
	local win = wins[1]

	state.current = #state.headers
	local line = state.headers[state.current].line
	set_cursor_with_goal_column(buf, win, line)
	vim.cmd("normal! zz")
end

--- Setup navigation keymaps and state for a difft buffer
--- @param buf number Buffer handle
--- @param opts table Options: { headers = array, keymaps = table, auto_jump = boolean, sync_buf = number|nil }
function M.setup(buf, opts)
	opts = opts or {}
	local headers = opts.headers or {}
	local keymaps = opts.keymaps or {
		next = "<Down>",
		prev = "<Up>",
		first = "gg",
		last = "G",
	}
	local auto_jump = opts.auto_jump
	local sync_buf = opts.sync_buf  -- Optional buffer to sync navigation with

	-- Initialize buffer state
	buffer_state[buf] = {
		headers = headers,
		current = 0,
		goal_column = 0,
		sync_buf = sync_buf,  -- Store sync buffer for cursor synchronization
	}

	-- Auto-jump to first change if enabled and there are changes
	if auto_jump and #headers > 0 then
		buffer_state[buf].current = 1
		vim.schedule(function()
			if vim.api.nvim_buf_is_valid(buf) then
				local wins = vim.fn.win_findbuf(buf)
				if #wins > 0 then
					local line = headers[1].line
					vim.api.nvim_win_set_cursor(wins[1], { line, 0 })
					vim.cmd("normal! zz")
				end
			end
		end)
	end

	-- Setup keymaps
	vim.keymap.set("n", keymaps.next, function()
		next_change(buf)
	end, {
		buffer = buf,
		noremap = true,
		silent = true,
		desc = "Next change",
	})

	vim.keymap.set("n", keymaps.prev, function()
		prev_change(buf)
	end, {
		buffer = buf,
		noremap = true,
		silent = true,
		desc = "Previous change",
	})

	vim.keymap.set("n", keymaps.first, function()
		first_change(buf)
	end, {
		buffer = buf,
		noremap = true,
		silent = true,
		desc = "First change",
	})

	vim.keymap.set("n", keymaps.last, function()
		last_change(buf)
	end, {
		buffer = buf,
		noremap = true,
		silent = true,
		desc = "Last change",
	})

	-- Cleanup state when buffer is deleted
	vim.api.nvim_create_autocmd("BufDelete", {
		buffer = buf,
		callback = function()
			buffer_state[buf] = nil
		end,
	})
end

--- Update the current change index based on cursor position
--- Useful after manual cursor movements to sync navigation state
--- @param buf number Buffer handle
function M.update_current_from_cursor(buf)
	local state = buffer_state[buf]
	if not state or #state.headers == 0 then
		return
	end

	local wins = vim.fn.win_findbuf(buf)
	if #wins == 0 then
		return
	end

	local cursor = vim.api.nvim_win_get_cursor(wins[1])
	local cursor_line = cursor[1]

	-- Find the closest header at or before the cursor
	local closest_idx = 0
	for i, header in ipairs(state.headers) do
		if header.line <= cursor_line then
			closest_idx = i
		else
			break
		end
	end

	state.current = closest_idx
end

--- Get the current navigation state for a buffer
--- @param buf number Buffer handle
--- @return table|nil State table or nil if not setup
function M.get_state(buf)
	return buffer_state[buf]
end

return M
