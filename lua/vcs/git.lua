local async = require("sencer.async")

local M = {}

function M.detect(dir)
	return vim.fn.finddir(".git", dir .. ";") ~= "" or vim.fn.findfile(".git", dir .. ";") ~= ""
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

function M.get_current_head(dir, callback)
	async.run_shell({
		command = "git -C " .. vim.fn.shellescape(dir) .. " rev-parse HEAD",
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
	async.run_shell({
		command = "git -C " .. vim.fn.shellescape(dir) .. " log -1 --pretty=format:%P " .. vim.fn.shellescape(rev),
		on_exit = function(obj)
			if obj.code ~= 0 then
				callback({})
				return
			end
			local parents = {}
			local stdout = vim.trim(obj.stdout or "")
			if stdout ~= "" then
				parents = vim.split(stdout, " ", { trimempty = true })
			end
			callback(parents)
		end,
	})
end

function M.get_children(dir, rev, callback)
	async.run_shell({
		command = "git -C " .. vim.fn.shellescape(dir) .. " rev-list --all --children",
		on_exit = function(obj)
			if obj.code ~= 0 then
				callback({})
				return
			end
			local children = {}
			for _, line in ipairs(vim.split(obj.stdout or "", "\n", { plain = true })) do
				if vim.startswith(line, rev) then
					local parts = vim.split(line, " ", { trimempty = true })
					for i = 2, #parts do
						table.insert(children, parts[i])
					end
					break
				end
			end
			callback(children)
		end,
	})
end

function M.get_revision_files(dir, rev, callback)
	async.run_shell({
		command = "git -C "
			.. vim.fn.shellescape(dir)
			.. " diff-tree --no-commit-id --name-only -r --diff-filter=ACMRT "
			.. vim.fn.shellescape(rev),
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
		command = "git -C " .. esc_dir .. ' log -1 --pretty=format:"%h%x09%s" ' .. esc_rev,
		on_exit = function(obj_log)
			if obj_log.code ~= 0 then
				callback(rev)
				return
			end
			local log_out = vim.trim(obj_log.stdout or "")

			vim.schedule(function()
				async.run_shell({
					command = "git -C " .. esc_dir .. " name-rev --name-only " .. esc_rev,
					on_exit = function(obj_name)
						local name = ""
						if obj_name.code == 0 then
							name = vim.trim(obj_name.stdout or "")
						end

						local parts = vim.split(log_out, "\t", { plain = true })
						local hash = parts[1] or rev
						local summary = parts[2] or ""

						local info = hash
						if name ~= "" and name ~= "undefined" then
							info = info .. " (" .. name .. ")"
						end
						if summary ~= "" then
							info = info .. ": " .. summary
						end
						callback(info)
					end,
				})
			end)
		end,
	})
end

function M.get_primary_states(file, callback)
	local dir = vim.fs.dirname(file)
	local rel_file = vim.fs.basename(file)
	async.run_shell({
		command = "git -C " .. vim.fn.shellescape(dir) .. " log --follow --format='%h: %s' -- " .. vim.fn.shellescape(rel_file),
		on_exit = function(obj)
			if obj.code ~= 0 then
				callback({}, nil)
				return
			end
			local entries = {}
			for _, line in ipairs(vim.split(obj.stdout or "", "\n", { plain = true })) do
				if line ~= "" then
					local parts = vim.split(line, ": ", { plain = true })
					local rev = parts[1]
					table.insert(entries, {
						uri = string.format("vcs://git/diff/%s%s", rev, file),
						display = line,
						rev = rev,
					})
				end
			end

			-- Add Working vs HEAD
			table.insert(entries, 1, {
				uri = string.format("vcs://git/diff/working%s", file),
				display = "working: Working Directory vs HEAD",
				rev = "working",
			})

			callback(entries, nil)
		end,
	})
end

function M.get_file_content(file, rev, callback)
	rev = rev or "HEAD"
	local dir = vim.fs.dirname(file)
	local rel_file = vim.fs.basename(file)
	local ignore_command = "git -C " .. vim.fn.shellescape(dir) .. " check-ignore -q -- " .. vim.fn.shellescape(rel_file)
	async.run_shell({
		command = "git -C " .. vim.fn.shellescape(dir) .. " show " .. vim.fn.shellescape(rev .. ":./" .. rel_file),
		on_exit = function(obj)
			if obj.code ~= 0 then
				vim.schedule(function()
					async.run_shell({
						command = ignore_command,
						on_exit = function(ignore_obj)
							callback(ignore_obj.code == 1 and "" or nil)
						end,
					})
				end)
				return
			end
			callback(obj.stdout)
		end,
	})
end

return M
