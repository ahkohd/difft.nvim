-- luacheck: globals vim

--- Tests for buffer.lua (integration of parser, renderer, navigation)

-- Setup package path
local script_dir = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h")
local repo_root = vim.fn.fnamemodify(script_dir, ":h:h")  -- Go up two levels: tests/lib -> tests -> root
package.path = package.path
	.. ";" .. repo_root .. "/lua/?.lua"
	.. ";" .. repo_root .. "/lua/?/init.lua"

local buffer = require("difft.lib.buffer")
local parser = require("difft.lib.parser")
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

--- Create test buffer and config
local function create_test_setup()
	local buf = vim.api.nvim_create_buf(false, true)
	local ns = vim.api.nvim_create_namespace("test_buffer_" .. buf)

	-- Initialize parser with config
	local config = {
		diff = {
			highlights = {
				add = "DiffAdd",
				delete = "DiffDelete",
				change = "DiffChange",
				info = "DiffText",
				hint = "Comment",
				dim = "Comment",
			}
		},
		keymaps = {
			next = "n",
			prev = "p",
			first = "gg",
			last = "G",
		}
	}

	parser.init_ansi_mapping(config)

	return buf, ns, config
end

--- Cleanup
local function cleanup(buf)
	if buf and vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_delete(buf, {force = true})
	end
end

--- Test 1: Setup buffer with clean lines
function tests.test_setup_with_clean_lines()
	local buf, ns, config = create_test_setup()

	local lines = {
		"file1.lua --- 1/2 --- Lua",
		"content line 1",
		"file2.lua --- 2/2 --- Lua",
		"content line 2",
	}

	local highlights = {
		[2] = {{col = 0, length = 7, hl_group = "DiffAdd"}},
		[4] = {{col = 0, length = 7, hl_group = "DiffDelete"}},
	}

	local result = buffer.setup_difft_buffer(buf, {
		lines = lines,
		highlights = highlights,
		config = config,
		namespace = ns,
		navigation = {enabled = false}, -- Disable for this test
	})

	-- Check buffer content
	local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	assert_eq(#buf_lines, 4, "Buffer has 4 lines")
	assert_eq(buf_lines[1], "file1.lua --- 1/2 --- Lua", "Line 1 correct")

	-- Check headers were parsed
	assert_eq(result ~= nil, true, "Result returned")
	assert_eq(#result.headers, 2, "Found 2 headers")
	assert_eq(result.headers[1].filename, "file1.lua", "Header 1 filename correct")

	cleanup(buf)
end

--- Test 2: Setup from ANSI lines
function tests.test_setup_from_ansi_lines()
	local buf, ns, config = create_test_setup()

	-- Create a window for the buffer (needed for navigation)
	vim.cmd("split")
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)

	local raw_lines = {
		"file1.lua --- 1/1 --- Lua",
		"\27[32madded line\27[0m",  -- Green (added)
		"\27[31mremoved line\27[0m", -- Red (removed)
	}

	local result = buffer.setup_from_ansi_lines(buf, raw_lines, config, ns, {
		navigation = {enabled = false}, -- Disable for this test
	})

	-- Check ANSI codes were stripped
	local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	assert_eq(buf_lines[2], "added line", "ANSI codes stripped from line 2")
	assert_eq(buf_lines[3], "removed line", "ANSI codes stripped from line 3")

	-- Check headers
	assert_eq(#result.headers, 1, "Found 1 header")

	-- Cleanup window
	if vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, true)
	end
	cleanup(buf)
end

--- Test 3: Setup with navigation enabled
function tests.test_setup_with_navigation()
	local buf, ns, config = create_test_setup()

	-- Create a window for the buffer
	vim.cmd("split")
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)

	local lines = {
		"file1.lua --- 1/2 --- Lua",
		"content line 1",
		"file2.lua --- 2/2 --- Lua",
		"content line 2",
	}

	buffer.setup_difft_buffer(buf, {
		lines = lines,
		highlights = {},
		config = config,
		namespace = ns,
		navigation = {
			enabled = true,
			auto_jump = false,
		},
	})

	-- Check navigation was setup
	local nav_state = navigation.get_state(buf)
	assert_eq(nav_state ~= nil, true, "Navigation state exists")
	assert_eq(#nav_state.headers, 2, "Navigation has 2 headers")

	-- Cleanup window
	if vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, true)
	end
	cleanup(buf)
end

--- Test 4: Setup with custom headers disabled
function tests.test_setup_custom_headers_disabled()
	local buf, ns, config = create_test_setup()

	-- Add a custom header function that should NOT be called
	config.header = {
		content = function(filename, step, language)
			return "CUSTOM: " .. filename
		end
	}

	local lines = {
		"file1.lua --- Lua",
		"content",
	}

	buffer.setup_difft_buffer(buf, {
		lines = lines,
		highlights = {},
		config = config,
		namespace = ns,
		custom_headers = false, -- Disable custom headers
		navigation = false,
	})

	-- Header should NOT be modified
	local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	assert_eq(buf_lines[1], "file1.lua --- Lua", "Header unchanged (custom disabled)")

	cleanup(buf)
end

--- Test 5: Setup with custom headers enabled
function tests.test_setup_custom_headers_enabled()
	local buf, ns, config = create_test_setup()

	-- Add a custom header function
	config.header = {
		content = function(filename, step, language)
			return "📄 " .. filename
		end
	}

	local lines = {
		"file1.lua --- Lua",
		"content",
	}

	buffer.setup_difft_buffer(buf, {
		lines = lines,
		highlights = {},
		config = config,
		namespace = ns,
		custom_headers = true, -- Enable custom headers
		navigation = false,
	})

	-- Header should be modified
	local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	assert_eq(buf_lines[1], "📄 file1.lua", "Header modified by custom function")

	cleanup(buf)
end

--- Test 6: Highlights applied correctly
function tests.test_highlights_applied()
	local buf, ns, config = create_test_setup()

	local lines = {
		"file1.lua --- Lua",
		"added line",
	}

	local highlights = {
		[2] = {{col = 0, length = 10, hl_group = "DiffAdd"}},
	}

	buffer.setup_difft_buffer(buf, {
		lines = lines,
		highlights = highlights,
		config = config,
		namespace = ns,
		navigation = false,
	})

	-- Check extmarks were created
	local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
	assert_eq(#extmarks > 0, true, "Extmarks created for highlights")

	cleanup(buf)
end

--- Test 7: Empty lines handled
function tests.test_empty_lines()
	local buf, ns, config = create_test_setup()

	local lines = {
		"file1.lua --- Lua",
		"",
		"content",
	}

	buffer.setup_difft_buffer(buf, {
		lines = lines,
		highlights = {},
		config = config,
		namespace = ns,
		navigation = false,
	})

	local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	assert_eq(#buf_lines, 3, "All lines including empty preserved")
	assert_eq(buf_lines[2], "", "Empty line preserved")

	cleanup(buf)
end

--- Test 8: Invalid buffer handled
function tests.test_invalid_buffer()
	local ns = vim.api.nvim_create_namespace("test_invalid")
	local config = {}

	-- Use an invalid buffer number
	buffer.setup_difft_buffer(9999, {
		lines = {},
		highlights = {},
		config = config,
		namespace = ns,
	})

	-- Should not crash - just return early
	assert_eq(true, true, "Invalid buffer handled gracefully")
end

--- Test 9: Missing config handled
function tests.test_missing_config()
	local buf = vim.api.nvim_create_buf(false, true)
	local ns = vim.api.nvim_create_namespace("test_missing_config")

	-- Call without config
	buffer.setup_difft_buffer(buf, {
		lines = {},
		highlights = {},
		namespace = ns,
	})

	-- Should not crash
	assert_eq(true, true, "Missing config handled gracefully")

	cleanup(buf)
end

-- Run all tests
print("\n=== Running Buffer Integration Tests ===\n")

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
