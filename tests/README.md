# Difft Tests

This directory contains tests for the `difft.nvim` plugin.

## Running Tests

These tests use a custom lightweight test runner (no external dependencies required).

### Running All Tests

From the shell:

```bash
nvim -l tests/run.lua
```

## Test Structure

Tests are organized using a BDD-style syntax with a custom test runner:

```lua
local test = require("dev.difft.tests.test_runner")
local describe = test.describe
local it = test.it
local assert = test.assert
local before_each = test.before_each
local after_each = test.after_each

describe("component", function()
  describe("function_name", function()
    it("should do something", function()
      -- test code
      assert.are.equal(expected, actual)
    end)
  end)
end)

test.run()  -- Don't forget to call this at the end
```

## Adding New Tests

1. Create or update test files in `tests/` directory
2. Import and use the custom test runner
3. Use descriptive test names with "should" statements
4. Test both happy paths and edge cases
5. Clean up resources in `after_each` hooks when needed
6. Call `test.run()` at the end of the file

## Continuous Testing

You can watch files and auto-run tests using a file watcher:

```bash
# Using entr
ls **/*.lua | entr nvim -l tests/run.lua
```
