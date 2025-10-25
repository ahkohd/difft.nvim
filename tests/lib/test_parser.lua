-- luacheck: globals vim

--- Tests for parser.lua (ANSI parsing and header detection)

-- Setup package path
local script_dir = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h")
local repo_root = vim.fn.fnamemodify(script_dir, ":h:h")  -- Go up two levels: tests/lib -> tests -> root
package.path = package.path
	.. ";" .. repo_root .. "/lua/?.lua"
	.. ";" .. repo_root .. "/lua/?/init.lua"

local parser = require("difft.lib.parser")

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

--- Test helper for deep table comparison
local function assert_deep_eq(actual, expected, test_name)
	local function tables_equal(t1, t2)
		if type(t1) ~= "table" or type(t2) ~= "table" then
			return t1 == t2
		end
		for k, v in pairs(t1) do
			if not tables_equal(v, t2[k]) then
				return false
			end
		end
		for k, v in pairs(t2) do
			if not tables_equal(v, t1[k]) then
				return false
			end
		end
		return true
	end

	if tables_equal(actual, expected) then
		passed = passed + 1
		print("✓ " .. test_name)
		return true
	else
		failed = failed + 1
		print("✗ " .. test_name)
		print("  Expected: " .. vim.inspect(expected))
		print("  Got:      " .. vim.inspect(actual))
		return false
	end
end

-- Initialize parser with mock config
parser.init_ansi_mapping({
	diff = {
		highlights = {
			add = "DiffAdd",
			delete = "DiffDelete",
			change = "DiffChange",
			info = "DiffText",
			hint = "Comment",
			dim = "Comment",
		}
	}
})

--- Test 1: Parse plain text (no ANSI codes)
function tests.test_parse_plain_text()
	local line = "plain text without any colors"
	local text, highlights = parser.parse_ansi_line(line)

	assert_eq(text, "plain text without any colors", "Plain text unchanged")
	assert_eq(#highlights, 0, "No highlights for plain text")
end

--- Test 2: Parse simple colored text (red)
function tests.test_parse_simple_color()
	-- Red text: ESC[31m + "error" + ESC[0m (reset)
	local line = "\27[31merror\27[0m"
	local text, highlights = parser.parse_ansi_line(line)

	assert_eq(text, "error", "ANSI codes stripped")
	assert_eq(#highlights, 1, "One highlight region")
	assert_eq(highlights[1].col, 0, "Highlight starts at column 0")
	assert_eq(highlights[1].length, 5, "Highlight length is 5")
	assert_eq(highlights[1].hl_group, "DiffDelete", "Red maps to DiffDelete")
end

--- Test 3: Parse multiple colors in one line
function tests.test_parse_multiple_colors()
	-- Green "added" + space + red "removed"
	local line = "\27[32madded\27[0m \27[31mremoved\27[0m"
	local text, highlights = parser.parse_ansi_line(line)

	assert_eq(text, "added removed", "Text is concatenated correctly")
	assert_eq(#highlights, 2, "Two highlight regions")

	-- First highlight (green)
	assert_eq(highlights[1].col, 0, "First highlight at col 0")
	assert_eq(highlights[1].length, 5, "First highlight length 5")
	assert_eq(highlights[1].hl_group, "DiffAdd", "Green maps to DiffAdd")

	-- Second highlight (red)
	assert_eq(highlights[2].col, 6, "Second highlight at col 6 (after space)")
	assert_eq(highlights[2].length, 7, "Second highlight length 7")
	assert_eq(highlights[2].hl_group, "DiffDelete", "Red maps to DiffDelete")
end

--- Test 4: Parse bold text
function tests.test_parse_bold()
	-- Bold + red text
	local line = "\27[1;31mbold error\27[0m"
	local text, highlights = parser.parse_ansi_line(line)

	assert_eq(text, "bold error", "Text extracted")
	assert_eq(#highlights, 1, "One highlight")
	-- The highlight group should include "_bold" suffix
	local hl_has_bold = highlights[1].hl_group:find("bold") ~= nil
	assert_eq(hl_has_bold, true, "Highlight group includes bold formatting")
end

--- Test 5: Parse italic text
function tests.test_parse_italic()
	-- Italic + green text
	local line = "\27[3;32mitalic added\27[0m"
	local text, highlights = parser.parse_ansi_line(line)

	assert_eq(text, "italic added", "Text extracted")
	assert_eq(#highlights, 1, "One highlight")
	-- The highlight group should include "_italic" suffix
	local hl_has_italic = highlights[1].hl_group:find("italic") ~= nil
	assert_eq(hl_has_italic, true, "Highlight group includes italic formatting")
end

--- Test 6: Parse dim text
function tests.test_parse_dim()
	-- Dim text (code 2)
	local line = "\27[2mdim text\27[0m"
	local text, highlights = parser.parse_ansi_line(line)

	assert_eq(text, "dim text", "Text extracted")
	assert_eq(#highlights, 1, "One highlight")
	-- Dim should use Comment highlight with _dim suffix (formatting applied)
	assert_eq(highlights[1].hl_group, "Comment_dim", "Dim uses Comment_dim highlight")
end

--- Test 7: Parse with reset mid-line
function tests.test_parse_reset()
	-- Red text + reset + plain text
	local line = "\27[31mred\27[0m plain"
	local text, highlights = parser.parse_ansi_line(line)

	assert_eq(text, "red plain", "Text concatenated")
	assert_eq(#highlights, 1, "Only highlighted part counted")
	assert_eq(highlights[1].length, 3, "Only 'red' is highlighted")
end

--- Test 8: Parse headers with step info
function tests.test_parse_headers_with_step()
	local lines = {
		"src/main.lua --- 1/5 --- Lua",
		"some content",
		"tests/spec.lua --- 2/5 --- Lua",
	}

	local headers, header_set = parser.parse_headers(lines)

	assert_eq(#headers, 2, "Found 2 headers")
	assert_eq(headers[1].line, 1, "First header at line 1")
	assert_eq(headers[1].filename, "src/main.lua", "First filename correct")
	assert_eq(headers[1].language, "Lua", "First language correct")
	assert_eq(headers[1].step.current, 1, "First step current is 1")
	assert_eq(headers[1].step.of, 5, "First step of is 5")

	assert_eq(headers[2].line, 3, "Second header at line 3")
	assert_eq(headers[2].filename, "tests/spec.lua", "Second filename correct")

	assert_eq(header_set[1], true, "Line 1 in header set")
	assert_eq(header_set[2], nil, "Line 2 not in header set")
	assert_eq(header_set[3], true, "Line 3 in header set")
end

--- Test 9: Parse headers without step info
function tests.test_parse_headers_no_step()
	local lines = {
		"README.md --- Markdown",
		"config.json --- JSON",
	}

	local headers, header_set = parser.parse_headers(lines)

	assert_eq(#headers, 2, "Found 2 headers")
	assert_eq(headers[1].filename, "README.md", "First filename correct")
	assert_eq(headers[1].language, "Markdown", "First language correct")
	assert_eq(headers[1].step, nil, "No step info")

	assert_eq(headers[2].filename, "config.json", "Second filename correct")
	assert_eq(headers[2].language, "JSON", "Second language correct")
end

--- Test 10: Ignore lines that aren't headers
function tests.test_parse_non_headers()
	local lines = {
		"just some text",
		"actual_file.lua --- 1/2 --- Lua",
		"--- just dashes",
	}

	local headers, header_set = parser.parse_headers(lines)

	assert_eq(#headers, 1, "Found only 1 header")
	assert_eq(headers[1].line, 2, "Header at line 2")
	assert_eq(headers[1].filename, "actual_file.lua", "Correct filename")
end

--- Test 41: Header with multi-word language
function tests.test_header_multiword_language()
	local lines = {
		"components/Button.tsx --- 2/5 --- TypeScript TSX",
	}
	local headers = parser.parse_headers(lines)
	assert_eq(headers[1].language, "TypeScript TSX", "Multi-word language")
end

--- Test 42: Reject plain numbers as headers
function tests.test_reject_plain_numbers()
	local lines = {
		"1049",
		"1050",
		"100",
	}
	local headers = parser.parse_headers(lines)
	assert_eq(#headers, 0, "Plain numbers rejected")
end

--- Test 43: Reject lines with only digits as language
function tests.test_reject_digit_language()
	local lines = {
		"file.txt --- 1/2 --- 123",
		"path/file.lua --- 456",
	}
	local headers = parser.parse_headers(lines)
	assert_eq(#headers, 0, "Digit-only language rejected")
end

--- Test 44: Reject filenames without path separator or extension
function tests.test_reject_invalid_filename()
	local lines = {
		"filename --- Lua",
		"another --- 1/2 --- Python",
	}
	local headers = parser.parse_headers(lines)
	assert_eq(#headers, 0, "Invalid filenames rejected")
end

--- Test 45: Accept filenames with underscores and dashes
function tests.test_accept_underscores_dashes()
	local lines = {
		"my_file-name.lua --- Lua",
		"test_dir/my-component.tsx --- TypeScript TSX",
	}
	local headers = parser.parse_headers(lines)
	assert_eq(#headers, 2, "Underscore and dash filenames accepted")
	assert_eq(headers[1].filename, "my_file-name.lua", "First filename correct")
	assert_eq(headers[2].filename, "test_dir/my-component.tsx", "Second filename correct")
end

--- Test 46: Handle lines without --- separator
function tests.test_lines_without_separator()
	local lines = {
		"This is just text",
		"1000 more lines",
		" 42 ",
	}
	local headers = parser.parse_headers(lines)
	assert_eq(#headers, 0, "Lines without separator rejected")
end

--- Test 47: Trim whitespace from filename and language
function tests.test_trim_whitespace()
	local lines = {
		"file.lua   ---   1/1   ---   Lua  ",
	}
	local headers = parser.parse_headers(lines)
	assert_eq(headers[1].filename, "file.lua", "Filename trimmed")
	assert_eq(headers[1].language, "Lua", "Language trimmed")
end

--- Test 48: Handle nested paths
function tests.test_nested_paths()
	local lines = {
		"apps/desktop/src/features/auth/login.ts --- TypeScript",
	}
	local headers = parser.parse_headers(lines)
	assert_eq(headers[1].filename, "apps/desktop/src/features/auth/login.ts", "Nested path accepted")
end

--- Test 49: Header with language containing special characters
function tests.test_language_special_chars()
	local lines = {
		"Makefile --- 1/1 --- GNU Make",
	}
	local headers = parser.parse_headers(lines)
	assert_eq(headers[1].language, "GNU Make", "Language with special chars")
end

--- Test 50: Empty input
function tests.test_empty_input()
	local headers = parser.parse_headers({})
	assert_eq(#headers, 0, "Empty input returns no headers")
end

--- Test 11: Parse complex ANSI with combined codes
function tests.test_parse_combined_ansi()
	-- Bold + italic + red: ESC[1;3;31m
	local line = "\27[1;3;31mcombined\27[0m"
	local text, highlights = parser.parse_ansi_line(line)

	assert_eq(text, "combined", "Text extracted")
	assert_eq(#highlights, 1, "One highlight")
	-- Should have both bold and italic
	local hl_group = highlights[1].hl_group
	local has_bold = hl_group:find("bold") ~= nil
	local has_italic = hl_group:find("italic") ~= nil
	assert_eq(has_bold, true, "Has bold formatting")
	assert_eq(has_italic, true, "Has italic formatting")
end

--- Test 12: Parse empty line
function tests.test_parse_empty_line()
	local text, highlights = parser.parse_ansi_line("")

	assert_eq(text, "", "Empty text")
	assert_eq(#highlights, 0, "No highlights")
end

--- Test 13: Parse line with only ANSI codes (no visible text)
function tests.test_parse_ansi_only()
	local line = "\27[31m\27[0m"  -- Red color code + reset, but no text
	local text, highlights = parser.parse_ansi_line(line)

	assert_eq(text, "", "No visible text")
	assert_eq(#highlights, 0, "No highlights (no text to highlight)")
end

--- Test 14: All ANSI color codes - standard red (31)
function tests.test_ansi_standard_red()
	local line = "\27[31mdeleted\27[0m"
	local text, highlights = parser.parse_ansi_line(line)
	assert_eq(highlights[1].hl_group, "DiffDelete", "Red (31) maps to DiffDelete")
end

--- Test 15: All ANSI color codes - standard green (32)
function tests.test_ansi_standard_green()
	local line = "\27[32madded\27[0m"
	local text, highlights = parser.parse_ansi_line(line)
	assert_eq(highlights[1].hl_group, "DiffAdd", "Green (32) maps to DiffAdd")
end

--- Test 16: All ANSI color codes - yellow (33)
function tests.test_ansi_yellow()
	local line = "\27[33mchanged\27[0m"
	local text, highlights = parser.parse_ansi_line(line)
	assert_eq(highlights[1].hl_group, "DiffChange", "Yellow (33) maps to DiffChange")
end

--- Test 17: All ANSI color codes - bright yellow (93)
function tests.test_ansi_bright_yellow()
	local line = "\27[93mchanged\27[0m"
	local text, highlights = parser.parse_ansi_line(line)
	assert_eq(highlights[1].hl_group, "DiffChange", "Bright yellow (93) maps to DiffChange")
end

--- Test 18: All ANSI color codes - blue (34)
function tests.test_ansi_blue()
	local line = "\27[34minfo\27[0m"
	local text, highlights = parser.parse_ansi_line(line)
	assert_eq(highlights[1].hl_group, "DiffText", "Blue (34) maps to DiffText")
end

--- Test 19: All ANSI color codes - cyan (36)
function tests.test_ansi_cyan()
	local line = "\27[36mcyan\27[0m"
	local text, highlights = parser.parse_ansi_line(line)
	assert_eq(highlights[1].hl_group, "DiffText", "Cyan (36) maps to DiffText")
end

--- Test 20: All ANSI color codes - magenta (35)
function tests.test_ansi_magenta()
	local line = "\27[35mhint\27[0m"
	local text, highlights = parser.parse_ansi_line(line)
	assert_eq(highlights[1].hl_group, "Comment", "Magenta (35) maps to Comment")
end

--- Test 21: All ANSI color codes - bright magenta (95)
function tests.test_ansi_bright_magenta()
	local line = "\27[95mhint\27[0m"
	local text, highlights = parser.parse_ansi_line(line)
	assert_eq(highlights[1].hl_group, "Comment", "Bright magenta (95) maps to Comment")
end

--- Test 22: All ANSI color codes - black (30)
function tests.test_ansi_black()
	local line = "\27[30mcomment\27[0m"
	local text, highlights = parser.parse_ansi_line(line)
	assert_eq(highlights[1].hl_group, "Comment", "Black (30) maps to Comment")
end

--- Test 23: All ANSI color codes - white (37)
function tests.test_ansi_white()
	local line = "\27[37mwhite\27[0m"
	local text, highlights = parser.parse_ansi_line(line)
	assert_eq(highlights[1].hl_group, "Comment", "White (37) maps to Comment")
end

--- Test 24: All ANSI color codes - bright gray (90)
function tests.test_ansi_bright_gray()
	local line = "\27[90mgray\27[0m"
	local text, highlights = parser.parse_ansi_line(line)
	assert_eq(highlights[1].hl_group, "Comment", "Bright gray (90) maps to Comment")
end

--- Test 25: All ANSI color codes - bright white (97)
function tests.test_ansi_bright_white()
	local line = "\27[97mbright\27[0m"
	local text, highlights = parser.parse_ansi_line(line)
	assert_eq(highlights[1].hl_group, "Comment", "Bright white (97) maps to Comment")
end

--- Test 26: Bright red (91)
function tests.test_ansi_bright_red()
	local line = "\27[91mdeleted\27[0m"
	local text, highlights = parser.parse_ansi_line(line)
	assert_eq(highlights[1].hl_group, "DiffDelete", "Bright red (91) maps to DiffDelete")
end

--- Test 27: Bright green (92)
function tests.test_ansi_bright_green()
	local line = "\27[92madded\27[0m"
	local text, highlights = parser.parse_ansi_line(line)
	assert_eq(highlights[1].hl_group, "DiffAdd", "Bright green (92) maps to DiffAdd")
end

--- Test 28: Dim with color after dim
function tests.test_dim_with_color_after()
	local line = "\27[2;32mdim green\27[0m"
	local text, highlights = parser.parse_ansi_line(line)
	assert_eq(highlights[1].hl_group, "DiffAdd_dim", "Dim with green after")
end

--- Test 29: Dim with color before dim
function tests.test_dim_with_color_before()
	local line = "\27[32;2mgreen dim\27[0m"
	local text, highlights = parser.parse_ansi_line(line)
	assert_eq(highlights[1].hl_group, "DiffAdd_dim", "Green with dim after")
end

--- Test 30: Bold + dim together
function tests.test_bold_dim()
	local line = "\27[1;2mbold dim\27[0m"
	local text, highlights = parser.parse_ansi_line(line)
	assert_eq(highlights[1].hl_group, "Comment_bold_dim", "Bold + dim")
end

--- Test 31: Bold + italic + dim together
function tests.test_bold_italic_dim()
	local line = "\27[32;1;2;3mformatted\27[0m"
	local text, highlights = parser.parse_ansi_line(line)
	assert_eq(highlights[1].hl_group, "DiffAdd_bold_italic_dim", "Bold + italic + dim")
end

--- Test 32: Consecutive ANSI codes with no text
function tests.test_consecutive_ansi_no_text()
	local line = "\27[32m\27[1m\27[0m"
	local text, highlights = parser.parse_ansi_line(line)
	assert_eq(text, "", "No text from consecutive codes")
	assert_eq(#highlights, 0, "No highlights for no text")
end

--- Test 33: Text before any ANSI codes
function tests.test_text_before_ansi()
	local line = "plain \27[92mgreen\27[0m"
	local text, highlights = parser.parse_ansi_line(line)
	assert_eq(text, "plain green", "Text concatenated correctly")
	assert_eq(#highlights, 1, "One highlight")
	assert_eq(highlights[1].col, 6, "Highlight starts after 'plain '")
	assert_eq(highlights[1].length, 5, "Highlight length is 5")
end

--- Test 34: Text after reset code
function tests.test_text_after_reset()
	local line = "\27[92mgreen\27[0m plain"
	local text, highlights = parser.parse_ansi_line(line)
	assert_eq(text, "green plain", "Text concatenated")
	assert_eq(#highlights, 1, "One highlight")
	assert_eq(highlights[1].length, 5, "Only 'green' highlighted")
end

--- Test 35: Multiple color changes
function tests.test_multiple_color_changes()
	local line = "\27[31mred\27[0m \27[32mgreen\27[0m \27[33myellow\27[0m"
	local text, highlights = parser.parse_ansi_line(line)
	assert_eq(text, "red green yellow", "All text present")
	assert_eq(#highlights, 3, "Three highlights")
	assert_eq(highlights[1].hl_group, "DiffDelete", "First is red")
	assert_eq(highlights[2].hl_group, "DiffAdd", "Second is green")
	assert_eq(highlights[3].hl_group, "DiffChange", "Third is yellow")
end

--- Test 36: Nested formatting changes
function tests.test_nested_formatting()
	local line = "\27[32mgreen \27[1mbold green\27[0m"
	local text, highlights = parser.parse_ansi_line(line)
	assert_eq(text, "green bold green", "Text correct")
	assert_eq(#highlights, 2, "Two highlights")
	assert_eq(highlights[1].hl_group, "DiffAdd", "First is plain green")
	assert_eq(highlights[2].hl_group, "DiffAdd_bold", "Second is bold green")
end

--- Test 37: Format reset mid-line then continue
function tests.test_format_reset_continue()
	local line = "\27[32;1mbold\27[0m normal \27[32;1mbold\27[0m"
	local text, highlights = parser.parse_ansi_line(line)
	assert_eq(text, "bold normal bold", "Text correct")
	assert_eq(#highlights, 2, "Two highlights")
	assert_eq(highlights[1].col, 0, "First at col 0")
	assert_eq(highlights[2].col, 12, "Second after 'bold normal '")
end

--- Test 38: Real-world complex diff line
function tests.test_real_world_complex()
	-- Real example with line number and mixed bold/normal
	local line = "\27[92;1m38 \27[0m\27[92;1mif\27[0m \27[92;1mnot\27[0m \27[92mvim\27[0m\27[92m.\27[0m\27[92mg\27[0m"
	local text, highlights = parser.parse_ansi_line(line)
	assert_eq(text, "38 if not vim.g", "Complex line parsed")
	assert_eq(#highlights, 6, "Six highlight segments")
	assert_eq(highlights[1].hl_group, "DiffAdd_bold", "Line number bold")
	assert_eq(highlights[2].hl_group, "DiffAdd_bold", "if bold")
	assert_eq(highlights[3].hl_group, "DiffAdd_bold", "not bold")
	assert_eq(highlights[4].hl_group, "DiffAdd", "vim not bold")
	assert_eq(highlights[5].hl_group, "DiffAdd", "dot not bold")
	assert_eq(highlights[6].hl_group, "DiffAdd", "g not bold")
end

--- Test 39: Ignore unknown ANSI codes
function tests.test_unknown_ansi()
	local line = "\27[999munknown\27[0m"
	local text, highlights = parser.parse_ansi_line(line)
	assert_eq(text, "unknown", "Text extracted")
	assert_eq(#highlights, 0, "Unknown code ignored")
end

--- Test 40: Malformed ANSI code at end
function tests.test_malformed_ansi()
	local line = "text\27[32"
	local text, highlights = parser.parse_ansi_line(line)
	assert_eq(text, "text\27[32", "Malformed code kept as-is")
	assert_eq(#highlights, 0, "No highlights for malformed")
end

--- Test 51: Filenames with spaces
function tests.test_filenames_with_spaces()
	local lines = {
		"ghostty/Library/Application Support/com.mitchellh.ghostty/colors --- Text",
		"path with spaces/file.lua --- 1/2 --- Lua",
	}
	local headers = parser.parse_headers(lines)
	assert_eq(#headers, 2, "Found 2 headers with spaces")
	assert_eq(headers[1].filename, "ghostty/Library/Application Support/com.mitchellh.ghostty/colors", "First filename with spaces correct")
	assert_eq(headers[1].language, "Text", "First language correct")
	assert_eq(headers[2].filename, "path with spaces/file.lua", "Second filename with spaces correct")
	assert_eq(headers[2].language, "Lua", "Second language correct")
	assert_eq(headers[2].step.current, 1, "Step info parsed correctly")
end

--- Test 52: Reject ellipsis and noise patterns
function tests.test_reject_ellipsis_patterns()
	local lines = {
		"... 366 --- 1/2 --- Text",
		"... --- Lua",
		".. 100 --- 1/1 --- Python",
		"... ... --- TypeScript",
	}
	local headers = parser.parse_headers(lines)
	assert_eq(#headers, 0, "Ellipsis patterns rejected as headers")
end

-- Run all tests
print("\n=== Running Parser Tests ===\n")

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
