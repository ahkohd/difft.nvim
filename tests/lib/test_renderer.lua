-- luacheck: globals vim

--- Tests for renderer.lua (buffer rendering and highlights)

-- Setup package path
local script_dir = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h")
local repo_root = vim.fn.fnamemodify(script_dir, ":h:h")  -- Go up two levels: tests/lib -> tests -> root
package.path = package.path
	.. ";" .. repo_root .. "/lua/?.lua"
	.. ";" .. repo_root .. "/lua/?/init.lua"

local renderer = require("difft.lib.renderer")

local tests = {}
local passed = 0
local failed = 0

--- Test helper
local function assert_eq(actual, expected, test_name)
	if actual == expected then
		passed = passed + 1
		print("✓ " .. test_name)
		return true
	else
		failed = failed + 1
		print("✗ " .. test_name)
		print("  Expected: " .. tostring(expected))
		print("  Got:      " .. tostring(actual))
		return false
	end
end

--- Create a test buffer with content
local function create_test_buffer(lines)
	local buf = vim.api.nvim_create_buf(false, true)  -- unlisted, scratch
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	return buf
end

--- Get extmarks from a buffer
local function get_extmarks(buf, ns, line_num)
	return vim.api.nvim_buf_get_extmarks(buf, ns, {line_num, 0}, {line_num, -1}, {details = true})
end

--- Test 1: Apply simple highlight to a line
function tests.test_apply_simple_highlight()
	local buf = create_test_buffer({"test line"})
	local ns = vim.api.nvim_create_namespace("test_renderer_1")

	local highlights = {
		{col = 0, length = 4, hl_group = "DiffAdd"},
	}

	renderer.apply_line_highlights(buf, 0, highlights, ns)

	local extmarks = get_extmarks(buf, ns, 0)
	assert_eq(#extmarks > 0, true, "Extmark created")

	-- Find the text highlight extmark (has hl_group, not number_hl_group)
	local text_highlight = nil
	for _, mark in ipairs(extmarks) do
		if mark[4].hl_group and not mark[4].number_hl_group then
			text_highlight = mark[4]
			break
		end
	end

	assert_eq(text_highlight ~= nil, true, "Text highlight found")
	assert_eq(text_highlight.hl_group, "DiffAdd", "Correct highlight group")
	assert_eq(text_highlight.end_col, 4, "Correct end column")

	vim.api.nvim_buf_delete(buf, {force = true})
end

--- Test 2: Apply multiple highlights to a line
function tests.test_apply_multiple_highlights()
	local buf = create_test_buffer({"added removed"})
	local ns = vim.api.nvim_create_namespace("test_renderer_2")

	local highlights = {
		{col = 0, length = 5, hl_group = "DiffAdd"},
		{col = 6, length = 7, hl_group = "DiffDelete"},
	}

	renderer.apply_line_highlights(buf, 0, highlights, ns)

	local extmarks = get_extmarks(buf, ns, 0)
	-- Should have at least 2 extmarks (may have more for line number coloring)
	assert_eq(#extmarks >= 2, true, "Multiple extmarks created")

	vim.api.nvim_buf_delete(buf, {force = true})
end

--- Test 3: Line number coloring for DiffAdd
function tests.test_line_number_coloring_add()
	local buf = create_test_buffer({"added line"})
	local ns = vim.api.nvim_create_namespace("test_renderer_3")

	local highlights = {
		{col = 0, length = 5, hl_group = "DiffAdd"},
	}

	renderer.apply_line_highlights(buf, 0, highlights, ns, {line_number_coloring = true})

	local extmarks = get_extmarks(buf, ns, 0)

	-- Find extmark with number_hl_group
	local found_line_number_hl = false
	for _, mark in ipairs(extmarks) do
		if mark[4].number_hl_group == "DiffAdd" then
			found_line_number_hl = true
			break
		end
	end

	assert_eq(found_line_number_hl, true, "Line number colored for DiffAdd")

	vim.api.nvim_buf_delete(buf, {force = true})
end

--- Test 4: Line number coloring for DiffDelete
function tests.test_line_number_coloring_delete()
	local buf = create_test_buffer({"deleted line"})
	local ns = vim.api.nvim_create_namespace("test_renderer_4")

	local highlights = {
		{col = 0, length = 7, hl_group = "DiffDelete"},
	}

	renderer.apply_line_highlights(buf, 0, highlights, ns, {line_number_coloring = true})

	local extmarks = get_extmarks(buf, ns, 0)

	-- Find extmark with number_hl_group
	local found_line_number_hl = false
	for _, mark in ipairs(extmarks) do
		if mark[4].number_hl_group == "DiffDelete" then
			found_line_number_hl = true
			break
		end
	end

	assert_eq(found_line_number_hl, true, "Line number colored for DiffDelete")

	vim.api.nvim_buf_delete(buf, {force = true})
end

--- Test 5: Disable line number coloring
function tests.test_disable_line_number_coloring()
	local buf = create_test_buffer({"test line"})
	local ns = vim.api.nvim_create_namespace("test_renderer_5")

	local highlights = {
		{col = 0, length = 4, hl_group = "DiffAdd"},
	}

	renderer.apply_line_highlights(buf, 0, highlights, ns, {line_number_coloring = false})

	local extmarks = get_extmarks(buf, ns, 0)

	-- Should not have line number coloring
	local found_line_number_hl = false
	for _, mark in ipairs(extmarks) do
		if mark[4].number_hl_group then
			found_line_number_hl = true
			break
		end
	end

	assert_eq(found_line_number_hl, false, "Line number coloring disabled")

	vim.api.nvim_buf_delete(buf, {force = true})
end

--- Test 6: Empty line support
function tests.test_empty_line_support()
	local buf = create_test_buffer({"", "non-empty"})
	local ns = vim.api.nvim_create_namespace("test_renderer_6")

	local highlights = {
		{col = 0, length = 10, hl_group = "DiffAdd"},
	}

	renderer.apply_line_highlights(buf, 0, highlights, ns, {empty_line_support = true})

	local extmarks = get_extmarks(buf, ns, 0)

	-- Find extmark with end_row (indicates full line highlight)
	local found_full_line = false
	for _, mark in ipairs(extmarks) do
		if mark[4].end_row then
			found_full_line = true
			break
		end
	end

	assert_eq(found_full_line, true, "Empty line gets full line highlight")

	vim.api.nvim_buf_delete(buf, {force = true})
end

--- Test 7: Custom header with simple string
function tests.test_custom_header_string()
	local buf = create_test_buffer({"old_header.lua --- 1/1 --- Lua"})
	local ns = vim.api.nvim_create_namespace("test_renderer_7")

	local headers = {
		{line = 1, filename = "old_header.lua", language = "Lua", step = {current = 1, of = 1}},
	}

	local config = {
		header = {
			content = function(filename, step, language)
				return "📄 " .. filename
			end
		}
	}

	renderer.render_custom_headers(buf, {"old_header.lua --- 1/1 --- Lua"}, headers, config, ns)

	local new_line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
	assert_eq(new_line, "📄 old_header.lua", "Header replaced with custom string")

	vim.api.nvim_buf_delete(buf, {force = true})
end

--- Test 8: Custom header with table (text + highlights)
function tests.test_custom_header_table()
	local buf = create_test_buffer({"test.lua --- 1/1 --- Lua"})
	local ns = vim.api.nvim_create_namespace("test_renderer_8")

	local headers = {
		{line = 1, filename = "test.lua", language = "Lua", step = {current = 1, of = 1}},
	}

	local config = {
		header = {
			content = function(filename, step, language)
				return {
					{"File: ", "Comment"},
					{filename, "String"},
				}
			end
		}
	}

	renderer.render_custom_headers(buf, {"test.lua --- 1/1 --- Lua"}, headers, config, ns)

	local new_line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
	assert_eq(new_line, "File: test.lua", "Header replaced with custom content")

	-- Check that extmarks were created for highlights
	local extmarks = get_extmarks(buf, ns, 0)
	assert_eq(#extmarks >= 2, true, "Custom highlights created")

	vim.api.nvim_buf_delete(buf, {force = true})
end

--- Test 9: Custom header returns nil (no replacement)
function tests.test_custom_header_nil()
	local buf = create_test_buffer({"original.lua --- 1/1 --- Lua"})
	local ns = vim.api.nvim_create_namespace("test_renderer_9")

	local headers = {
		{line = 1, filename = "original.lua", language = "Lua", step = {current = 1, of = 1}},
	}

	local config = {
		header = {
			content = function(filename, step, language)
				return nil  -- Don't replace
			end
		}
	}

	renderer.render_custom_headers(buf, {"original.lua --- 1/1 --- Lua"}, headers, config, ns)

	local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
	assert_eq(line, "original.lua --- 1/1 --- Lua", "Header unchanged when nil returned")

	vim.api.nvim_buf_delete(buf, {force = true})
end

--- Test 10: Apply header highlight (full width)
function tests.test_header_highlight_full_width()
	local buf = create_test_buffer({"test.lua --- Lua"})
	local ns = vim.api.nvim_create_namespace("test_renderer_10")

	-- First define the highlight group
	vim.api.nvim_set_hl(0, "DifftFileHeader", {fg = "#ffffff", bg = "#000000"})

	local config = {
		header = {
			highlight = {
				fg = "#ffffff",
				bg = "#000000",
				full_width = true,
			}
		}
	}

	renderer.apply_header_highlight(buf, 1, "test.lua --- Lua", false, config, ns)

	local extmarks = get_extmarks(buf, ns, 0)
	assert_eq(#extmarks > 0, true, "Header highlight applied")

	-- Check for full width (hl_eol = true)
	local has_full_width = false
	for _, mark in ipairs(extmarks) do
		if mark[4].hl_eol then
			has_full_width = true
			break
		end
	end
	assert_eq(has_full_width, true, "Full width highlight applied")

	vim.api.nvim_buf_delete(buf, {force = true})
end

--- Test 11: Apply header highlight (text only)
function tests.test_header_highlight_text_only()
	local buf = create_test_buffer({"test.lua --- Lua"})
	local ns = vim.api.nvim_create_namespace("test_renderer_11")

	vim.api.nvim_set_hl(0, "DifftFileHeader", {fg = "#ffffff"})

	local config = {
		header = {
			highlight = {
				fg = "#ffffff",
				full_width = false,
			}
		}
	}

	renderer.apply_header_highlight(buf, 1, "test.lua --- Lua", false, config, ns)

	local extmarks = get_extmarks(buf, ns, 0)
	assert_eq(#extmarks > 0, true, "Header highlight applied")

	-- Should not have hl_eol (not full width)
	local has_full_width = false
	for _, mark in ipairs(extmarks) do
		if mark[4].hl_eol then
			has_full_width = true
			break
		end
	end
	assert_eq(has_full_width, false, "Text-only highlight (not full width)")

	vim.api.nvim_buf_delete(buf, {force = true})
end

--- Test 12: Skip header highlight if custom highlights exist
function tests.test_skip_header_highlight_with_custom()
	local buf = create_test_buffer({"test.lua --- Lua"})
	local ns = vim.api.nvim_create_namespace("test_renderer_12")

	vim.api.nvim_set_hl(0, "DifftFileHeader", {fg = "#ffffff"})

	local config = {
		header = {
			highlight = {
				fg = "#ffffff",
			}
		}
	}

	-- Pass has_custom_highlights = true to skip
	renderer.apply_header_highlight(buf, 1, "test.lua --- Lua", true, config, ns)

	local extmarks = get_extmarks(buf, ns, 0)
	assert_eq(#extmarks, 0, "Header highlight skipped when custom highlights exist")

	vim.api.nvim_buf_delete(buf, {force = true})
end

-- Run all tests
print("\n=== Running Renderer Tests ===\n")

for name, test_fn in pairs(tests) do
	local ok, err = pcall(test_fn)
	if not ok then
		failed = failed + 1
		print("✗ " .. name .. " (error)")
		print("  " .. tostring(err))
	end
end

print("\n=== Results ===")
print("Passed: " .. passed)
print("Failed: " .. failed)

if failed == 0 then
	print("\n✓ All tests passed!")
	os.exit(0)
else
	print("\n✗ Some tests failed")
	os.exit(1)
end
