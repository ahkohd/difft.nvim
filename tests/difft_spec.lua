-- luacheck: globals vim

local test = require("dev.difft.tests.test_runner")
local describe = test.describe
local it = test.it
local assert = test.assert
local before_each = test.before_each
local after_each = test.after_each

local difft = require("difft")

describe("difft.nvim", function()
	describe("parse_changes", function()
		local parse_changes = difft._test.parse_changes

		it("should parse valid header with step info", function()
			local lines = {
				"lua/plugins/diff.lua --- 1/10 --- Lua",
			}

			local changes = parse_changes(lines)

			assert.are.equal(1, #changes)
			assert.are.equal(1, changes[1].line)
			assert.are.equal("lua/plugins/diff.lua", changes[1].filename)
			assert.are.equal("Lua", changes[1].language)
			assert.is_not_nil(changes[1].step)
			assert.are.equal(1, changes[1].step.current)
			assert.are.equal(10, changes[1].step.of)
		end)

		it("should parse valid header without step info", function()
			local lines = {
				"src/app.ts --- TypeScript",
			}

			local changes = parse_changes(lines)

			assert.are.equal(1, #changes)
			assert.are.equal(1, changes[1].line)
			assert.are.equal("src/app.ts", changes[1].filename)
			assert.are.equal("TypeScript", changes[1].language)
			assert.is_nil(changes[1].step)
		end)

		it("should parse header with multi-word language", function()
			local lines = {
				"components/Button.tsx --- 2/5 --- TypeScript TSX",
			}

			local changes = parse_changes(lines)

			assert.are.equal(1, #changes)
			assert.are.equal("components/Button.tsx", changes[1].filename)
			assert.are.equal("TypeScript TSX", changes[1].language)
			assert.are.equal(2, changes[1].step.current)
			assert.are.equal(5, changes[1].step.of)
		end)

		it("should parse multiple headers", function()
			local lines = {
				"file1.lua --- 1/3 --- Lua",
				"some code here",
				"file2.ts --- 2/3 --- TypeScript",
				"more code",
				"file3.py --- 3/3 --- Python",
			}

			local changes = parse_changes(lines)

			assert.are.equal(3, #changes)
			assert.are.equal(1, changes[1].line)
			assert.are.equal("file1.lua", changes[1].filename)
			assert.are.equal(3, changes[2].line)
			assert.are.equal("file2.ts", changes[2].filename)
			assert.are.equal(5, changes[3].line)
			assert.are.equal("file3.py", changes[3].filename)
		end)

		it("should reject plain numbers as headers", function()
			local lines = {
				"1049",
				"1050",
				"100",
			}

			local changes = parse_changes(lines)

			assert.are.equal(0, #changes)
		end)

		it("should reject lines with only digits as language", function()
			local lines = {
				"file.txt --- 1/2 --- 123",
				"path/file.lua --- 456",
			}

			local changes = parse_changes(lines)

			assert.are.equal(0, #changes)
		end)

		it("should reject filenames without path separator or extension", function()
			local lines = {
				"filename --- Lua",
				"another --- 1/2 --- Python",
			}

			local changes = parse_changes(lines)

			assert.are.equal(0, #changes)
		end)

		it("should accept filenames with underscores and dashes", function()
			local lines = {
				"my_file-name.lua --- Lua",
				"test_dir/my-component.tsx --- TypeScript TSX",
			}

			local changes = parse_changes(lines)

			assert.are.equal(2, #changes)
			assert.are.equal("my_file-name.lua", changes[1].filename)
			assert.are.equal("test_dir/my-component.tsx", changes[2].filename)
		end)

		it("should handle lines without --- separator", function()
			local lines = {
				"This is just text",
				"1000 more lines",
				" 42 ",
			}

			local changes = parse_changes(lines)

			assert.are.equal(0, #changes)
		end)

		it("should trim whitespace from filename and language", function()
			local lines = {
				"file.lua   ---   1/1   ---   Lua  ",
			}

			local changes = parse_changes(lines)

			assert.are.equal(1, #changes)
			assert.are.equal("file.lua", changes[1].filename)
			assert.are.equal("Lua", changes[1].language)
		end)

		it("should handle nested paths", function()
			local lines = {
				"apps/desktop/src/features/auth/login.ts --- TypeScript",
			}

			local changes = parse_changes(lines)

			assert.are.equal(1, #changes)
			assert.are.equal("apps/desktop/src/features/auth/login.ts", changes[1].filename)
		end)

		it("should handle empty input", function()
			local lines = {}

			local changes = parse_changes(lines)

			assert.are.equal(0, #changes)
		end)

		it("should parse header with language containing special characters", function()
			local lines = {
				"Makefile --- 1/1 --- GNU Make",
			}

			local changes = parse_changes(lines)

			assert.are.equal(1, #changes)
			assert.are.equal("GNU Make", changes[1].language)
		end)
	end)

	describe("parse_first_line_number", function()
		local parse_first_line_number = difft._test.parse_first_line_number
		local state = difft._test.state
		local config = difft._test.config

		local test_buf

		before_each(function()
			-- Create a test buffer
			test_buf = vim.api.nvim_create_buf(false, true)

			-- Ensure jump is enabled
			config.jump.enabled = true
		end)

		after_each(function()
			-- Clean up buffer
			if test_buf and vim.api.nvim_buf_is_valid(test_buf) then
				vim.api.nvim_buf_delete(test_buf, { force = true })
			end
		end)

		it("should return nil when jump is disabled", function()
			config.jump.enabled = false

			local result = parse_first_line_number(test_buf, 1)

			assert.is_nil(result)
		end)

		it("should extract line number with leading whitespace", function()
			-- Set up buffer with difftastic format
			local lines = {
				"header line",
				" 6     import { useState } from 'react';",
			}
			vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, lines)

			-- Add DiffAdd highlight to line 2 (index 1)
			vim.api.nvim_buf_set_extmark(test_buf, state.ns, 1, 0, {
				end_col = #lines[2],
				hl_group = "DiffAdd",
			})

			local result = parse_first_line_number(test_buf, 2)

			assert.are.equal(6, result)
		end)

		it("should extract multi-digit line numbers", function()
			local lines = {
				"header line",
				" 1234     function doSomething() {",
			}
			vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, lines)

			vim.api.nvim_buf_set_extmark(test_buf, state.ns, 1, 0, {
				end_col = #lines[2],
				hl_group = "DiffAdd",
			})

			local result = parse_first_line_number(test_buf, 2)

			assert.are.equal(1234, result)
		end)

		it("should detect DiffDelete highlighted lines", function()
			local lines = {
				"header",
				" 33     const oldCode = true;",
			}
			vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, lines)

			vim.api.nvim_buf_set_extmark(test_buf, state.ns, 1, 0, {
				end_col = #lines[2],
				hl_group = "DiffDelete",
			})

			local result = parse_first_line_number(test_buf, 2)

			assert.are.equal(33, result)
		end)

		it("should detect formatted diff highlights like DiffAdd_bold", function()
			local lines = {
				"header",
				" 99     const newCode = true;",
			}
			vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, lines)

			vim.api.nvim_buf_set_extmark(test_buf, state.ns, 1, 0, {
				end_col = #lines[2],
				hl_group = "DiffAdd_bold",
			})

			local result = parse_first_line_number(test_buf, 2)

			assert.are.equal(99, result)
		end)

		it("should return nil when no highlighted line is found", function()
			local lines = {
				"header",
				"plain text without highlights",
				"more plain text",
			}
			vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, lines)

			local result = parse_first_line_number(test_buf, 2)

			assert.is_nil(result)
		end)

		it("should scan forward from start_line", function()
			local lines = {
				"header",
				"plain line 1",
				"plain line 2",
				" 42     highlighted line",
			}
			vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, lines)

			vim.api.nvim_buf_set_extmark(test_buf, state.ns, 3, 0, {
				end_col = #lines[4],
				hl_group = "DiffAdd",
			})

			-- Start scanning from line 2
			local result = parse_first_line_number(test_buf, 2)

			assert.are.equal(42, result)
		end)

		it("should return first highlighted line when multiple exist", function()
			local lines = {
				"header",
				" 10     first change",
				" 20     second change",
				" 30     third change",
			}
			vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, lines)

			-- Highlight all three
			for i = 1, 3 do
				vim.api.nvim_buf_set_extmark(test_buf, state.ns, i, 0, {
					end_col = #lines[i + 1],
					hl_group = "DiffAdd",
				})
			end

			local result = parse_first_line_number(test_buf, 2)

			assert.are.equal(10, result)
		end)

		it("should return nil for lines without valid line number format", function()
			local lines = {
				"header",
				"not a difftastic line",
			}
			vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, lines)

			vim.api.nvim_buf_set_extmark(test_buf, state.ns, 1, 0, {
				end_col = #lines[2],
				hl_group = "DiffAdd",
			})

			local result = parse_first_line_number(test_buf, 2)

			assert.is_nil(result)
		end)

		it("should respect max_lines scan limit of 50 lines", function()
			local lines = { "header" }

			-- Add 51 plain lines
			for i = 1, 51 do
				table.insert(lines, "plain line " .. i)
			end

			-- Add highlighted line after 51 lines
			table.insert(lines, " 999     too far away")

			vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, lines)

			-- Highlight the line beyond scan limit
			vim.api.nvim_buf_set_extmark(test_buf, state.ns, 52, 0, {
				end_col = #lines[53],
				hl_group = "DiffAdd",
			})

			-- Start from line 2, should not find line at position 53 (52nd line away)
			local result = parse_first_line_number(test_buf, 2)

			assert.is_nil(result)
		end)

		it("should handle line numbers with no leading whitespace", function()
			local lines = {
				"header",
				"6     import statement",
			}
			vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, lines)

			vim.api.nvim_buf_set_extmark(test_buf, state.ns, 1, 0, {
				end_col = #lines[2],
				hl_group = "DiffAdd",
			})

			local result = parse_first_line_number(test_buf, 2)

			assert.are.equal(6, result)
		end)
	end)

	describe("extract_line_number", function()
		local extract_line_number = difft._test.extract_line_number

		-- Single number format tests
		it("should extract single line number with leading whitespace", function()
			local line_text = " 6     import { useState } from 'react';"
			local result = extract_line_number(line_text)
			assert.are.equal(6, result)
		end)

		it("should extract multi-digit line numbers", function()
			local line_text = " 1234     function doSomething() {"
			local result = extract_line_number(line_text)
			assert.are.equal(1234, result)
		end)

		it("should extract line number without leading whitespace", function()
			local line_text = "3 import { useCallback, useEffect, useState } from 'react';"
			local result = extract_line_number(line_text)
			assert.are.equal(3, result)
		end)

		it("should handle line numbers at start of line", function()
			local line_text = "42 const value = true;"
			local result = extract_line_number(line_text)
			assert.are.equal(42, result)
		end)

		-- Side-by-side format tests (prefer second/right number)
		it("should prefer second number in side-by-side format at line start", function()
			local line_text = "580 642"
			local result = extract_line_number(line_text)
			assert.are.equal(642, result)
		end)

		it("should prefer second number in side-by-side format with content", function()
			local line_text = "580 642     -- Check if current line is a header"
			local result = extract_line_number(line_text)
			assert.are.equal(642, result)
		end)

		it("should prefer second number with leading whitespace", function()
			local line_text = "  581 643     local header_info = nil"
			local result = extract_line_number(line_text)
			assert.are.equal(643, result)
		end)

		it("should handle multi-digit side-by-side numbers", function()
			local line_text = "1234 5678 some content"
			local result = extract_line_number(line_text)
			assert.are.equal(5678, result)
		end)

		it("should prefer right line number (1277) over left line number (1249)", function()
			-- Real example: when cursor is on line showing "1249 1277", jump to 1277 not 1249
			local line_text = "1249 1277             -- Only resize if diff is visible"
			local result = extract_line_number(line_text)
			assert.are.equal(1277, result)
		end)

		it("should always prefer new/right line in side-by-side diff", function()
			-- The second number represents the new file's line number (right side)
			local line_text = "100 200     if state.is_floating and M.is_visible() then"
			local result = extract_line_number(line_text)
			assert.are.equal(200, result)
		end)

		it("should prefer right number even when left is larger", function()
			-- In case of deletions, left might be larger than right
			local line_text = "500 300     -- some deleted content"
			local result = extract_line_number(line_text)
			assert.are.equal(300, result)
		end)

		it("should handle side-by-side with tabs between numbers", function()
			local line_text = "42\t84 content here"
			local result = extract_line_number(line_text)
			assert.are.equal(84, result)
		end)

		it("should handle side-by-side with multiple spaces between numbers", function()
			local line_text = "123    456     code content"
			local result = extract_line_number(line_text)
			assert.are.equal(456, result)
		end)

		-- Single dot tests (context lines)
		it("should extract number from single dot format", function()
			local line_text = ". 10"
			local result = extract_line_number(line_text)
			assert.are.equal(10, result)
		end)

		it("should extract multi-digit number from single dot format", function()
			local line_text = ". 123"
			local result = extract_line_number(line_text)
			assert.are.equal(123, result)
		end)

		it("should extract number from single dot with leading whitespace", function()
			local line_text = "   . 42"
			local result = extract_line_number(line_text)
			assert.are.equal(42, result)
		end)

		it("should extract number from single dot with content after", function()
			local line_text = ". 10     const value = true;"
			local result = extract_line_number(line_text)
			assert.are.equal(10, result)
		end)

		it("should return nil for pure single dot without number", function()
			local line_text = "."
			local result = extract_line_number(line_text)
			assert.is_nil(result)
		end)

		it("should return nil for pure single dot with whitespace", function()
			local line_text = "   .   "
			local result = extract_line_number(line_text)
			assert.is_nil(result)
		end)

		-- Ellipsis tests (dots correlate to digit count)
		it("should return nil for pure ellipsis lines (2 dots)", function()
			local line_text = ".."
			local result = extract_line_number(line_text)
			assert.is_nil(result)
		end)

		it("should return nil for pure ellipsis lines (3 dots)", function()
			local line_text = "..."
			local result = extract_line_number(line_text)
			assert.is_nil(result)
		end)

		it("should return nil for pure ellipsis lines with whitespace", function()
			local line_text = "   ...."
			local result = extract_line_number(line_text)
			assert.is_nil(result)
		end)

		it("should extract 2-digit number from 2-dot ellipsis", function()
			local line_text = ".. 20"
			local result = extract_line_number(line_text)
			assert.are.equal(20, result)
		end)

		it("should extract 3-digit number from 3-dot ellipsis", function()
			local line_text = "... 645"
			local result = extract_line_number(line_text)
			assert.are.equal(645, result)
		end)

		it("should extract 4-digit number from 4-dot ellipsis", function()
			local line_text = ".... 2000"
			local result = extract_line_number(line_text)
			assert.are.equal(2000, result)
		end)

		it("should extract 5-digit number from 5-dot ellipsis", function()
			local line_text = "..... 10000"
			local result = extract_line_number(line_text)
			assert.are.equal(10000, result)
		end)

		it("should extract number from ellipsis with content", function()
			local line_text = "... 645     local line_num = nil"
			local result = extract_line_number(line_text)
			assert.are.equal(645, result)
		end)

		it("should extract number from ellipsis with whitespace prefix", function()
			local line_text = "   .. 99"
			local result = extract_line_number(line_text)
			assert.are.equal(99, result)
		end)

		-- Two-column format tests (cursor-aware)
		it("should extract left column number when cursor is in left half", function()
			-- Format: "1249 content     1277 content"
			local line_text = "1249 -- Only refresh if diff     1277 -- Only resize if diff"
			-- Cursor at column 10 (in left content)
			local result = extract_line_number(line_text, 10)
			assert.are.equal(1249, result)
		end)

		it("should extract right column number when cursor is in right half", function()
			-- Format: "1249 content     1277 content"
			local line_text = "1249 -- Only refresh if diff     1277 -- Only resize if diff"
			-- Cursor at column 40 (in right content after the spaces)
			local result = extract_line_number(line_text, 40)
			assert.are.equal(1277, result)
		end)

		it("should detect two-column with real diff example", function()
			local line_text = "1249                 -- Only refresh    1277             -- Only resize"
			-- Cursor in left column
			local result_left = extract_line_number(line_text, 10)
			assert.are.equal(1249, result_left)
			-- Cursor in right column
			local result_right = extract_line_number(line_text, 50)
			assert.are.equal(1277, result_right)
		end)

		it("should handle two-column with varying whitespace", function()
			local line_text = "100 if state.is_floating      200 if state.is_visible"
			-- Left column
			local result_left = extract_line_number(line_text, 5)
			assert.are.equal(100, result_left)
			-- Right column
			local result_right = extract_line_number(line_text, 35)
			assert.are.equal(200, result_right)
		end)

		it("should fallback to default when no cursor position given", function()
			-- Without cursor position, should use default behavior (prefer right in side-by-side)
			local line_text = "100 content    200 content"
			local result = extract_line_number(line_text, nil)
			-- Should still work, falling back to other patterns
			assert.is_not_nil(result)
		end)

		it("should handle boundary case at column divider", function()
			local line_text = "50 left content      100 right content"
			-- Cursor exactly at the start of right column spaces
			local result = extract_line_number(line_text, 20)
			-- Should prefer right since cursor >= right_col_start
			assert.are.equal(100, result)
		end)

		-- Edge cases
		it("should return nil for empty string", function()
			local result = extract_line_number("")
			assert.is_nil(result)
		end)

		it("should return nil for nil input", function()
			local result = extract_line_number(nil)
			assert.is_nil(result)
		end)

		it("should return nil for lines without numbers", function()
			local line_text = "This is just plain text"
			local result = extract_line_number(line_text)
			assert.is_nil(result)
		end)

		it("should return nil for lines with number not followed by whitespace", function()
			local line_text = "123abc def"
			local result = extract_line_number(line_text)
			assert.is_nil(result)
		end)
	end)

	describe("find_header_above", function()
		local find_header_above = difft._test.find_header_above
		local state = difft._test.state

		local function setup_test_changes()
			-- Mock state.changes with test data
			state.changes = {
				{ line = 5, filename = "file1.lua", language = "Lua" },
				{ line = 20, filename = "file2.ts", language = "TypeScript" },
				{ line = 40, filename = "file3.py", language = "Python" },
			}
		end

		local function clear_test_changes()
			state.changes = {}
		end

		before_each(function()
			setup_test_changes()
		end)

		after_each(function()
			clear_test_changes()
		end)

		it("should find header when current line is between first and second header", function()
			local result = find_header_above(15)
			assert.is_not_nil(result)
			assert.are.equal(5, result.line)
			assert.are.equal("file1.lua", result.filename)
		end)

		it("should find header when current line is between second and third header", function()
			local result = find_header_above(30)
			assert.is_not_nil(result)
			assert.are.equal(20, result.line)
			assert.are.equal("file2.ts", result.filename)
		end)

		it("should find last header when current line is after all headers", function()
			local result = find_header_above(100)
			assert.is_not_nil(result)
			assert.are.equal(40, result.line)
			assert.are.equal("file3.py", result.filename)
		end)

		it("should return nil when current line is before first header", function()
			local result = find_header_above(3)
			assert.is_nil(result)
		end)

		it("should return nil when current line is on first header", function()
			local result = find_header_above(5)
			assert.is_nil(result)
		end)

		it("should find previous header when current line is on second header", function()
			local result = find_header_above(20)
			assert.is_not_nil(result)
			assert.are.equal(5, result.line)
			assert.are.equal("file1.lua", result.filename)
		end)

		it("should return nil when no changes exist", function()
			state.changes = {}
			local result = find_header_above(50)
			assert.is_nil(result)
		end)

		it("should find nearest header when line is immediately after header", function()
			local result = find_header_above(6)
			assert.is_not_nil(result)
			assert.are.equal(5, result.line)
		end)

		it("should find nearest header when line is immediately before next header", function()
			local result = find_header_above(19)
			assert.is_not_nil(result)
			assert.are.equal(5, result.line)
		end)
	end)
end)

test.run()
