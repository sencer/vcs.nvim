if vim.g.vcs_plugin_loaded then
	return
end
vim.g.vcs_plugin_loaded = true

local vcs = require("vcs")
vcs.register("git", require("vcs.git"))
vcs.register("hg", require("vcs.hg"))

-- Auto-load modified files if started empty in a repo
vim.api.nvim_create_autocmd("VimEnter", {
	callback = function()
		if vim.fn.bufname() == "" then
			local cwd = vim.fn.getcwd()
			local name, _ = vcs.detect(cwd)
			if name then
				vcs.load_modified_files(cwd)
			end
		end
	end,
})
