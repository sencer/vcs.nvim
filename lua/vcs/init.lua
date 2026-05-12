local M = {}

local providers = {}

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

-- Common function to load files into buffers asynchronously
local function load_files(files)
	vim.g.vcs_workspace_loaded = true
	local first = true
	for _, file in ipairs(files) do
		if file ~= "" then
			local nm = vim.fn.fnamemodify(file, ":p:~:.")
			local dir = vim.fn.fnamemodify(nm, ":h")
			local prefix = "." .. vim.fn.fnamemodify(nm, ":t") .. ".sw"

			async_check_swap_exists(dir, prefix, function(swap_exists)
				if swap_exists then
					return
				end
				if first and vim.fn.bufname() == "" then
					first = false
					vim.cmd.edit(nm)
				else
					vim.cmd.badd(nm)
				end
			end)
		end
	end
end

function M.load_modified_files(dir)
	local name, provider = M.detect(dir)
	if provider then
		provider.get_modified_files(dir, function(files)
			vim.schedule(function()
				load_files(files)
			end)
		end)
	else
		print("No VCS detected for " .. dir)
	end
end

return M
