# Difft Tests

This directory contains tests for the `difft.nvim` plugin.

## Running Tests

These tests use a simple lightweight test runner (no external dependencies required).

### Running All Tests

From the shell:

```bash
# Run all lib tests
for f in tests/lib/test_*.lua; do nvim -l "$f"; done
```

### Running Individual Tests

```bash
# Run specific test file
nvim -l tests/lib/test_parser.lua
nvim -l tests/lib/test_file_jump.lua
```

## Test Structure

Tests use a simple table-based structure:

```lua
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

--- Test 1: Description
function tests.test_something()
  local result = my_function()
  assert_eq(result, expected, "Test description")
end

-- Run all tests
for name, test_fn in pairs(tests) do
  local ok, err = pcall(test_fn)
  if not ok then
    failed = failed + 1
    print("✗ " .. name .. " (error)")
    print("  " .. tostring(err))
  end
end

if failed == 0 then
  print("\n✓ All tests passed!")
  os.exit(0)
else
  print("\n✗ Some tests failed")
  os.exit(1)
end
```

## Adding New Tests

1. Create or update test files in `tests/lib/` directory
2. Use the simple test structure above
3. Use descriptive test function names: `function tests.test_descriptive_name()`
4. Test both happy paths and edge cases
5. Clean up resources (buffers, windows) when needed
6. Run all tests in a `for` loop at the end

## Continuous Testing

You can watch files and auto-run tests using a file watcher:

```bash
# Using entr - run all lib tests
find lua tests/lib -name '*.lua' | entr -c sh -c 'for f in tests/lib/test_*.lua; do nvim -l "$f" || exit 1; done'
```
