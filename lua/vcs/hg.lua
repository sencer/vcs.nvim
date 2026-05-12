local async = require("sencer.async")

local M = {}

function M.detect(dir)
	return vim.fn.finddir(".hg", dir .. ";") ~= ""
end

function M.get_modified_files(dir, callback)
	async.run_shell({
		command = "cd " .. vim.fn.shellescape(dir) .. " && hg status -n -m -a",
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

function M.get_current_head(dir, callback)
	async.run_shell({
		command = "cd " .. vim.fn.shellescape(dir) .. " && hg log -r . -T '{node}'",
		on_exit = function(obj)
			if obj.code ~= 0 then
				callback(nil)
				return
			end
			local head = vim.trim(obj.stdout or "")
			if head == "" then
				callback(nil)
			else
				callback(head)
			end
		end,
	})
end

function M.get_parents(dir, rev, callback)
	local revset = "parents(" .. rev .. ")"
	async.run_shell({
		command = "cd "
			.. vim.fn.shellescape(dir)
			.. " && hg log -r "
			.. vim.fn.shellescape(revset)
			.. " -T '{node}\\n'",
		on_exit = function(obj)
			if obj.code ~= 0 then
				callback({})
				return
			end
			local parents = {}
			for _, line in ipairs(vim.split(obj.stdout or "", "\n", { plain = true })) do
				if line ~= "" then
					table.insert(parents, line)
				end
			end
			callback(parents)
		end,
	})
end

function M.get_children(dir, rev, callback)
	local revset = "children(" .. rev .. ")"
	async.run_shell({
		command = "cd "
			.. vim.fn.shellescape(dir)
			.. " && hg log -r "
			.. vim.fn.shellescape(revset)
			.. " -T '{node}\\n'",
		on_exit = function(obj)
			if obj.code ~= 0 then
				callback({})
				return
			end
			local children = {}
			for _, line in ipairs(vim.split(obj.stdout or "", "\n", { plain = true })) do
				if line ~= "" then
					table.insert(children, line)
				end
			end
			callback(children)
		end,
	})
end

function M.get_revision_files(dir, rev, callback)
	async.run_shell({
		command = "cd " .. vim.fn.shellescape(dir) .. " && hg status -n -a -m --change " .. vim.fn.shellescape(rev),
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

function M.get_revision_info(dir, rev, callback)
	local esc_dir = vim.fn.shellescape(dir)
	local esc_rev = vim.fn.shellescape(rev)
	async.run_shell({
		command = "cd "
			.. esc_dir
			.. " && hg log -r "
			.. esc_rev
			.. ' -T "{rev}:{node|short} ({bookmarks}): {desc|firstline}"',
		on_exit = function(obj)
			if obj.code ~= 0 then
				callback(rev)
				return
			end
			local info = vim.trim(obj.stdout or "")
			if info == "" then
				callback(rev)
			else
				info = info:gsub(" %(%):", ":")
				callback(info)
			end
		end,
	})
end

return M

