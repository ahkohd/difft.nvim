-- luacheck: globals vim

--- Highlight management for difft.nvim
--- @class DifftHighlight
local M = {}

--- Check if a highlight group is defined (not empty)
--- @param hl_name string Highlight group name
--- @return boolean True if the group is defined
function M.is_hl_defined(hl_name)
	local hl = vim.api.nvim_get_hl(0, { name = hl_name, link = true })
	return hl and (hl.fg ~= nil or hl.bg ~= nil or hl.link ~= nil)
end

--- Setup default Difft highlight groups if not defined by theme
--- These allow theme authors to customize difft-specific colors
--- @param force boolean If true, recreate even if already defined (for ColorScheme updates)
function M.setup_difft_highlights(force)
	force = force or false

	local ansi_defaults = {
		add = 0x00ff00,      -- green
		delete = 0xff0000,   -- red
		change = 0xffff00,   -- yellow
		info = 0x00ffff,     -- cyan
		hint = 0xff00ff,     -- magenta
		dim = 0x808080,      -- gray
		header = 0xffffff,   -- white
	}

	if force or not M.is_hl_defined("DifftAdd") then
		local color = vim.g.terminal_color_2 or ansi_defaults.add
		vim.api.nvim_set_hl(0, "DifftAdd", { fg = color })
	end

	if force or not M.is_hl_defined("DifftDelete") then
		local color = vim.g.terminal_color_1 or ansi_defaults.delete
		vim.api.nvim_set_hl(0, "DifftDelete", { fg = color })
	end

	if force or not M.is_hl_defined("DifftChange") then
		local color = vim.g.terminal_color_3 or ansi_defaults.change
		vim.api.nvim_set_hl(0, "DifftChange", { fg = color })
	end

	if force or not M.is_hl_defined("DifftInfo") then
		local color = vim.g.terminal_color_6 or ansi_defaults.info
		vim.api.nvim_set_hl(0, "DifftInfo", { fg = color })
	end

	if force or not M.is_hl_defined("DifftHint") then
		local color = vim.g.terminal_color_5 or ansi_defaults.hint
		vim.api.nvim_set_hl(0, "DifftHint", { fg = color })
	end

	if force or not M.is_hl_defined("DifftDim") then
		local color = vim.g.terminal_color_8 or ansi_defaults.dim
		vim.api.nvim_set_hl(0, "DifftDim", { fg = color })
	end

	if force or not M.is_hl_defined("DifftFileHeader") then
		local color = vim.g.terminal_color_7 or ansi_defaults.header
		vim.api.nvim_set_hl(0, "DifftFileHeader", { fg = color })
	end
end

--- Build default diff highlights - link to Difft* groups
--- @return table Default highlights config
function M.build_default_diff_highlights()
	return {
		add = { link = "DifftAdd" },
		delete = { link = "DifftDelete" },
		change = { link = "DifftChange" },
		info = { link = "DifftInfo" },
		hint = { link = "DifftHint" },
		dim = { link = "DifftDim" },
	}
end

--- Normalize diff highlights - convert table configs to highlight groups
--- @param highlights table User highlight config (string or table values)
--- @return table Normalized config with group name strings
function M.normalize_diff_highlights(highlights)
	local normalized = {}

	for key, value in pairs(highlights) do
		if type(value) == "string" then
			normalized[key] = value
		elseif type(value) == "table" then
			local group_name = "DifftAnsi" .. key:sub(1,1):upper() .. key:sub(2)

			if value.link then
				local linked_hl = vim.api.nvim_get_hl(0, { name = value.link, link = false })
				local hl_opts = {}

				if linked_hl.fg then
					hl_opts.fg = linked_hl.fg
				end

				if not value.no_bg and linked_hl.bg then
					hl_opts.bg = linked_hl.bg
				end

				if next(hl_opts) then
					vim.api.nvim_set_hl(0, group_name, hl_opts)
				else
					vim.api.nvim_set_hl(0, group_name, { link = value.link })
				end

				normalized[key] = group_name
				goto continue
			end

			local hl_opts = {}
			if value.fg then
				hl_opts.fg = value.fg
			end
			if value.bg then
				hl_opts.bg = value.bg
			end

			if next(hl_opts) then
				vim.api.nvim_set_hl(0, group_name, {})
				vim.api.nvim_set_hl(0, group_name, hl_opts)
				normalized[key] = group_name
			else
				normalized[key] = nil
			end

			::continue::
		end
	end

	return normalized
end

return M
