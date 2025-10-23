--- Test highlight object support in diff.highlights config

-- Setup package path
local script_dir = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h")
local repo_root = vim.fn.fnamemodify(script_dir, ":h")
package.path = package.path
	.. ";" .. repo_root .. "/lua/?.lua"
	.. ";" .. repo_root .. "/lua/?/init.lua"

-- Clear any existing difft setup
package.loaded["difft"] = nil
package.loaded["difft.lib.parser"] = nil

local difft = require("difft")

print("=== Testing Highlight Object Support ===\n")

-- Test 1: String values (backward compatibility)
print("Test 1: String values (backward compat)")
difft.setup({
	diff = {
		highlights = {
			add = "DiffAdd",
			delete = "DiffDelete",
		}
	}
})

-- Check that DiffAdd group exists
local add_hl = vim.api.nvim_get_hl(0, {name = "DiffAdd"})
if add_hl then
	print("✓ String values work (DiffAdd exists)")
else
	print("✗ String values failed")
end

-- Test 2: Table with direct colors
print("\nTest 2: Table with direct colors")
difft.setup({
	diff = {
		highlights = {
			add = {fg = "#00ff00"},
			delete = {fg = "#ff0000", bg = "#300000"},
		}
	}
})

-- Check that DifftAnsiAdd group was created
local custom_add = vim.api.nvim_get_hl(0, {name = "DifftAnsiAdd"})
if custom_add and custom_add.fg then
	print("✓ DifftAnsiAdd created with fg=" .. string.format("#%06x", custom_add.fg))
else
	print("✗ DifftAnsiAdd not created properly")
end

local custom_delete = vim.api.nvim_get_hl(0, {name = "DifftAnsiDelete"})
if custom_delete and custom_delete.fg and custom_delete.bg then
	print("✓ DifftAnsiDelete created with fg=" .. string.format("#%06x", custom_delete.fg) ..
	      " bg=" .. string.format("#%06x", custom_delete.bg))
else
	print("✗ DifftAnsiDelete not created properly")
end

-- Test 3: Table with link (extracts colors for bold support)
print("\nTest 3: Table with link extracts colors")
difft.setup({
	diff = {
		highlights = {
			add = {link = "String"},
			change = {link = "WarningMsg"},
		}
	}
})

-- Check that DifftAnsiAdd extracted colors from String (not a Neovim link)
local link_add = vim.api.nvim_get_hl(0, {name = "DifftAnsiAdd", link = false})
local string_hl = vim.api.nvim_get_hl(0, {name = "String", link = false})
if link_add and string_hl and link_add.fg then
	print("✓ DifftAnsiAdd extracts colors from String")
	print("  (allows bold variants to be created)")
else
	print("✗ DifftAnsiAdd extraction failed")
end

local link_change = vim.api.nvim_get_hl(0, {name = "DifftAnsiChange", link = false})
local warning_hl = vim.api.nvim_get_hl(0, {name = "WarningMsg", link = false})
if link_change and warning_hl and link_change.fg then
	print("✓ DifftAnsiChange extracts colors from WarningMsg")
else
	print("✗ DifftAnsiChange extraction failed")
end

-- Test 4: Mixed string and table
print("\nTest 4: Mixed string and table")
difft.setup({
	diff = {
		highlights = {
			add = {fg = "#00ff00"},
			delete = "DiffDelete",
			change = {link = "DiffChange"},
		}
	}
})

custom_add = vim.api.nvim_get_hl(0, {name = "DifftAnsiAdd", link = false})
local string_delete = vim.api.nvim_get_hl(0, {name = "DiffDelete"})
link_change = vim.api.nvim_get_hl(0, {name = "DifftAnsiChange", link = false})

if custom_add and custom_add.fg and string_delete and link_change and link_change.fg then
	print("✓ Mixed string and table works")
	print("  Custom fg, string passthrough, and link extraction all work")
else
	print("✗ Mixed string and table failed")
end

-- Test 5: ANSI parsing still works
print("\nTest 5: ANSI parsing with custom highlights")
local parser = require("difft.lib.parser")

-- Setup with custom color
difft.setup({
	diff = {
		highlights = {
			add = {fg = "#00ff00"},
		}
	}
})

-- Parse a green ANSI line
local line = "\27[32madded text\27[0m"
local text, highlights = parser.parse_ansi_line(line)

if text == "added text" and #highlights == 1 then
	local hl_group = highlights[1].hl_group
	-- Should be DifftAnsiAdd (without formatting) or DifftAnsiAdd_* (with formatting)
	if hl_group:match("^DifftAnsiAdd") or hl_group == "DiffAdd" then
		print("✓ ANSI parsing works with custom highlights")
		print("  Highlight group: " .. hl_group)
	else
		print("✗ Unexpected highlight group: " .. hl_group)
	end
else
	print("✗ ANSI parsing failed")
end

-- Test 6: Bold formatting overrides still work with custom highlights
print("\nTest 6: Bold/italic/dim formatting with custom highlights")
difft.setup({
	diff = {
		highlights = {
			add = {fg = "#00ff00"},
		}
	}
})

-- Parse a bold green ANSI line
local bold_line = "\27[1;32mbold added\27[0m"
local bold_text, bold_highlights = parser.parse_ansi_line(bold_line)

if bold_text == "bold added" and #bold_highlights == 1 then
	local hl_group = bold_highlights[1].hl_group
	-- Should have _bold suffix
	if hl_group:match("_bold") then
		print("✓ Bold formatting works with custom highlights")
		print("  Highlight group: " .. hl_group)

		-- Verify the base group exists and has our custom color
		local base_group = vim.api.nvim_get_hl(0, {name = "DifftAnsiAdd", link = false})
		if base_group and base_group.fg then
			print("  Base group has custom fg: " .. string.format("#%06x", base_group.fg))
		end
	else
		print("✗ Bold formatting failed - no _bold suffix")
	end
else
	print("✗ Bold formatting test failed")
end

-- Test 7: Link with no_bg flag (foreground only)
print("\nTest 7: Link with no_bg flag (foreground only)")
-- Create a test highlight group with both fg and bg
vim.api.nvim_set_hl(0, "TestGroupWithBg", {fg = 0xff0000, bg = 0x00ff00})

difft.setup({
	diff = {
		highlights = {
			add = {link = "TestGroupWithBg", no_bg = true},
		}
	}
})

local no_bg_hl = vim.api.nvim_get_hl(0, {name = "DifftAnsiAdd", link = false})
if no_bg_hl and no_bg_hl.fg and not no_bg_hl.bg then
	print("✓ no_bg flag works - extracted only foreground")
	print("  fg=" .. string.format("#%06x", no_bg_hl.fg) .. " (bg not set)")
elseif no_bg_hl and no_bg_hl.bg then
	print("✗ no_bg flag failed - background is still set")
	print("  fg=" .. string.format("#%06x", no_bg_hl.fg or 0) .. " bg=" .. string.format("#%06x", no_bg_hl.bg))
else
	print("✗ no_bg flag test failed - group not created properly")
end

-- Test 8: Link without no_bg (full extraction for bold support)
print("\nTest 8: Link without no_bg extracts colors for bold support")
vim.api.nvim_set_hl(0, "TestGroupForBold", {fg = 0x0000ff, bg = 0xffff00})

difft.setup({
	diff = {
		highlights = {
			change = {link = "TestGroupForBold"},
		}
	}
})

local with_bg_hl = vim.api.nvim_get_hl(0, {name = "DifftAnsiChange", link = false})
if with_bg_hl and with_bg_hl.fg and with_bg_hl.bg then
	print("✓ Link extracts both fg and bg (not a Neovim link)")
	print("  fg=" .. string.format("#%06x", with_bg_hl.fg) .. " bg=" .. string.format("#%06x", with_bg_hl.bg))

	-- Verify bold variant can be created
	local bold_group_name = "DifftAnsiChange_bold"
	vim.api.nvim_set_hl(0, bold_group_name, vim.tbl_extend("force", with_bg_hl, {bold = true}))
	local bold_variant = vim.api.nvim_get_hl(0, {name = bold_group_name, link = false})

	if bold_variant and bold_variant.bold and bold_variant.fg and bold_variant.bg then
		print("✓ Bold variant inherits colors and adds bold")
	else
		print("✗ Bold variant creation failed")
	end
else
	print("✗ Link extraction failed")
	if with_bg_hl then
		print("  has fg: " .. tostring(with_bg_hl.fg ~= nil) .. " has bg: " .. tostring(with_bg_hl.bg ~= nil))
	end
end

-- Test 9: Custom colors are not deep-merged with defaults
print("\nTest 9: Custom colors replace defaults (not merge)")
difft.setup({
	diff = {
		highlights = {
			add = {fg = "#123456", bg = "#abcdef"},
		}
	}
})

local custom_only = vim.api.nvim_get_hl(0, {name = "DifftAnsiAdd", link = false})
-- Should NOT have 'link' or 'no_bg' from defaults
local config_add = require("difft").get_config().diff.highlights.add
if type(config_add) == "table" and config_add.fg and config_add.bg and not config_add.link and not config_add.no_bg then
	print("✓ Custom colors replace defaults (no merge)")
	print("  Config has fg and bg only")
else
	print("✗ Deep merge issue - defaults leaked into custom config")
	if type(config_add) == "table" then
		print("  Config keys: " .. table.concat(vim.tbl_keys(config_add), ", "))
	end
end

-- Test 10: Default config uses smart detection
print("\nTest 10: Default config uses smart detection based on colorscheme")
-- Reload to get defaults
package.loaded["difft"] = nil
package.loaded["difft.lib.parser"] = nil
difft = require("difft")

-- Don't call setup, use defaults
local default_config = difft.get_config()
local add_hl = default_config.diff.highlights.add

if type(add_hl) == "table" and add_hl.link == "DifftAdd" then
	print("✓ Default config uses { link = 'DifftAdd' }")

	-- Check that DifftAdd was created with fg only
	local difft_add = vim.api.nvim_get_hl(0, {name = "DifftAdd", link = false})
	if difft_add and difft_add.fg and not difft_add.bg then
		print("  DifftAdd has fg only (no bg) ✓")
	elseif difft_add and difft_add.fg and difft_add.bg then
		print("  ⚠ DifftAdd has both fg and bg (theme override?)")
	else
		print("  ⚠ DifftAdd:", vim.inspect(difft_add))
	end
else
	print("✗ Unexpected default config format")
	print("  add = " .. vim.inspect(add_hl))
end

-- Test 11: Link fallback when linked group has no colors
print("\nTest 11: Link fallback when no colors found")
vim.api.nvim_set_hl(0, "EmptyGroup", {})  -- Group with no fg/bg

difft.setup({
	diff = {
		highlights = {
			add = {link = "EmptyGroup"},
		}
	}
})

local fallback_hl = vim.api.nvim_get_hl(0, {name = "DifftAnsiAdd", link = true})
if fallback_hl and fallback_hl.link == "EmptyGroup" then
	print("✓ Falls back to Neovim link when no colors found")
else
	print("✗ Fallback behavior failed")
	if fallback_hl then
		print("  Got: " .. vim.inspect(fallback_hl))
	end
end

-- Test 12: Table with only fg (no bg)
print("\nTest 12: Table with only fg color")
difft.setup({
	diff = {
		highlights = {
			add = {fg = "#ff00ff"},
		}
	}
})

local fg_only = vim.api.nvim_get_hl(0, {name = "DifftAnsiAdd", link = false})
if fg_only and fg_only.fg and not fg_only.bg then
	print("✓ Highlight with only fg works")
	print("  fg=" .. string.format("#%06x", fg_only.fg) .. " (no bg)")
else
	print("✗ fg-only highlight failed")
	if fg_only then
		print("  has fg: " .. tostring(fg_only.fg ~= nil) .. " has bg: " .. tostring(fg_only.bg ~= nil))
	end
end

-- Test 13: Table with only bg (no fg) - edge case
print("\nTest 13: Table with only bg color (edge case)")
difft.setup({
	diff = {
		highlights = {
			add = {bg = "#00ffff"},
		}
	}
})

local bg_only = vim.api.nvim_get_hl(0, {name = "DifftAnsiAdd", link = false})
if bg_only and bg_only.bg and not bg_only.fg then
	print("✓ Highlight with only bg works")
	print("  bg=" .. string.format("#%06x", bg_only.bg) .. " (no fg)")
elseif not bg_only then
	print("⚠ bg-only highlight not created (acceptable behavior)")
else
	print("✗ bg-only highlight failed")
end

-- Test 14: Empty table (invalid config)
print("\nTest 14: Empty table handling")
-- Clear previous DifftAnsiAdd to avoid pollution
vim.api.nvim_set_hl(0, "DifftAnsiAdd", {})

difft.setup({
	diff = {
		highlights = {
			add = {},  -- Empty table, no properties
			delete = "DiffDelete",  -- Keep a valid one for comparison
		}
	}
})

local empty_result = vim.api.nvim_get_hl(0, {name = "DifftAnsiAdd", link = false})
local config_highlights = require("difft").get_config().diff.highlights
-- Empty tables should result in nil in normalized config, or empty highlight group
if not config_highlights.add then
	print("✓ Empty table returns nil (skipped)")
elseif vim.tbl_isempty(empty_result) or (not empty_result.fg and not empty_result.bg and not empty_result.link) then
	print("✓ Empty table creates empty group (acceptable)")
else
	print("⚠ Empty table created group with properties: " .. vim.inspect(empty_result))
end

-- Test 15: Colorscheme change re-normalizes highlights with smart detection
print("\nTest 15: ColorScheme autocmd re-normalizes with smart detection")
-- Reload modules for clean slate
package.loaded["difft"] = nil
package.loaded["difft.lib.parser"] = nil
difft = require("difft")

-- Set initial DiffAdd color with fg
vim.api.nvim_set_hl(0, "DiffAdd", {fg = 0xff0000, bg = 0x00ff00})

-- Set up with defaults
difft.setup({})

-- Get current DifftAnsiAdd (should have fg only from DifftAdd)
local before_hl = vim.api.nvim_get_hl(0, {name = "DifftAnsiAdd", link = false})

-- Change DiffAdd to new colors
vim.api.nvim_set_hl(0, "DiffAdd", {fg = 0x0000ff, bg = 0xffff00})

-- Trigger ColorScheme autocmd (should recreate DifftAdd with new fg only, then update DifftAnsiAdd)
vim.cmd("doautocmd ColorScheme")

-- Check if DifftAnsiAdd was updated to new fg (no bg)
local after_hl = vim.api.nvim_get_hl(0, {name = "DifftAnsiAdd", link = false})

if after_hl and after_hl.fg == 0x0000ff and not after_hl.bg then
	print("✓ ColorScheme autocmd updates to new colors (fg only)")
	print("  Updated fg to #0000ff (bg stripped)")
elseif after_hl and after_hl.fg == before_hl.fg then
	print("⚠ ColorScheme autocmd didn't update (still has old fg)")
else
	print("⚠ ColorScheme re-normalization behavior unclear")
	if after_hl then
		print("  fg=" .. (after_hl.fg and string.format("#%06x", after_hl.fg) or "nil") ..
		      " bg=" .. (after_hl.bg and string.format("#%06x", after_hl.bg) or "nil"))
	end
end

-- Test 16: Bold variants created by parser inherit fg color correctly
print("\nTest 16: Parser creates bold variants with fg color (link=false fix)")
-- Reload for clean state
package.loaded["difft"] = nil
package.loaded["difft.lib.parser"] = nil
difft = require("difft")

-- Create a highlight with only foreground (like DevIconBashrc)
vim.api.nvim_set_hl(0, "TestIconGroup", {fg = 0xabcdef})

difft.setup({
	diff = {
		highlights = {
			add = {link = "TestIconGroup"},
		}
	}
})

-- Use parser to parse bold green text
local parser = require("difft.lib.parser")
local bold_line = "\27[1;32mbold text\27[0m"
local text, highlights = parser.parse_ansi_line(bold_line)

if #highlights == 1 then
	local hl_group = highlights[1].hl_group
	-- Should be DifftAnsiAdd_bold
	if hl_group:match("_bold$") then
		local hl_props = vim.api.nvim_get_hl(0, {name = hl_group, link = false})

		if hl_props.bold and hl_props.fg == 0xabcdef then
			print("✓ Bold variant has BOTH bold=true AND fg color")
			print("  fg=" .. string.format("#%06x", hl_props.fg) .. " bold=true")
		elseif hl_props.bold and not hl_props.fg then
			print("✗ REGRESSION: Bold variant has bold but MISSING fg color")
			print("  This is the bug we fixed with link=false parameter")
		elseif hl_props.fg and not hl_props.bold then
			print("✗ Bold variant has fg but MISSING bold attribute")
		else
			print("⚠ Bold variant properties unclear: " .. vim.inspect(hl_props))
		end
	else
		print("✗ Expected _bold suffix, got: " .. hl_group)
	end
else
	print("✗ Parser didn't return highlights")
end

-- Test 17: Normal (non-bold) text uses base group with fg
print("\nTest 17: Non-bold text uses base group with fg color")
local normal_line = "\27[32mnormal text\27[0m"
local text2, highlights2 = parser.parse_ansi_line(normal_line)

if #highlights2 == 1 then
	local hl_group2 = highlights2[1].hl_group
	local hl_props2 = vim.api.nvim_get_hl(0, {name = hl_group2, link = false})

	if hl_props2.fg == 0xabcdef and not hl_props2.bold then
		print("✓ Non-bold text has fg color without bold")
		print("  fg=" .. string.format("#%06x", hl_props2.fg) .. " bold=nil")
	else
		print("⚠ Non-bold properties: " .. vim.inspect(hl_props2))
	end
end

-- Test 18: Underline support
print("\nTest 18: Underline formatting")
vim.api.nvim_set_hl(0, "TestUnderlineGroup", {fg = 0x00ff00})

difft.setup({
	diff = {
		highlights = {
			add = {link = "TestUnderlineGroup"},
		}
	}
})

-- Test underline alone
local parser = require("difft.lib.parser")
local underline_line = "\27[4;32munderlined text\27[0m"
local text, highlights = parser.parse_ansi_line(underline_line)

if #highlights == 1 then
	local hl_group = highlights[1].hl_group
	local hl_props = vim.api.nvim_get_hl(0, {name = hl_group, link = false})

	if hl_props.underline and hl_props.fg == 0x00ff00 then
		print("✓ Underline variant has underline=true AND fg color")
		print("  fg=#00ff00 underline=true")
	else
		print("✗ Underline variant failed: " .. vim.inspect(hl_props))
	end
else
	print("✗ Parser didn't return highlights")
end

-- Test 19: Bold + Underline combination
print("\nTest 19: Bold + Underline combination")
local bold_underline_line = "\27[1;4;32mbold underlined text\27[0m"
local text2, highlights2 = parser.parse_ansi_line(bold_underline_line)

if #highlights2 == 1 then
	local hl_group2 = highlights2[1].hl_group
	local hl_props2 = vim.api.nvim_get_hl(0, {name = hl_group2, link = false})

	if hl_props2.bold and hl_props2.underline and hl_props2.fg == 0x00ff00 then
		print("✓ Bold+Underline variant has ALL properties")
		print("  fg=#00ff00 bold=true underline=true")
		print("  Group name: " .. hl_group2)
	else
		print("✗ Bold+Underline failed: " .. vim.inspect(hl_props2))
		print("  Expected: bold=true underline=true fg=#00ff00")
	end
else
	print("✗ Parser didn't return highlights")
end

print("\n=== All Tests Complete ===")
