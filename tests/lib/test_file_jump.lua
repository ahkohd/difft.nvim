-- luacheck: globals vim

--- Tests for file_jump.lua (line number extraction and file opening)

-- Setup package path
local script_dir = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h")
local repo_root = vim.fn.fnamemodify(script_dir, ":h:h")  -- Go up two levels: tests/lib -> tests -> root
package.path = package.path
	.. ";" .. repo_root .. "/lua/?.lua"
	.. ";" .. repo_root .. "/lua/?/init.lua"

local file_jump = require("difft.lib.file_jump")

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

--- Test 1: Extract single line number
function tests.test_extract_single_line_number()
	local line = " 6 import { defineConfig } from 'vite'"
	local line_num = file_jump.extract_line_number(line)
	assert_eq(line_num, 6, "Extracts single line number")
end

--- Test 2: Extract from ellipsis format
function tests.test_extract_ellipsis()
	local line1 = ".. 20"
	local line2 = "... 645"
	local line3 = ".... 2000"

	assert_eq(file_jump.extract_line_number(line1), 20, "Extracts from double dot")
	assert_eq(file_jump.extract_line_number(line2), 645, "Extracts from triple dot")
	assert_eq(file_jump.extract_line_number(line3), 2000, "Extracts from quad dot")
end

--- Test 3: Extract from single dot format (context line)
function tests.test_extract_single_dot()
	local line = ". 10"
	assert_eq(file_jump.extract_line_number(line), 10, "Extracts from single dot")
end

--- Test 4: Extract from side-by-side format (two numbers at start)
function tests.test_extract_side_by_side()
	local line = "580 642"
	-- Should prefer the second (right) number
	assert_eq(file_jump.extract_line_number(line), 642, "Prefers second number in side-by-side")
end

--- Test 5: Skip pure ellipsis lines
function tests.test_skip_pure_ellipsis()
	local line1 = "..."
	local line2 = "...."
	assert_eq(file_jump.extract_line_number(line1), nil, "Skips pure triple dot")
	assert_eq(file_jump.extract_line_number(line2), nil, "Skips pure quad dot")
end

--- Test 6: Handle empty or nil input
function tests.test_empty_input()
	assert_eq(file_jump.extract_line_number(""), nil, "Returns nil for empty string")
	assert_eq(file_jump.extract_line_number(nil), nil, "Returns nil for nil input")
end

--- Test 7: Two-column format - left side
function tests.test_two_column_left()
	-- Format: "number content ... number content"
	-- Left: "10 some code", Right: "15 other code"
	local line = " 10 some code here                        15 other code here"
	-- Cursor at column 5 (in left side)
	local line_num = file_jump.extract_line_number(line, 5)
	assert_eq(line_num, 10, "Extracts left number when cursor in left column")
end

--- Test 8: Two-column format - right side
function tests.test_two_column_right()
	local line = " 10 some code here                        15 other code here"
	-- Cursor at column 50 (in right side)
	local line_num = file_jump.extract_line_number(line, 50)
	assert_eq(line_num, 15, "Extracts right number when cursor in right column")
end

--- Test 9: Find header above - simple case
function tests.test_find_header_above_simple()
	local headers = {
		{line = 1, filename = "file1.lua"},
		{line = 10, filename = "file2.lua"},
		{line = 20, filename = "file3.lua"},
	}

	local header = file_jump.find_header_above(headers, 15)
	assert_eq(header ~= nil, true, "Found header")
	assert_eq(header.filename, "file2.lua", "Found correct header (file2)")
end

--- Test 10: Find header above - at boundary
function tests.test_find_header_above_boundary()
	local headers = {
		{line = 1, filename = "file1.lua"},
		{line = 10, filename = "file2.lua"},
	}

	-- Cursor at line 10 (on the header itself) - should return previous header
	local header = file_jump.find_header_above(headers, 10)
	assert_eq(header ~= nil, true, "Found header")
	assert_eq(header.filename, "file1.lua", "Returns previous header when on header line")
end

--- Test 11: Find header above - before first header
function tests.test_find_header_above_before_first()
	local headers = {
		{line = 10, filename = "file1.lua"},
		{line = 20, filename = "file2.lua"},
	}

	local header = file_jump.find_header_above(headers, 5)
	assert_eq(header, nil, "Returns nil when before first header")
end

--- Test 12: Find header above - empty headers
function tests.test_find_header_above_empty()
	local header = file_jump.find_header_above({}, 10)
	assert_eq(header, nil, "Returns nil for empty headers")

	header = file_jump.find_header_above(nil, 10)
	assert_eq(header, nil, "Returns nil for nil headers")
end

--- Test 13: Find header above - last position
function tests.test_find_header_above_last()
	local headers = {
		{line = 1, filename = "file1.lua"},
		{line = 10, filename = "file2.lua"},
		{line = 20, filename = "file3.lua"},
	}

	local header = file_jump.find_header_above(headers, 100)
	assert_eq(header ~= nil, true, "Found header")
	assert_eq(header.filename, "file3.lua", "Returns last header when past all headers")
end

--- Test 14: Extract line number with leading whitespace
function tests.test_extract_with_whitespace()
	local line = "   15 some content"
	assert_eq(file_jump.extract_line_number(line), 15, "Handles leading whitespace")
end

--- Test 15: No line number in text
function tests.test_no_line_number()
	local line = "just some text without numbers at start"
	assert_eq(file_jump.extract_line_number(line), nil, "Returns nil when no line number")
end

--- Test 16: Single number no leading whitespace
function tests.test_single_no_whitespace()
	local line = "3 import { useCallback, useEffect, useState } from 'react';"
	assert_eq(file_jump.extract_line_number(line), 3, "Single number without whitespace")
end

--- Test 17: Number at start of line
function tests.test_number_at_start()
	local line = "42 const value = true;"
	assert_eq(file_jump.extract_line_number(line), 42, "Number at line start")
end

--- Test 18: Multi-digit single number
function tests.test_multi_digit_single()
	local line = " 1234     function doSomething() {"
	assert_eq(file_jump.extract_line_number(line), 1234, "Multi-digit extraction")
end

--- Test 19: Side-by-side with content
function tests.test_side_by_side_with_content()
	local line = "580 642     -- Check if current line is a header"
	assert_eq(file_jump.extract_line_number(line), 642, "Side-by-side with content prefers right")
end

--- Test 20: Side-by-side with leading whitespace
function tests.test_side_by_side_leading_ws()
	local line = "  581 643     local header_info = nil"
	assert_eq(file_jump.extract_line_number(line), 643, "Side-by-side with leading whitespace")
end

--- Test 21: Multi-digit side-by-side
function tests.test_multi_digit_side_by_side()
	local line = "1234 5678 some content"
	assert_eq(file_jump.extract_line_number(line), 5678, "Multi-digit side-by-side")
end

--- Test 22: Real example - prefer right (1277 over 1249)
function tests.test_real_example_prefer_right()
	local line = "1249 1277             -- Only resize if diff is visible"
	assert_eq(file_jump.extract_line_number(line), 1277, "Real example: 1277 not 1249")
end

--- Test 23: Prefer right even when left is larger
function tests.test_prefer_right_when_left_larger()
	local line = "500 300     -- some deleted content"
	assert_eq(file_jump.extract_line_number(line), 300, "Prefer right even when smaller")
end

--- Test 24: Side-by-side with tabs
function tests.test_side_by_side_tabs()
	local line = "42	84 content here"
	assert_eq(file_jump.extract_line_number(line), 84, "Side-by-side with tabs")
end

--- Test 25: Side-by-side with multiple spaces
function tests.test_side_by_side_multi_spaces()
	local line = "123    456     code content"
	assert_eq(file_jump.extract_line_number(line), 456, "Side-by-side with multiple spaces")
end

--- Test 26: Single dot multi-digit
function tests.test_single_dot_multi_digit()
	local line = ". 123"
	assert_eq(file_jump.extract_line_number(line), 123, "Single dot with multi-digit")
end

--- Test 27: Single dot with leading whitespace
function tests.test_single_dot_leading_ws()
	local line = "   . 42"
	assert_eq(file_jump.extract_line_number(line), 42, "Single dot with leading whitespace")
end

--- Test 28: Single dot with content after
function tests.test_single_dot_with_content()
	local line = ". 10     const value = true;"
	assert_eq(file_jump.extract_line_number(line), 10, "Single dot with content")
end

--- Test 29: Pure single dot without number
function tests.test_pure_single_dot()
	assert_eq(file_jump.extract_line_number("."), nil, "Pure dot returns nil")
end

--- Test 30: Pure single dot with whitespace
function tests.test_pure_single_dot_ws()
	assert_eq(file_jump.extract_line_number("   .   "), nil, "Pure dot with whitespace")
end

--- Test 31: Pure two dots
function tests.test_pure_two_dots()
	assert_eq(file_jump.extract_line_number(".."), nil, "Pure two dots")
end

--- Test 32: Pure three dots
function tests.test_pure_three_dots()
	assert_eq(file_jump.extract_line_number("..."), nil, "Pure three dots")
end

--- Test 33: Pure ellipsis with whitespace
function tests.test_pure_ellipsis_ws()
	assert_eq(file_jump.extract_line_number("   ...."), nil, "Pure ellipsis with whitespace")
end

--- Test 34: 3-digit from 3-dot ellipsis
function tests.test_3_digit_3_dot()
	local line = "... 645"
	assert_eq(file_jump.extract_line_number(line), 645, "3-digit from 3-dot")
end

--- Test 35: 4-digit from 4-dot ellipsis
function tests.test_4_digit_4_dot()
	local line = ".... 2000"
	assert_eq(file_jump.extract_line_number(line), 2000, "4-digit from 4-dot")
end

--- Test 36: 5-digit from 5-dot ellipsis
function tests.test_5_digit_5_dot()
	local line = "..... 10000"
	assert_eq(file_jump.extract_line_number(line), 10000, "5-digit from 5-dot")
end

--- Test 37: Ellipsis with content
function tests.test_ellipsis_with_content()
	local line = "... 645     local line_num = nil"
	assert_eq(file_jump.extract_line_number(line), 645, "Ellipsis with content")
end

--- Test 38: Ellipsis with whitespace prefix
function tests.test_ellipsis_ws_prefix()
	local line = "   .. 99"
	assert_eq(file_jump.extract_line_number(line), 99, "Ellipsis with whitespace prefix")
end

--- Test 39: Two-column with cursor in left (from difft_spec)
function tests.test_two_column_cursor_left_detailed()
	local line = "1249 -- Only refresh if diff     1277 -- Only resize if diff"
	-- Cursor at column 10 (in left content)
	assert_eq(file_jump.extract_line_number(line, 10), 1249, "Cursor in left gets left number")
end

--- Test 40: Two-column with cursor in right (from difft_spec)
function tests.test_two_column_cursor_right_detailed()
	local line = "1249 -- Only refresh if diff     1277 -- Only resize if diff"
	-- Cursor at column 40 (in right content)
	assert_eq(file_jump.extract_line_number(line, 40), 1277, "Cursor in right gets right number")
end

--- Test 41: Two-column real diff example
function tests.test_two_column_real_diff()
	local line = "1249                 -- Only refresh    1277             -- Only resize"
	-- Left column
	assert_eq(file_jump.extract_line_number(line, 10), 1249, "Real diff left column")
	-- Right column
	assert_eq(file_jump.extract_line_number(line, 50), 1277, "Real diff right column")
end

--- Test 42: Two-column with varying whitespace
function tests.test_two_column_varying_ws()
	local line = "100 if state.is_floating      200 if state.is_visible"
	-- Left
	assert_eq(file_jump.extract_line_number(line, 5), 100, "Two-column varying ws left")
	-- Right
	assert_eq(file_jump.extract_line_number(line, 35), 200, "Two-column varying ws right")
end

--- Test 43: Two-column at boundary
function tests.test_two_column_boundary()
	local line = "50 left content      100 right content"
	-- Cursor at column 20 (right col start)
	assert_eq(file_jump.extract_line_number(line, 20), 100, "Boundary prefers right")
end

--- Test 44: Number not followed by whitespace
function tests.test_number_no_whitespace()
	local line = "123abc def"
	assert_eq(file_jump.extract_line_number(line), nil, "No whitespace after number")
end

--- Test 45: Always prefer new/right line in side-by-side
function tests.test_always_prefer_new_line()
	local line = "100 200     if state.is_floating and M.is_visible() then"
	assert_eq(file_jump.extract_line_number(line), 200, "Always prefer new/right line")
end

-- Run all tests
print("\n=== Running File Jump Tests ===\n")

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
