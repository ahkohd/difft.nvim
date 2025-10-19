local M = {}

function M.check()
	vim.health.start("difft.nvim")

	-- Check if difftastic is installed
	if vim.fn.executable("difft") == 1 then
		local handle = io.popen("difft --version 2>&1")
		if handle then
			local version = handle:read("*a")
			handle:close()
			vim.health.ok("difftastic found: " .. version:gsub("\n", ""))
		else
			vim.health.ok("difftastic command is available")
		end
	else
		vim.health.error("difftastic not found in PATH", {
			"Install difftastic: https://github.com/Wilfred/difftastic",
			"Ensure 'difft' command is available in your PATH",
		})
	end

	-- Check Neovim version
	if vim.fn.has("nvim-0.10") == 1 then
		vim.health.ok("Neovim version is compatible (0.10+)")
	else
		vim.health.warn("Neovim 0.10+ is recommended for best compatibility")
	end

	-- Check if plugin is loaded
	local ok, difft = pcall(require, "difft")
	if ok then
		vim.health.ok("difft.nvim module loaded successfully")

		-- Check configuration
		if difft._test and difft._test.config then
			vim.health.info("Configuration initialized")
		end
	else
		vim.health.error("Failed to load difft.nvim module", {
			"Ensure the plugin is properly installed",
			"Check your plugin manager configuration",
		})
	end
end

return M
