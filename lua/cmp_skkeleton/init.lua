local source = {}

source.new = function()
	return setmetatable({
		_completion_sequence = 0,
		_finalized_completions = {},
		_finalized_order = {},
	}, { __index = source })
end

source.is_available = function()
	return vim.fn["skkeleton#is_enabled"]()
end

source.get_debug_name = function()
	return "skkeleton"
end

source.get_keyword_pattern = function()
	local mode = vim.g["skkeleton#mode"]
	if mode == "abbrev" then
		return [[\%([a-zA-Z]\+\)]]
	else
		return [[\%([ぁ-ゖァ-ヺー]\+\)]]
	end
end

source._build_rank_map = function(ranks)
	table.sort(ranks, function(a, b)
		return a[2] > b[2]
	end)
	local rank_map = {}
	for i, rank_entry in ipairs(ranks) do
		rank_map[rank_entry[1]] = i - 1
	end
	return rank_map
end

source._get_base_kana_length = function(_, candidates)
	local min_length = math.huge
	for _, cs in pairs(candidates) do
		local kana_length = vim.fn.strchars(cs[1])
		min_length = math.min(min_length, kana_length)
	end
	return min_length
end

source._calculate_smart_rank = function(_, base_rank, actual_kana_length, input_kana_length)
	if actual_kana_length == input_kana_length then
		return base_rank - 500
	elseif actual_kana_length == input_kana_length + 1 then
		return base_rank - 100
	else
		return base_rank + (actual_kana_length - input_kana_length) * 200
	end
end

source._parse_candidate = function(_, raw_candidate)
	local label = string.gsub(raw_candidate, [[;.*$]], "")
	local annotation_match = string.match(raw_candidate, [[;.*$]])
	local annotation = annotation_match and string.gsub(annotation_match, [[^;]], "") or nil
	return label, annotation
end

source._build_sort_text = function(_, normalized_rank, idx, label)
	return string.format("%05d_%05d_%s", normalized_rank, idx, label)
end

source._build_documentation = function(_, kana, annotation)
	if annotation then
		return kana .. "\n" .. annotation
	else
		return kana
	end
end

source._get_completion_location = function(self, request)
	local context = request and request.context
	if not context or type(context.cursor_before_line) ~= "string" then
		return nil
	end

	local preedit = self:_get_pre_edit()
	local marker = self:_get_marker()
	if type(preedit) ~= "string" or preedit == "" or type(marker) ~= "string" then
		return nil
	end
	if preedit:sub(1, #marker) ~= marker or context.cursor_before_line:sub(-#preedit) ~= preedit then
		return nil
	end

	return {
		bufnr = context.bufnr,
		row = context.cursor and context.cursor.line or nil,
		marker_col = #context.cursor_before_line - #preedit,
		marker = marker,
		context_id = context.id,
	}
end

source._build_completion_metadata = function(self, location, item_index, midasi, word, completion_type, inserted)
	if not location or location.bufnr == nil or location.row == nil then
		return nil
	end

	local context_id = location.context_id or "context"
	return {
		id = string.format("%s:%d:%s", context_id, self._completion_sequence, item_index),
		bufnr = location.bufnr,
		row = location.row,
		marker_col = location.marker_col,
		marker = location.marker,
		midasi = midasi,
		word = word,
		type = completion_type,
		inserted = inserted,
	}
end

source.complete = function(self, request, callback)
	local candidates = self:_get_completion_result()
	local ranks = self:_get_ranks()
	local okuri_candidates = self:_get_okuri_candidates()
	self._completion_sequence = self._completion_sequence + 1
	local location = self:_get_completion_location(request)

	local rank_map = source._build_rank_map(ranks)
	local base_kana_length = self:_get_base_kana_length(candidates)

	local items = {}
	local added_labels = {}
	-- ユーザー辞書ではない候補の優先度を保持するためのインデックス
	-- 例: SKK_JISYO.Lの以下の順番を保持する
	-- かんとう /関東/巻頭/完投/竿頭/敢闘/間道;舶来の織物/竿灯/完答/冠頭/
	-- https://github.com/happy663/dotfiles/issues/196
	local idx = 0

	-- 送りなし候補の処理
	for _, cs in pairs(candidates) do
		local kana = cs[1]
		local actual_kana_length = vim.fn.strchars(kana)

		for _, c in pairs(cs[2]) do
			local label, annotation = self:_parse_candidate(c)
			if not added_labels[label] then
				added_labels[label] = true
				idx = idx + 1

				local base_rank = rank_map[label] or 9999
				local rank = self:_calculate_smart_rank(base_rank, actual_kana_length, base_kana_length)
				local normalized_rank = rank + 10000

				local metadata =
					self:_build_completion_metadata(location, "okurinasi:" .. idx, kana, label, "okurinasi", label)
				table.insert(items, {
					label = label,
					word = label,
					filterText = kana,
					sortText = self:_build_sort_text(normalized_rank, idx, label),
					documentation = self:_build_documentation(kana, annotation),
					data = metadata and { cmp_skkeleton = metadata } or nil,
				})
			end
		end
	end

	-- 送りあり候補の処理
	for index, okuri_item in ipairs(okuri_candidates) do
		local label = okuri_item.word
		if not added_labels[label] then
			added_labels[label] = true

			local base_rank = rank_map[label] or 9999
			local normalized_rank = (base_rank + 500) + 10000

			local okuri_len = vim.fn.strchars(okuri_item.okuri)
			local word_len = vim.fn.strchars(label)
			local word_without_okuri = vim.fn.strcharpart(label, 0, word_len - okuri_len)
			local metadata = self:_build_completion_metadata(
				location,
				"okuriari:" .. index,
				okuri_item.midasi,
				word_without_okuri,
				"okuriari",
				label
			)

			table.insert(items, {
				label = label,
				word = label,
				filterText = okuri_item.kana,
				sortText = self:_build_sort_text(normalized_rank, index, label),
				documentation = okuri_item.kana,
				data = {
					midasi = okuri_item.midasi,
					okuri = okuri_item.okuri,
					okuriari = true,
					cmp_skkeleton = metadata,
				},
			})
		end
	end

	if #items == 0 then
		callback()
		return
	end

	callback({ items = items, isIncomplete = true })
end

source.resolve = function(self, completion_item, callback)
	callback(completion_item)
end

source._remember_finalized = function(self, id)
	self._finalized_completions[id] = true
	table.insert(self._finalized_order, id)
	if #self._finalized_order > 128 then
		local expired = table.remove(self._finalized_order, 1)
		self._finalized_completions[expired] = nil
	end
end

source._finalize_completion = function(self, completion_item)
	local metadata = completion_item and completion_item.data and completion_item.data.cmp_skkeleton
	if not metadata or self._finalized_completions[metadata.id] then
		return false
	end
	if metadata.bufnr ~= vim.api.nvim_get_current_buf() or not vim.api.nvim_buf_is_valid(metadata.bufnr) then
		return false
	end

	local line_count = vim.api.nvim_buf_line_count(metadata.bufnr)
	if metadata.row < 0 or metadata.row >= line_count then
		return false
	end
	local line = vim.api.nvim_buf_get_lines(metadata.bufnr, metadata.row, metadata.row + 1, false)[1]
	local marker_start = metadata.marker_col + 1
	local inserted_start = marker_start + #metadata.marker
	if line:sub(marker_start, inserted_start - 1) ~= metadata.marker then
		return false
	end
	if
		metadata.inserted == ""
		or line:sub(inserted_start, inserted_start + #metadata.inserted - 1) ~= metadata.inserted
	then
		return false
	end

	local ok, err =
		pcall(self._complete_callback, self, metadata.midasi, metadata.word, metadata.type, metadata.inserted)
	if not ok then
		vim.notify("cmp-skkeleton: failed to notify skkeleton: " .. tostring(err), vim.log.levels.ERROR)
		return false
	end

	self:_remember_finalized(metadata.id)
	local cursor = vim.api.nvim_win_get_cursor(0)
	vim.api.nvim_buf_set_text(
		metadata.bufnr,
		metadata.row,
		metadata.marker_col,
		metadata.row,
		metadata.marker_col + #metadata.marker,
		{}
	)
	if cursor[1] - 1 == metadata.row and cursor[2] > metadata.marker_col then
		vim.api.nvim_win_set_cursor(0, { cursor[1], math.max(metadata.marker_col, cursor[2] - #metadata.marker) })
	end

	return true
end

source.execute = function(self, completion_item, callback)
	self:_finalize_completion(completion_item)
	callback(completion_item)
end

source._register_completion_backend = function(_, name, backend)
	vim.fn["skkeleton#register_completion_backend"](name, backend)
end

source._defer_completion_backend_registration = function(_, callback)
	vim.api.nvim_create_autocmd("User", {
		pattern = "skkeleton-initialize-pre",
		once = true,
		callback = callback,
	})
end

source.setup = function(self, cmp, schedule)
	schedule = schedule or vim.schedule
	local backend = {
		complete_info = function()
			local visible = cmp.visible()
			return {
				pum_visible = visible,
				selected = visible and cmp.get_active_entry() ~= nil and 0 or -1,
			}
		end,
		confirm_key = "<Cmd>lua require('cmp').confirm({ select = true })",
	}
	local function register_backend()
		return pcall(self._register_completion_backend, self, "nvim-cmp", backend)
	end
	if not register_backend() then
		self:_defer_completion_backend_registration(function()
			local ok, err = register_backend()
			if not ok then
				vim.notify("cmp-skkeleton: failed to register nvim-cmp backend: " .. tostring(err), vim.log.levels.WARN)
			end
		end)
	end

	cmp.event:on("complete_done", function(event)
		local entry = event and event.entry
		if not entry or not entry.source or entry.source.name ~= "skkeleton" then
			return
		end
		local completion_item = entry.completion_item
		schedule(function()
			self:_finalize_completion(completion_item)
		end)
	end)
end

source._get_pre_edit_length = function(_)
	return vim.fn["denops#request"]("skkeleton", "getPreEditLength", {})
end

source._get_pre_edit = function(_)
	return vim.fn["denops#request"]("skkeleton", "getPreEdit", {})
end

source._get_marker = function(_)
	local config = vim.fn["denops#request"]("skkeleton", "getConfig", {})
	return config.markerHenkan
end

source._get_prefix = function(_)
	return vim.fn["denops#request"]("skkeleton", "getPrefix", {})
end

source._get_completion_result = function(_)
	return vim.fn["denops#request"]("skkeleton", "getCompletionResult", {})
end

source._get_ranks = function(_)
	return vim.fn["denops#request"]("skkeleton", "getRanks", {})
end

source._get_okuri_candidates = function(_)
	local okuri_module = require("cmp_skkeleton.okuri")

	-- abbrevモードでは無効化
	local mode = vim.g["skkeleton#mode"]
	if mode == "abbrev" then
		return {}
	end

	-- 現在の入力を取得
	local ok_prefix, prefix = pcall(vim.fn["denops#request"], "skkeleton", "getPrefix", {})
	if not ok_prefix or not prefix or prefix == "" then
		return {}
	end

	-- 2文字未満は早期リターン（送り仮名分割に最低2文字必要）
	if vim.fn.strchars(prefix) < 2 then
		return {}
	end

	local splits = okuri_module.okuri_splits(prefix)
	local candidates = {}

	for _, split in ipairs(splits) do
		local word, okuri = split[1], split[2]
		local midasi = okuri_module.get_okuri_str(word, okuri)

		-- エラーハンドリング付きで候補取得
		local ok, cands = pcall(vim.fn["denops#request"], "skkeleton", "getCandidates", { midasi, "okuriari" })

		if ok and cands and type(cands) == "table" then
			for _, cand in ipairs(cands) do
				local label = string.gsub(cand, [[;.*$]], "")
				table.insert(candidates, {
					word = label .. okuri,
					kana = prefix,
					midasi = midasi,
					okuri = okuri,
					raw_cand = cand,
				})
			end
		end
	end

	return candidates
end

source._complete_callback = function(_, midasi, word, completion_type, inserted)
	return vim.fn["denops#request"]("skkeleton", "completeCallback", { midasi, word, completion_type, inserted })
end

source._get_rank_file_path = function(_)
	local config = vim.fn["denops#request"]("skkeleton", "getConfig", {})
	return config.completionRankFile
end

source._get_user_dictionary_path = function(_)
	local config = vim.fn["denops#request"]("skkeleton", "getConfig", {})
	return config.userDictionary
end

-- ユーザー辞書から候補を削除する
-- 注: skkeletonには内部的にpurgeCandidate関数があるが、denops#requestで
-- 外部から呼び出せるAPIとして公開されていないため、辞書ファイルを直接編集する
source.remove_from_user_dictionary = function(self, kana, candidate)
	local dict_file = self:_get_user_dictionary_path()
	if not dict_file or dict_file == "" then
		vim.notify("userDictionary is not configured", vim.log.levels.WARN)
		return false
	end

	-- ユーザー辞書を読み込み
	local file = io.open(dict_file, "r")
	if not file then
		vim.notify("Failed to open user dictionary: " .. dict_file, vim.log.levels.ERROR)
		return false
	end

	local lines = {}
	local removed = false
	for line in file:lines() do
		-- SKK辞書形式: "読み /候補1/候補2/候補3/"
		local line_kana = line:match("^(%S+)%s")
		if line_kana == kana then
			-- この行から候補を削除
			local new_line = line:gsub("/" .. vim.pesc(candidate) .. "/", "/")
			-- 候補が空になったら行自体を削除
			if new_line:match("^%S+%s+/$") then
				removed = true
				-- 行を追加しない（削除）
			elseif new_line ~= line then
				removed = true
				table.insert(lines, new_line)
			else
				table.insert(lines, line)
			end
		else
			table.insert(lines, line)
		end
	end
	file:close()

	if not removed then
		return false
	end

	-- ユーザー辞書を書き戻し
	file = io.open(dict_file, "w")
	if not file then
		vim.notify("Failed to write user dictionary: " .. dict_file, vim.log.levels.ERROR)
		return false
	end

	file:write(table.concat(lines, "\n"))
	if #lines > 0 then
		file:write("\n")
	end
	file:close()

	return true
end

source.remove_from_rank = function(self, candidate)
	local rank_file = self:_get_rank_file_path()
	if not rank_file or rank_file == "" then
		vim.notify("completionRankFile is not configured", vim.log.levels.WARN)
		return false
	end

	-- ランクファイルを読み込み
	local file = io.open(rank_file, "r")
	if not file then
		vim.notify("Failed to open rank file: " .. rank_file, vim.log.levels.ERROR)
		return false
	end

	local content = file:read("*a")
	file:close()

	-- JSONをパース
	local ok, ranks = pcall(vim.json.decode, content)
	if not ok or type(ranks) ~= "table" then
		vim.notify("Failed to parse rank file", vim.log.levels.ERROR)
		return false
	end

	-- 候補を配列から削除
	local new_ranks = {}
	local removed = false
	for _, rank in ipairs(ranks) do
		if rank ~= candidate then
			table.insert(new_ranks, rank)
		else
			removed = true
		end
	end

	if not removed then
		-- ランクファイルに候補がないことは削除の失敗ではない
		-- 辞書からの削除を妨げないため、trueを返す
		return true
	end

	-- ランクファイルを書き戻し
	file = io.open(rank_file, "w")
	if not file then
		vim.notify("Failed to write rank file: " .. rank_file, vim.log.levels.ERROR)
		return false
	end

	file:write(vim.json.encode(new_ranks))
	file:close()

	return true
end

local M = {}

M.new = function()
	return source.new()
end

M.remove_from_rank = function(candidate)
	return source:remove_from_rank(candidate)
end

M.remove_from_user_dictionary = function(kana, candidate)
	return source:remove_from_user_dictionary(kana, candidate)
end

-- ランクとユーザー辞書の両方から削除
M.purge_candidate = function(kana, candidate)
	local okuri_module = require("cmp_skkeleton.okuri")
	local splits = okuri_module.okuri_splits(kana)

	-- 送りあり候補の場合
	if #splits > 0 then
		for _, split in ipairs(splits) do
			local word, okuri = split[1], split[2]
			local midasi = okuri_module.get_okuri_str(word, okuri)

			-- 候補から送り仮名を除去
			local okuri_len = vim.fn.strchars(okuri)
			local cand_len = vim.fn.strchars(candidate)
			local candidate_without_okuri = vim.fn.strcharpart(candidate, 0, cand_len - okuri_len)

			local dict_removed = source:remove_from_user_dictionary(midasi, candidate_without_okuri)
			if dict_removed then
				source:remove_from_rank(candidate)
				vim.notify("Purged okuriari: " .. candidate, vim.log.levels.INFO)
				return true
			end
		end
	end

	-- 既存の送りなし処理
	local rank_removed = source:remove_from_rank(candidate)
	local dict_removed = source:remove_from_user_dictionary(kana, candidate)

	if rank_removed and dict_removed then
		vim.notify("Purged from rank and dictionary: " .. candidate, vim.log.levels.INFO)
	elseif rank_removed then
		vim.notify("Removed from rank: " .. candidate, vim.log.levels.INFO)
	elseif dict_removed then
		vim.notify("Removed from dictionary: " .. candidate, vim.log.levels.INFO)
	else
		vim.notify("Not found: " .. candidate, vim.log.levels.INFO)
	end

	return rank_removed or dict_removed
end

return M
