local async = require("sencer.async")

local M = {}

function M.detect(dir)
	return vim.fn.finddir(".git", dir .. ";") ~= ""
end

function M.get_modified_files(dir, callback)
	async.run_shell({
		command = "git -C " .. vim.fn.shellescape(dir) .. " status --porcelain",
		on_exit = function(obj)
			if obj.code ~= 0 then
				callback({})
				return
			end
			local files = {}
			for _, line in ipairs(vim.split(obj.stdout or "", "\n", { plain = true })) do
				if line ~= "" then
					local file = line:sub(4)
					if line:sub(1, 1) == "R" then
						local parts = vim.split(file, " -> ", { plain = true })
						file = parts[2]
					end
					table.insert(files, dir .. "/" .. file)
				end
			end
			callback(files)
		end,
	})
end

return M
