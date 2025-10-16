#!/usr/bin/env nvim -l

-- Get the script directory
local script_dir = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h")
local repo_root = vim.fn.fnamemodify(script_dir, ":h:h:h:h")

-- Add the nvim config to the package path
package.path = package.path
	.. ";" .. repo_root .. "/lua/?.lua"
	.. ";" .. repo_root .. "/lua/?/init.lua"
	.. ";" .. repo_root .. "/lua/dev/difft/lua/?.lua"

-- Run the tests
require("dev.difft.tests.difft_spec")
