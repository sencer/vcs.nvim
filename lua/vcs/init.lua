local M = {}

local providers = {}

local repo_states = {}

local function get_state(dir)
	if not repo_states[dir] then
		repo_states[dir] = { current_rev = "working" }
	end
	return repo_states[dir]
end
local function safe_echo(msg, hl)
	vim.schedule(function()
		local limit = vim.v.echospace
		local text = msg
		if #text > limit then
			text = text:sub(1, limit - 3) .. "..."
		end
		hl = hl or "Normal"
		vim.api.nvim_echo({{text, hl}}, false, {})
	end)
end
local function filter_valid_files(files)
	local valid = {}
	for _, file in ipairs(files) do
		if file ~= "" then
			if vim.fn.isdirectory(file) == 0 then
				table.insert(valid, file)
			end
		end
	end
	return valid
end

function M.register(name, provider)
	providers[name] = provider
end

function M.get_provider(name)
	return providers[name]
end

function M.detect(dir)
	for name, provider in pairs(providers) do
		if provider.detect(dir) then
			return name, provider
		end
	end
	return nil, nil
end

---Asynchronously checks if a swap file exists.
local function async_check_swap_exists(dir, prefix, callback)
	vim.loop.fs_scandir(dir, function(err, req)
		if err then
			vim.schedule(function()
				callback(false)
			end)
			return
		end

		local function check_next()
			local name, type = vim.loop.fs_scandir_next(req)
			if not name then
				vim.schedule(function()
					callback(false)
				end)
				return
			end
			if name:sub(1, #prefix) == prefix then
				vim.schedule(function()
					callback(true)
				end)
				return
			end
			check_next()
		end

		check_next()
	end)
end

local function wipe_other_buffers(keep_files)
	local keep_set = {}
	for _, f in ipairs(keep_files) do
		keep_set[vim.fn.fnamemodify(f, ":p")] = true
	end

	vim.schedule(function()
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_loaded(buf) then
				local name = vim.api.nvim_buf_get_name(buf)
				local abs_name = vim.fn.fnamemodify(name, ":p")
				if name ~= "" and not keep_set[abs_name] then
					if not vim.api.nvim_buf_get_option(buf, "modified") then
						vim.api.nvim_buf_delete(buf, { force = false })
					end
				end
			end
		end
	end)
end

-- Common function to load files into buffers asynchronously
local function load_files(valid_files, exclusive)
	vim.g.vcs_workspace_loaded = true
	local first = true
	local loaded_count = 0
	local total_files = #valid_files

	if total_files == 0 then
		safe_echo("No valid files to load for this revision", "WarningMsg")
		return
	end

	local keep_files = {}
	for _, file in ipairs(valid_files) do
		table.insert(keep_files, vim.fn.fnamemodify(file, ":p"))
	end

	local function on_file_processed()
		loaded_count = loaded_count + 1
		if loaded_count == total_files and exclusive then
			wipe_other_buffers(keep_files)
		end
	end

	for _, file in ipairs(valid_files) do
		local nm = vim.fn.fnamemodify(file, ":p:~:.")
		local dir = vim.fn.fnamemodify(nm, ":h")
		local prefix = "." .. vim.fn.fnamemodify(nm, ":t") .. ".sw"

		async_check_swap_exists(dir, prefix, function(swap_exists)
			if swap_exists then
				on_file_processed()
				return
			end
			if first and vim.fn.bufname() == "" then
				first = false
				vim.cmd.edit(nm)
			else
				vim.cmd.badd(nm)
			end
			on_file_processed()
		end)
	end
end

function M.load_modified_files(dir)
	local name, provider = M.detect(dir)
	if provider then
		provider.get_modified_files(dir, function(files)
			vim.schedule(function()
				local valid = filter_valid_files(files)
				load_files(valid, false)
			end)
		end)
	else
		safe_echo("No VCS detected for " .. dir, "ErrorMsg")
	end
end

function M.load_parent_modified_files(dir, exclusive)
	local name, provider = M.detect(dir)
	if not provider then
		safe_echo("No VCS detected for " .. dir, "ErrorMsg")
		return
	end

	if not provider.get_current_head or not provider.get_parents or not provider.get_revision_files or not provider.get_revision_info then
		safe_echo("(parents not available)", "WarningMsg")
		return
	end

	local state = get_state(dir)

	local function load_rev(rev)
		provider.get_revision_files(dir, rev, function(files)
			vim.schedule(function()
				local valid = filter_valid_files(files)
				if #valid == 0 then
					provider.get_revision_info(dir, rev, function(info)
						safe_echo("[vcs] Skipping empty commit " .. info, "WarningMsg")
						vim.schedule(function()
							M.load_parent_modified_files(dir, exclusive)
						end)
					end)
				else
					load_files(valid, exclusive)
					provider.get_revision_info(dir, rev, function(info)
						safe_echo("[vcs] Switched to " .. info)
					end)
				end
			end)
		end)
	end

	if state.current_rev == "working" then
		provider.get_current_head(dir, function(head_rev)
			vim.schedule(function()
				if head_rev and head_rev ~= "" then
					state.current_rev = head_rev
					load_rev(head_rev)
				else
					safe_echo("Could not get current HEAD revision", "ErrorMsg")
				end
			end)
		end)
	else
		provider.get_parents(dir, state.current_rev, function(parents)
			vim.schedule(function()
				if #parents > 0 then
					local parent = parents[1]
					state.current_rev = parent
					load_rev(parent)
				else
					safe_echo("Already at initial commit", "WarningMsg")
				end
			end)
		end)
	end
end

function M.load_child_modified_files(dir, exclusive)
	local name, provider = M.detect(dir)
	if not provider then
		safe_echo("No VCS detected for " .. dir, "ErrorMsg")
		return
	end

	if not provider.get_current_head or not provider.get_children or not provider.get_revision_files or not provider.get_revision_info then
		safe_echo("(children not available)", "WarningMsg")
		return
	end

	local state = get_state(dir)

	if state.current_rev == "working" then
		safe_echo("Already at working directory (tip)", "WarningMsg")
		return
	end

	local function load_rev(rev)
		provider.get_revision_files(dir, rev, function(files)
			vim.schedule(function()
				local valid = filter_valid_files(files)
				if #valid == 0 then
					provider.get_revision_info(dir, rev, function(info)
						safe_echo("[vcs] Skipping empty commit " .. info, "WarningMsg")
						vim.schedule(function()
							M.load_child_modified_files(dir, exclusive)
						end)
					end)
				else
					load_files(valid, exclusive)
					provider.get_revision_info(dir, rev, function(info)
						safe_echo("[vcs] Switched to " .. info)
					end)
				end
			end)
		end)
	end

	provider.get_current_head(dir, function(head_rev)
		vim.schedule(function()
			if state.current_rev == head_rev then
				state.current_rev = "working"
				provider.get_modified_files(dir, function(files)
					vim.schedule(function()
						local valid = filter_valid_files(files)
						load_files(valid, exclusive)
					end)
				end)
				safe_echo("[vcs] Switched to Working Directory (tip)")
			else
				provider.get_children(dir, state.current_rev, function(children)
					vim.schedule(function()
						if #children == 0 then
							safe_echo("Already at branch tip", "WarningMsg")
						elseif #children == 1 then
							local child = children[1]
							state.current_rev = child
							load_rev(child)
						else
							vim.ui.select(children, {
								prompt = "Select child commit to follow:",
								format_item = function(item)
									return item
								end
							}, function(choice)
								if choice then
									state.current_rev = choice
									load_rev(choice)
								end
							end)
						end
					end)
				end)
			end
		end)
	end)
end

return M

