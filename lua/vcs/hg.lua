local async = require("sencer.async")

local M = {}

function M.detect(dir)
	return vim.fn.finddir(".hg", dir .. ";") ~= ""
end

function M.get_modified_files(dir, callback)
	async.run_shell({
		command = "hg -R " .. vim.fn.shellescape(dir) .. " status -n -m -a",
		on_exit = function(obj)
			if obj.code ~= 0 then
				callback({})
				return
			end
			local files = {}
			for _, line in ipairs(vim.split(obj.stdout or "", "\n", { plain = true })) do
				if line ~= "" then
					table.insert(files, dir .. "/" .. line)
				end
			end
			callback(files)
		end,
	})
end

return M
