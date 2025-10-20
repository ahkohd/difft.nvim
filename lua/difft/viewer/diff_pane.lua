--- Diff pane rendering with difftastic output
local M = {}

local parser = require("difft.lib.parser")
local buffer = require("difft.lib.buffer")
local renderer = require("difft.lib.renderer")

--- Render diff content to buffer (single-column mode)
--- @param buf number Buffer handle
--- @param diff_output string Raw difftastic output with ANSI codes
--- @param config table Difft configuration
--- @param ns number Namespace for highlights
function M.render(buf, diff_output, config, ns)
	-- Parse ANSI and render using existing lib functions
	local lines = vim.split(diff_output, "\n", { plain = true })

	-- Make buffer modifiable temporarily
	vim.api.nvim_buf_set_option(buf, "modifiable", true)

	buffer.setup_from_ansi_lines(buf, lines, config, ns, {
		navigation = { enabled = true, auto_jump = false },
	})

	-- Set back to non-modifiable
	vim.api.nvim_buf_set_option(buf, "modifiable", false)
end


--- Setup additional keymaps for diff pane
--- @param buf number Buffer handle
--- @param callbacks table Callbacks: { on_close, on_focus_list, on_refresh }
function M.setup_keymaps(buf, callbacks)
	local opts = { buffer = buf, noremap = true, silent = true }
	local on_close = callbacks.on_close
	local on_focus_list = callbacks.on_focus_list
	local on_refresh = callbacks.on_refresh

	-- Navigate to file list: h or <C-h>
	vim.keymap.set("n", "h", on_focus_list, opts)
	vim.keymap.set("n", "<C-h>", on_focus_list, opts)

	-- Close viewer: q or Esc
	vim.keymap.set("n", "q", on_close, opts)
	vim.keymap.set("n", "<Esc>", on_close, opts)

	-- Refresh diff: r
	if on_refresh then
		vim.keymap.set("n", "r", on_refresh, opts)
	end
end

return M
