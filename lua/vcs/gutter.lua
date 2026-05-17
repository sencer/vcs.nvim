local api = vim.api
local set_extmark = api.nvim_buf_set_extmark
local table_insert = table.insert
local unpack = unpack or table.unpack
local math_min = math.min
local math_max = math.max

local M = {}

local ns = api.nvim_create_namespace("vcs_gutter")

local cached_base = {} -- [bufnr] = string content
local cached_hunks = {} -- [bufnr] = array of hunks
local repo_stats = {} -- [bufnr] = { added, deleted, changed }
local timers = {} -- [bufnr] = timer handle

-- Initialize signs / highlight groups
api.nvim_set_hl(0, "VCSGutterAdd", { link = "DiffAdd" })
api.nvim_set_hl(0, "VCSGutterDelete", { link = "DiffDelete" })
api.nvim_set_hl(0, "VCSGutterChange", { link = "DiffChange" })

local vcs = require("vcs")

local function update_gutter(bufnr)
	if not api.nvim_buf_is_valid(bufnr) then return end

	local base_text = cached_base[bufnr]
	if not base_text then return end

	local buf_lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local buf_text = table.concat(buf_lines, "\n")

	local indices = vim.diff(base_text, buf_text, { result_type = "indices" })
	if not indices then return end

	api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

	local hunks = {}
	local added, deleted, changed = 0, 0, 0

	for _, hunk in ipairs(indices) do
		local start_a, count_a, start_b, count_b = unpack(hunk)
		local h_type
		if count_a == 0 then
			h_type = "add"
			added = added + count_b
		elseif count_b == 0 then
			h_type = "delete"
			deleted = deleted + count_a
		else
			h_type = "change"
			changed = changed + count_b
		end

		table_insert(hunks, {
			start_a = start_a,
			count_a = count_a,
			start_b = start_b,
			count_b = count_b,
			type = h_type,
		})

		local sign_text, hl_group
		if h_type == "add" then
			sign_text = "+"
			hl_group = "VCSGutterAdd"
		elseif h_type == "delete" then
			sign_text = "_"
			hl_group = "VCSGutterDelete"
		else
			sign_text = "~"
			hl_group = "VCSGutterChange"
		end

		local place_line = math_max(0, start_b - 1)
		for i = 0, math_max(0, count_b - 1) do
			local l = place_line + i
			if l < #buf_lines then
				set_extmark(bufnr, ns, l, 0, {
					sign_text = sign_text,
					sign_hl_group = hl_group,
					priority = 10,
				})
			end
		end
	end

	cached_hunks[bufnr] = hunks
	repo_stats[bufnr] = { added = added, deleted = deleted, changed = changed }
end

local function debounced_update(bufnr)
	if timers[bufnr] then
		timers[bufnr]:stop()
	end
	timers[bufnr] = vim.defer_fn(function()
		timers[bufnr] = nil
		update_gutter(bufnr)
	end, 150)
end

function M.attach(bufnr, base_rev)
	bufnr = bufnr or api.nvim_get_current_buf()
	local file = api.nvim_buf_get_name(bufnr)
	if file == "" then return end

	local name, provider, real_file, rev
	if vim.startswith(file, "vcs://") then
		local parts = vim.split(file:sub(#"vcs://" + 1), "/", { plain = true })
		name = parts[1]
		provider = vcs.get_provider(name)
		rev = parts[3]
		real_file = table.concat(vim.list_slice(parts, 4), "/")
		if real_file:sub(1, 1) ~= "/" then
			real_file = "/" .. real_file
		end
	else
		real_file = file
		name, provider = vcs.detect(vim.fs.dirname(real_file))
	end

	if not provider or not provider.get_file_content then return end

	provider.get_file_content(real_file, base_rev, function(content)
		vim.schedule(function()
			if api.nvim_buf_is_valid(bufnr) then
				cached_base[bufnr] = content or ""
				update_gutter(bufnr)

				local group = api.nvim_create_augroup("VCSGutter_" .. bufnr, { clear = true })
				api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
					group = group,
					buffer = bufnr,
					callback = function()
						debounced_update(bufnr)
					end,
				})

				api.nvim_create_autocmd("BufWipeout", {
					group = group,
					buffer = bufnr,
					callback = function()
						cached_base[bufnr] = nil
						cached_hunks[bufnr] = nil
						repo_stats[bufnr] = nil
						if timers[bufnr] then
							timers[bufnr]:stop()
							timers[bufnr] = nil
						end
					end,
				})

				vim.keymap.set("n", "]c", M.next_hunk, { buffer = bufnr, desc = "Next hunk" })
				vim.keymap.set("n", "[c", M.prev_hunk, { buffer = bufnr, desc = "Previous hunk" })
				vim.keymap.set({"o", "x"}, "ic", M.select_hunk, { buffer = bufnr, desc = "Inner hunk" })
				vim.keymap.set({"o", "x"}, "ac", M.select_hunk, { buffer = bufnr, desc = "A hunk" })
			end
		end)
	end)
end

function M.get_stats(bufnr)
	bufnr = bufnr or api.nvim_get_current_buf()
	return repo_stats[bufnr] or { added = 0, deleted = 0, changed = 0 }
end

function M.next_hunk()
	local bufnr = api.nvim_get_current_buf()
	local hunks = cached_hunks[bufnr]
	if not hunks or #hunks == 0 then return end

	local cur_line = vim.fn.line(".")
	for _, hunk in ipairs(hunks) do
		if hunk.start_b > cur_line then
			vim.cmd("normal! " .. math_max(1, hunk.start_b) .. "G")
			return
		end
	end
	print("No more hunks")
end

function M.prev_hunk()
	local bufnr = api.nvim_get_current_buf()
	local hunks = cached_hunks[bufnr]
	if not hunks or #hunks == 0 then return end

	local cur_line = vim.fn.line(".")
	for i = #hunks, 1, -1 do
		local hunk = hunks[i]
		if hunk.start_b < cur_line then
			vim.cmd("normal! " .. math_max(1, hunk.start_b) .. "G")
			return
		end
	end
	print("No more hunks")
end

local function get_current_hunk(bufnr, cur_line)
	local hunks = cached_hunks[bufnr]
	if not hunks then return nil end

	for _, hunk in ipairs(hunks) do
		local end_b = hunk.start_b + math_max(0, hunk.count_b - 1)
		if cur_line >= hunk.start_b and cur_line <= end_b then
			return hunk
		end
	end
	return nil
end

function M.select_hunk()
	local bufnr = api.nvim_get_current_buf()
	local cur_line = vim.fn.line(".")
	local hunk = get_current_hunk(bufnr, cur_line)
	if not hunk then return end

	local end_b = hunk.start_b + math_max(0, hunk.count_b - 1)
	vim.cmd("normal! " .. math_max(1, hunk.start_b) .. "GV" .. end_b .. "G")
end

function M.preview_hunk()
	local bufnr = api.nvim_get_current_buf()
	local cur_line = vim.fn.line(".")
	local hunk = get_current_hunk(bufnr, cur_line)
	if not hunk then
		print("No hunk under cursor")
		return
	end

	local base_text = cached_base[bufnr]
	if not base_text then return end
	local base_lines = vim.split(base_text, "\n", { plain = true })

	local preview_lines = {}
	table_insert(preview_lines, "=== Base Lines (" .. hunk.type .. ") ===")
	for i = 0, hunk.count_a - 1 do
		local l = hunk.start_a + i
		if l <= #base_lines then
			table_insert(preview_lines, base_lines[l])
		end
	end

	local pbuf = api.nvim_create_buf(false, true)
	api.nvim_buf_set_lines(pbuf, 0, -1, false, preview_lines)

	local win_opts = {
		relative = "cursor",
		row = 1,
		col = 1,
		width = math_min(80, math_max(30, #preview_lines[1] + 10)),
		height = math_min(15, #preview_lines),
		style = "minimal",
		border = "rounded",
	}
	api.nvim_open_win(pbuf, true, win_opts)
	vim.bo[pbuf].filetype = vim.bo[bufnr].filetype
end

function M.revert_hunk()
	local bufnr = api.nvim_get_current_buf()
	local cur_line = vim.fn.line(".")
	local hunk = get_current_hunk(bufnr, cur_line)
	if not hunk then
		print("No hunk under cursor")
		return
	end

	local base_text = cached_base[bufnr]
	if not base_text then return end
	local base_lines = vim.split(base_text, "\n", { plain = true })

	local extract_base = {}
	for i = 0, hunk.count_a - 1 do
		local l = hunk.start_a + i
		if l <= #base_lines then
			table_insert(extract_base, base_lines[l])
		end
	end

	local start_b = math_max(0, hunk.start_b - 1)
	local end_b = start_b + hunk.count_b
	api.nvim_buf_set_lines(bufnr, start_b, end_b, false, extract_base)
end

api.nvim_create_augroup("VCSGutterAutoAttach", { clear = true })
api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
	group = "VCSGutterAutoAttach",
	pattern = "*",
	callback = function(args)
		local bnr = args.buf
		if vim.bo[bnr].buflisted and vim.bo[bnr].buftype == "" then
			vim.schedule(function()
				M.attach(bnr, nil)
			end)
		end
	end,
})

return M
