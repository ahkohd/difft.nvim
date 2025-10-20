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

-- Test 3: Table with link
print("\nTest 3: Table with link")
difft.setup({
	diff = {
		highlights = {
			add = {link = "String"},
			change = {link = "WarningMsg"},
		}
	}
})

-- Check that DifftAnsiAdd links to String
local link_add = vim.api.nvim_get_hl(0, {name = "DifftAnsiAdd", link = true})
if link_add and link_add.link == "String" then
	print("✓ DifftAnsiAdd links to String")
else
	print("✗ DifftAnsiAdd link failed")
end

local link_change = vim.api.nvim_get_hl(0, {name = "DifftAnsiChange", link = true})
if link_change and link_change.link == "WarningMsg" then
	print("✓ DifftAnsiChange links to WarningMsg")
else
	print("✗ DifftAnsiChange link failed")
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
link_change = vim.api.nvim_get_hl(0, {name = "DifftAnsiChange", link = true})

if custom_add and custom_add.fg and string_delete and link_change and link_change.link then
	print("✓ Mixed string and table works")
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

print("\n=== All Tests Complete ===")
