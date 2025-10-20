--- Git operations for diff viewer
--- Provides file listing and diff content retrieval
local M = {}

--- Get list of changed files with their status
--- @param opts? table Options: { staged = bool, unstaged = bool }
--- @return table|nil Array of {path, status, staged} or nil on error
--- @return string|nil Error message if failed
function M.get_changed_files(opts)
	opts = opts or {}
	local include_staged = opts.staged ~= false -- default true
	local include_unstaged = opts.unstaged ~= false -- default true

	-- Get git status --porcelain output
	local cmd = "git status --porcelain --untracked-files=all"
	local output = vim.fn.system(cmd)

	if vim.v.shell_error ~= 0 then
		return nil, "Failed to run git status: " .. vim.trim(output)
	end

	local files = {}
	for line in vim.gsplit(output, "\n", { plain = true }) do
		if line ~= "" then
			-- Porcelain format: XY PATH
			-- X = index status, Y = working tree status
			local index_status = line:sub(1, 1)
			local worktree_status = line:sub(2, 2)
			local path = line:sub(4) -- Skip "XY "

			-- Determine if file has staged or unstaged changes
			local has_staged = index_status ~= " " and index_status ~= "?"
			local has_unstaged = worktree_status ~= " "

			-- Add entry for staged changes
			if has_staged and include_staged then
				table.insert(files, {
					path = path,
					status = index_status,
					staged = true,
				})
			end

			-- Add entry for unstaged changes (separate entry)
			if has_unstaged and include_unstaged then
				table.insert(files, {
					path = path,
					status = worktree_status,
					staged = false,
				})
			end
		end
	end

	return files
end

--- Get diff content for a specific file using difftastic (async)
--- @param file_path string Path to the file
--- @param opts? table Options: { staged = bool, context_lines = number }
--- @param callback function Callback(output: string|nil, err: string|nil)
function M.get_file_diff(file_path, opts, callback)
	opts = opts or {}
	local staged = opts.staged or false
	local context = opts.context_lines or 3

	-- Check if difft is available
	if vim.fn.executable("difft") == 0 then
		callback(nil, "difftastic (difft) not found in PATH")
		return
	end

	-- Build git diff command with difftastic as external diff
	local git_cmd = string.format(
		"git diff --color=always -U%d %s -- %s",
		context,
		staged and "--staged" or "",
		vim.fn.shellescape(file_path)
	)

	-- Set difftastic as external diff tool with width 500 and COLUMNS env var
	local cmd = "COLUMNS=500 GIT_EXTERNAL_DIFF='difft --color always --width 500' " .. git_cmd

	-- Run async
	vim.system({ "sh", "-c", cmd }, { text = true }, function(result)
		vim.schedule(function()
			if result.code ~= 0 then
				callback(nil, "Failed to get diff: " .. vim.trim(result.stderr or ""))
				return
			end

			local output = result.stdout or ""

			-- If output is empty, file might be new or deleted
			if vim.trim(output) == "" then
				-- Try to get file content for new files
				if not staged then
					-- Unstaged: show working tree content
					local ok, content = pcall(function()
						return table.concat(vim.fn.readfile(file_path), "\n")
					end)
					if ok then
						callback(content, nil)
					else
						callback("", nil)
					end
				else
					-- Staged: show index content
					vim.system(
						{ "git", "show", ":" .. file_path },
						{ text = true },
						function(show_result)
							vim.schedule(function()
								if show_result.code == 0 then
									callback(show_result.stdout, nil)
								else
									callback("", nil)
								end
							end)
						end
					)
				end
				return
			end

			callback(output, nil)
		end)
	end)
end

--- Check if we're in a git repository
--- @return boolean
function M.is_git_repo()
	local result = vim.fn.system("git rev-parse --git-dir 2>/dev/null")
	return vim.v.shell_error == 0
end

--- Get git root directory
--- @return string|nil Git root path or nil if not in repo
function M.get_git_root()
	if not M.is_git_repo() then
		return nil
	end
	local root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null")
	return vim.trim(root)
end

return M
