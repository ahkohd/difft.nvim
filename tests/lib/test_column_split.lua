-- luacheck: globals vim

--- Tests for column splitting functionality (per-section algorithm)

-- Setup package path
local script_dir = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h")
local repo_root = vim.fn.fnamemodify(script_dir, ":h:h")  -- Go up two levels: tests/lib -> tests -> root
package.path = package.path
	.. ";" .. repo_root .. "/lua/?.lua"
	.. ";" .. repo_root .. "/lua/?/init.lua"

local column_split = require("difft.lib.column_split")

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

--- Test 1: Detect side-by-side format (algorithm finds gutter)
function tests.test_side_by_side_detection()
	local lines = {
		"file.lua --- 1/1 --- Lua",  -- Header at line 1
		" 1 [manager]                             1 [mgr]",
		" 2 cwd = { fg = \"#C1A890\" }              2 cwd = { fg = \"#CEDEAD\" }",
		" 3 hovered = { reversed = true }         3 hovered = { reversed = true }",
	}

	local header_lines = { [1] = true }  -- Line 1 is a header

	local split_columns = column_split.calculate_split_columns_per_section(lines, header_lines, 100)

	-- Headers should not have split column
	assert_eq(split_columns[1], nil, "Header has no split column")

	-- Content lines should detect a gutter (algorithm finds it at max_width/2)
	local split_col = split_columns[2]
	assert_eq(split_col > 0, true, "Line 2 has side-by-side split")
	assert_eq(split_columns[2], split_col, "All lines use same split in section")
	assert_eq(split_columns[3], split_col, "All lines use same split in section")
	assert_eq(split_columns[4], split_col, "All lines use same split in section")
end

--- Test 2: Detect single column format (no gutter - dense content)
function tests.test_single_column_no_gutter()
	local lines = {
		"file.lua --- 1/1 --- Lua",
		"1 function very_long_function_name_that_has_no_gaps_or_whitespace_gutters()",
		"2   local x=very_long_variable_without_gaps_this_is_single_column_content",
		"3 end_of_function_with_no_side_by_side_just_dense_single_column_text",
	}

	local header_lines = { [1] = true }

	local split_columns = column_split.calculate_split_columns_per_section(lines, header_lines, 100)

	-- Content lines should have split_col = 0 (single column - no gutter detected)
	assert_eq(split_columns[2], 0, "Line 2 single column")
	assert_eq(split_columns[3], 0, "Line 3 single column")
	assert_eq(split_columns[4], 0, "Line 4 single column")
end

--- Test 3: Split lines correctly with per-section split columns
function tests.test_split_lines_side_by_side()
	local lines = {
		"file.lua --- 1/1 --- Lua",
		" 1 [manager]                             1 [mgr]",
		" 2 cwd = { fg = \"#C1A890\" }              2 cwd = { fg = \"#CEDEAD\" }",
	}

	local header_lines = { [1] = true }
	local split_columns = column_split.calculate_split_columns_per_section(lines, header_lines, 100)

	local left_lines, right_lines, trim_info = column_split.split_lines(lines, split_columns, header_lines)

	assert_eq(#left_lines, 3, "Left has 3 lines")
	assert_eq(#right_lines, 3, "Right has 3 lines")

	-- Header goes to both sides (for navigation support)
	assert_eq(left_lines[1], "file.lua --- 1/1 --- Lua", "Header on left")
	assert_eq(right_lines[1], "file.lua --- 1/1 --- Lua", "Header on right too")

	-- Check split content
	assert_eq(left_lines[2]:find("manager") ~= nil, true, "Left contains 'manager'")
	assert_eq(right_lines[2]:find("mgr") ~= nil, true, "Right contains 'mgr'")
	assert_eq(left_lines[2]:find("mgr") == nil, true, "Left doesn't contain 'mgr'")
end

--- Test 4: Handle multiple sections with different split columns
function tests.test_multiple_sections()
	local lines = {
		"file1.lua --- 1/2 --- Lua",                                   -- Header 1
		" 1 short line                           1 another short",     -- Section 1: side-by-side
		" 2 test                                 2 test",
		"file2.lua --- 2/2 --- Lua",                                   -- Header 2
		"1 dense_line_without_gutter_just_single_column_no_whitespace_gaps",  -- Section 2: single column
		"2 another_dense_line_no_gaps",
	}

	local header_lines = { [1] = true, [4] = true }
	local split_columns = column_split.calculate_split_columns_per_section(lines, header_lines, 100)

	-- Section 1 should be side-by-side
	assert_eq(split_columns[2] > 0, true, "Section 1 line 2 is side-by-side")
	assert_eq(split_columns[3] > 0, true, "Section 1 line 3 is side-by-side")

	-- Section 2 should be single column (no gutter detected)
	assert_eq(split_columns[5], 0, "Section 2 line 5 is single column")
	assert_eq(split_columns[6], 0, "Section 2 line 6 is single column")
end

--- Test 5: Handle empty/whitespace lines
function tests.test_empty_lines()
	local lines = {
		"file.lua --- 1/1 --- Lua",
		" 1 test                                 1 test",
		"                                        ",  -- Empty/whitespace line
		" 3 foo                                  3 bar",
	}

	local header_lines = { [1] = true }
	local split_columns = column_split.calculate_split_columns_per_section(lines, header_lines, 100)

	local left_lines, right_lines = column_split.split_lines(lines, split_columns, header_lines)

	assert_eq(#left_lines, 4, "Handles empty lines")
	assert_eq(#right_lines, 4, "Handles empty lines")
end

--- Test 6: Split with trim info
function tests.test_trim_info()
	local lines = {
		"file.lua --- 1/1 --- Lua",
		" 1 left                                 1 right",
	}

	local header_lines = { [1] = true }
	local split_columns = column_split.calculate_split_columns_per_section(lines, header_lines, 100)

	local left_lines, right_lines, trim_info = column_split.split_lines(lines, split_columns, header_lines)

	-- Check trim info is returned
	assert_eq(type(trim_info), "table", "Returns trim info")
	assert_eq(type(trim_info[2]), "table", "Line 2 has trim info")
	assert_eq(type(trim_info[2].left_trim), "number", "Has left_trim")
	assert_eq(type(trim_info[2].right_trim), "number", "Has right_trim")
end

-- Run all tests
print("\n=== Running Column Split Tests (New Per-Section Algorithm) ===\n")

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
