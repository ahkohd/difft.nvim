-- luacheck: globals vim

--- Tests for navigation.lua (section jumping and cursor management)

-- Setup package path
local script_dir = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h")
local repo_root = vim.fn.fnamemodify(script_dir, ":h:h")  -- Go up two levels: tests/lib -> tests -> root
package.path = package.path
	.. ";" .. repo_root .. "/lua/?.lua"
	.. ";" .. repo_root .. "/lua/?/init.lua"

local navigation = require("difft.lib.navigation")

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

--- Create a test buffer with content in a window
local function create_test_window(lines)
	local buf = vim.api.nvim_create_buf(false, true)  -- unlisted, scratch
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	-- Create a window for the buffer
	vim.cmd("split")
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)

	return buf, win
end

--- Close window and delete buffer
local function cleanup(win, buf)
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, true)
	end
	if buf and vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_delete(buf, {force = true})
	end
end

--- Test 1: Setup navigation with headers
function tests.test_setup_navigation()
	local lines = {
		"file1.lua --- 1/2 --- Lua",
		"content line 1",
		"content line 2",
		"file2.lua --- 2/2 --- Lua",
		"content line 3",
	}

	local buf, win = create_test_window(lines)

	local headers = {
		{line = 1, filename = "file1.lua"},
		{line = 4, filename = "file2.lua"},
	}

	navigation.setup(buf, {
		headers = headers,
		auto_jump = false,
	})

	local state = navigation.get_state(buf)
	assert_eq(state ~= nil, true, "Navigation state created")
	assert_eq(#state.headers, 2, "Headers stored")
	assert_eq(state.current, 0, "Current index starts at 0")

	cleanup(win, buf)
end

--- Test 2: Auto-jump to first change
function tests.test_auto_jump()
	local lines = {
		"file1.lua --- 1/2 --- Lua",
		"content line 1",
		"file2.lua --- 2/2 --- Lua",
		"content line 2",
	}

	local buf, win = create_test_window(lines)

	local headers = {
		{line = 1, filename = "file1.lua"},
		{line = 3, filename = "file2.lua"},
	}

	navigation.setup(buf, {
		headers = headers,
		auto_jump = true,
	})

	-- Wait for scheduled jump
	vim.wait(100)

	local cursor = vim.api.nvim_win_get_cursor(win)
	assert_eq(cursor[1], 1, "Auto-jumped to first header")

	cleanup(win, buf)
end

--- Test 3: Navigate to next change
function tests.test_next_change()
	local lines = {
		"file1.lua --- 1/3 --- Lua",
		"content line 1",
		"file2.lua --- 2/3 --- Lua",
		"content line 2",
		"file3.lua --- 3/3 --- Lua",
	}

	local buf, win = create_test_window(lines)

	local headers = {
		{line = 1, filename = "file1.lua"},
		{line = 3, filename = "file2.lua"},
		{line = 5, filename = "file3.lua"},
	}

	navigation.setup(buf, {
		headers = headers,
		auto_jump = true,
		keymaps = {next = "n", prev = "p", first = "gg", last = "G"},
	})

	vim.wait(100)

	-- Press 'n' to go to next (should go to line 3)
	vim.api.nvim_feedkeys("n", "x", false)
	vim.wait(50)

	local cursor = vim.api.nvim_win_get_cursor(win)
	assert_eq(cursor[1], 3, "Navigated to second header")

	-- Press 'n' again (should go to line 5)
	vim.api.nvim_feedkeys("n", "x", false)
	vim.wait(50)

	cursor = vim.api.nvim_win_get_cursor(win)
	assert_eq(cursor[1], 5, "Navigated to third header")

	-- Press 'n' again (should wrap to line 1)
	vim.api.nvim_feedkeys("n", "x", false)
	vim.wait(50)

	cursor = vim.api.nvim_win_get_cursor(win)
	assert_eq(cursor[1], 1, "Wrapped to first header")

	cleanup(win, buf)
end

--- Test 4: Navigate to previous change
function tests.test_prev_change()
	local lines = {
		"file1.lua --- 1/3 --- Lua",
		"content line 1",
		"file2.lua --- 2/3 --- Lua",
		"content line 2",
		"file3.lua --- 3/3 --- Lua",
	}

	local buf, win = create_test_window(lines)

	local headers = {
		{line = 1, filename = "file1.lua"},
		{line = 3, filename = "file2.lua"},
		{line = 5, filename = "file3.lua"},
	}

	navigation.setup(buf, {
		headers = headers,
		auto_jump = true,
		keymaps = {next = "n", prev = "p", first = "gg", last = "G"},
	})

	vim.wait(100)

	-- Press 'p' to go to previous (should wrap to line 5)
	vim.api.nvim_feedkeys("p", "x", false)
	vim.wait(50)

	local cursor = vim.api.nvim_win_get_cursor(win)
	assert_eq(cursor[1], 5, "Wrapped to last header")

	-- Press 'p' again (should go to line 3)
	vim.api.nvim_feedkeys("p", "x", false)
	vim.wait(50)

	cursor = vim.api.nvim_win_get_cursor(win)
	assert_eq(cursor[1], 3, "Navigated to second header")

	cleanup(win, buf)
end

--- Test 5: Navigate to first change
function tests.test_first_change()
	local lines = {
		"file1.lua --- 1/2 --- Lua",
		"content line 1",
		"file2.lua --- 2/2 --- Lua",
	}

	local buf, win = create_test_window(lines)

	local headers = {
		{line = 1, filename = "file1.lua"},
		{line = 3, filename = "file2.lua"},
	}

	navigation.setup(buf, {
		headers = headers,
		auto_jump = false,
		keymaps = {next = "n", prev = "p", first = "gg", last = "G"},
	})

	-- Manually move to line 3
	vim.api.nvim_win_set_cursor(win, {3, 0})

	-- Press 'gg' to go to first
	vim.api.nvim_feedkeys("gg", "x", false)
	vim.wait(50)

	local cursor = vim.api.nvim_win_get_cursor(win)
	assert_eq(cursor[1], 1, "Navigated to first header")

	cleanup(win, buf)
end

--- Test 6: Navigate to last change
function tests.test_last_change()
	local lines = {
		"file1.lua --- 1/2 --- Lua",
		"content line 1",
		"file2.lua --- 2/2 --- Lua",
	}

	local buf, win = create_test_window(lines)

	local headers = {
		{line = 1, filename = "file1.lua"},
		{line = 3, filename = "file2.lua"},
	}

	navigation.setup(buf, {
		headers = headers,
		auto_jump = true,
		keymaps = {next = "n", prev = "p", first = "gg", last = "G"},
	})

	vim.wait(100)

	-- Press 'G' to go to last
	vim.api.nvim_feedkeys("G", "x", false)
	vim.wait(50)

	local cursor = vim.api.nvim_win_get_cursor(win)
	assert_eq(cursor[1], 3, "Navigated to last header")

	cleanup(win, buf)
end

--- Test 7: Update current from cursor position
function tests.test_update_current_from_cursor()
	local lines = {
		"file1.lua --- 1/3 --- Lua",
		"content line 1",
		"file2.lua --- 2/3 --- Lua",
		"content line 2",
		"file3.lua --- 3/3 --- Lua",
	}

	local buf, win = create_test_window(lines)

	local headers = {
		{line = 1, filename = "file1.lua"},
		{line = 3, filename = "file2.lua"},
		{line = 5, filename = "file3.lua"},
	}

	navigation.setup(buf, {
		headers = headers,
		auto_jump = false,
	})

	-- Manually move cursor to line 4 (between file2 and file3)
	vim.api.nvim_win_set_cursor(win, {4, 0})

	-- Update navigation state based on cursor
	navigation.update_current_from_cursor(buf)

	local state = navigation.get_state(buf)
	assert_eq(state.current, 2, "Current updated to closest header (file2)")

	cleanup(win, buf)
end

--- Test 8: No headers (empty navigation)
function tests.test_no_headers()
	local lines = {
		"just some content",
		"no headers here",
	}

	local buf, win = create_test_window(lines)

	navigation.setup(buf, {
		headers = {},
		auto_jump = false,
	})

	local state = navigation.get_state(buf)
	assert_eq(#state.headers, 0, "No headers")

	-- Try to navigate (should do nothing)
	vim.api.nvim_feedkeys("n", "x", false)
	vim.wait(50)

	-- Cursor should stay at position 1
	local cursor = vim.api.nvim_win_get_cursor(win)
	assert_eq(cursor[1], 1, "Cursor unchanged with no headers")

	cleanup(win, buf)
end

--- Test 9: Get state returns correct data
function tests.test_get_state()
	local lines = {
		"file1.lua --- Lua",
		"content",
	}

	local buf, win = create_test_window(lines)

	local headers = {
		{line = 1, filename = "file1.lua"},
	}

	navigation.setup(buf, {
		headers = headers,
		auto_jump = false,
	})

	local state = navigation.get_state(buf)
	assert_eq(state ~= nil, true, "State exists")
	assert_eq(type(state.headers), "table", "State has headers")
	assert_eq(type(state.current), "number", "State has current index")
	assert_eq(type(state.goal_column), "number", "State has goal column")

	cleanup(win, buf)
end

--- Test 10: Navigate next from within header content
function tests.test_next_from_header_content()
	local lines = {
		"file1.lua --- 1/3 --- Lua",
		"content line 1",
		"content line 2",
		"file2.lua --- 2/3 --- Lua",
		"content line 3",
		"file3.lua --- 3/3 --- Lua",
	}

	local buf, win = create_test_window(lines)

	local headers = {
		{line = 1, filename = "file1.lua"},
		{line = 4, filename = "file2.lua"},
		{line = 6, filename = "file3.lua"},
	}

	navigation.setup(buf, {
		headers = headers,
		auto_jump = false,
		keymaps = {next = "n", prev = "p", first = "gg", last = "G"},
	})

	-- Move cursor to line 2 (within first header's content)
	vim.api.nvim_win_set_cursor(win, {2, 0})

	-- Press 'n' to go to next (should go to line 4, NOT line 1)
	vim.api.nvim_feedkeys("n", "x", false)
	vim.wait(50)

	local cursor = vim.api.nvim_win_get_cursor(win)
	assert_eq(cursor[1], 4, "Navigated to second header from first header's content")

	-- Now from line 5 (within second header's content), press 'n'
	vim.api.nvim_win_set_cursor(win, {5, 0})
	vim.api.nvim_feedkeys("n", "x", false)
	vim.wait(50)

	cursor = vim.api.nvim_win_get_cursor(win)
	assert_eq(cursor[1], 6, "Navigated to third header from second header's content")

	cleanup(win, buf)
end

--- Test 11: Navigate previous from within header content
function tests.test_prev_from_header_content()
	local lines = {
		"file1.lua --- 1/3 --- Lua",
		"content line 1",
		"file2.lua --- 2/3 --- Lua",
		"content line 2",
		"file3.lua --- 3/3 --- Lua",
		"content line 3",
	}

	local buf, win = create_test_window(lines)

	local headers = {
		{line = 1, filename = "file1.lua"},
		{line = 3, filename = "file2.lua"},
		{line = 5, filename = "file3.lua"},
	}

	navigation.setup(buf, {
		headers = headers,
		auto_jump = false,
		keymaps = {next = "n", prev = "p", first = "gg", last = "G"},
	})

	-- Move cursor to line 4 (within second header's content)
	vim.api.nvim_win_set_cursor(win, {4, 0})

	-- Press 'p' to go to previous (should go to line 1)
	vim.api.nvim_feedkeys("p", "x", false)
	vim.wait(50)

	local cursor = vim.api.nvim_win_get_cursor(win)
	assert_eq(cursor[1], 1, "Navigated to first header from second header's content")

	cleanup(win, buf)
end

-- Run all tests
print("\n=== Running Navigation Tests ===\n")

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
