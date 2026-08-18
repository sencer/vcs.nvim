local async = require("sencer.async")

local M = {}

function M.detect(dir)
	return vim.fn.finddir(".jj", dir .. ";") ~= ""
end

function M.get_modified_files(dir, callback)
	async.run_shell({
		command = "cd " .. vim.fn.shellescape(dir) .. " && jj diff --name-only --no-pager --color=never",
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
		command = "cd " .. vim.fn.shellescape(dir) .. " && jj log --no-graph -r @ -T 'commit_id' --no-pager --color=never",
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
		command = "cd " .. vim.fn.shellescape(dir) .. " && jj log --no-graph -r " .. vim.fn.shellescape(revset) .. " -T 'commit_id ++ \"\\n\"' --no-pager --color=never",
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
		command = "cd " .. vim.fn.shellescape(dir) .. " && jj log --no-graph -r " .. vim.fn.shellescape(revset) .. " -T 'commit_id ++ \"\\n\"' --no-pager --color=never",
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
		command = "cd " .. vim.fn.shellescape(dir) .. " && jj diff --name-only -r " .. vim.fn.shellescape(rev .. "-") .. " -r " .. vim.fn.shellescape(rev) .. " --no-pager --color=never",
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
	async.run_shell({
		command = "cd " .. vim.fn.shellescape(dir) .. " && jj log --no-graph -r " .. vim.fn.shellescape(rev) .. ' -T \'commit_id.short() ++ ": " ++ description.first_line()\' --no-pager --color=never',
		on_exit = function(obj)
			if obj.code ~= 0 then
				callback(rev)
				return
			end
			local info = vim.trim(obj.stdout or "")
			if info == "" then
				callback(rev)
			else
				callback(info)
			end
		end,
	})
end

function M.get_primary_states(file, callback)
	local dir = vim.fs.dirname(file)
	local rel_file = vim.fs.basename(file)
	async.run_shell({
		command = "cd " .. vim.fn.shellescape(dir) .. " && jj log --no-graph -T 'commit_id.short() ++ \"|@|\" ++ description.first_line() ++ \"|@|\" ++ if(current_working_copy, \"true\", \"false\") ++ \"\\n\"' --no-pager --color=never -- " .. vim.fn.shellescape(rel_file),
		on_exit = function(obj)
			if obj.code ~= 0 then
				callback({}, nil)
				return
			end
			local entries = {}
			for _, line in ipairs(vim.split(obj.stdout or "", "\n", { plain = true })) do
				if line ~= "" then
					local parts = vim.split(line, "|@|", { plain = true })
					if #parts >= 3 then
						local rev = parts[1]
						local desc = parts[2]
						local is_wc = parts[3] == "true"

						if not is_wc then
							table.insert(entries, {
								uri = string.format("vcs://jj/diff/%s%s", rev, file),
								display = string.format("%s: %s", rev, desc),
								rev = rev,
							})
						end
					end
				end
			end

			-- Add Working vs .
			table.insert(entries, 1, {
				uri = string.format("vcs://jj/diff/working%s", file),
				display = "working: Working Directory vs .",
				rev = "working",
			})

			callback(entries, nil)
		end,
	})
end

function M.get_file_content(file, rev, callback)
	rev = rev or "HEAD"
	if rev == "working" then
		rev = "@"
	elseif rev == "HEAD" then
		rev = "@-"
	end
	local dir = vim.fs.dirname(file)
	local rel_file = vim.fs.basename(file)
	local tracked_command = "cd " .. vim.fn.shellescape(dir) .. " && jj file list --no-pager --color=never -r @ -- " .. vim.fn.shellescape(rel_file)
	async.run_shell({
		command = "cd " .. vim.fn.shellescape(dir) .. " && jj file show --no-pager -r " .. vim.fn.shellescape(rev) .. " -- " .. vim.fn.shellescape(rel_file),
		on_exit = function(obj)
			if obj.code ~= 0 then
				vim.schedule(function()
					async.run_shell({
						command = tracked_command,
						on_exit = function(tracked_obj)
							callback(tracked_obj.code == 0 and (tracked_obj.stdout or "") ~= "" and "" or nil)
						end,
					})
				end)
				return
			end
			local content = obj.stdout
			if content then
				content = content:gsub("\n$", "")
			end
			callback(content)
		end,
	})
end

return M
