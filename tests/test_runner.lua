-- Simple test runner without plenary
local M = {}

local tests = {}
local current_describe = nil
local before_each_fn = nil
local after_each_fn = nil

function M.describe(name, fn)
	local old_describe = current_describe
	local old_before_each = before_each_fn
	local old_after_each = after_each_fn

	current_describe = name
	before_each_fn = nil
	after_each_fn = nil

	fn()

	current_describe = old_describe
	before_each_fn = old_before_each
	after_each_fn = old_after_each
end

function M.it(name, fn)
	table.insert(tests, {
		describe = current_describe,
		name = name,
		fn = fn,
		before_each = before_each_fn,
		after_each = after_each_fn,
	})
end

function M.before_each(fn)
	before_each_fn = fn
end

function M.after_each(fn)
	after_each_fn = fn
end

-- Simple assertion library
M.assert = {
	are = {
		equal = function(expected, actual, message)
			if expected ~= actual then
				error(string.format(
					"Expected %s to equal %s%s",
					vim.inspect(actual),
					vim.inspect(expected),
					message and (" - " .. message) or ""
				))
			end
		end,
	},
	is_nil = function(value)
		if value ~= nil then
			error(string.format("Expected nil but got %s", vim.inspect(value)))
		end
	end,
	is_not_nil = function(value)
		if value == nil then
			error("Expected non-nil value but got nil")
		end
	end,
}

function M.run()
	local passed = 0
	local failed = 0
	local errors = {}

	for _, test in ipairs(tests) do
		local full_name = (test.describe and (test.describe .. " - ") or "") .. test.name

		local ok, err = pcall(function()
			if test.before_each then
				test.before_each()
			end

			test.fn()

			if test.after_each then
				test.after_each()
			end
		end)

		if ok then
			passed = passed + 1
			print("✓ " .. full_name)
		else
			failed = failed + 1
			print("✗ " .. full_name)
			table.insert(errors, { name = full_name, error = err })
		end
	end

	print(string.format("\n%d passed, %d failed", passed, failed))

	if #errors > 0 then
		print("\nFailures:")
		for _, e in ipairs(errors) do
			print("\n" .. e.name)
			print("  " .. e.error)
		end
		os.exit(1)
	end
end

return M
