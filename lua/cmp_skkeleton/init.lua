local source = {}

source.new = function()
	return setmetatable({}, { __index = source })
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
		return [[\%([ぁ-ゖ]\+\)]]
	end
end

source.complete = function(self, request, callback)
	local candidates = self:_get_completion_result()

	local preeditlen = self:_get_pre_edit_length()
	local ranks = self:_get_ranks()

	-- 送りあり候補を取得
	local okuri_candidates = self:_get_okuri_candidates()

	-- ランク情報をタイムスタンプで降順ソート（新しい選択が上位に）
	table.sort(ranks, function(a, b)
		return a[2] > b[2]
	end)

	-- ランクマップ生成
	local rank_map = {}
	for i, rank_entry in ipairs(ranks) do
		rank_map[rank_entry[1]] = i - 1 -- 0ベースのインデックス
	end

	local items = {}
	local added_labels = {} -- 重複排除用
	local cnt = 0

	local function get_base_kana_length(candidates)
		local min_length = math.huge
		for _, cs in pairs(candidates) do
			local kana_length = vim.fn.strchars(cs[1])
			min_length = math.min(min_length, kana_length)
		end
		return min_length
	end
	local base_kana_length = get_base_kana_length(candidates)

	-- ユーザー辞書ではない候補の優先度を保持するためのインデックス
	-- 例: SKK_JISYO.Lの以下の順番を保持する
	-- かんとう /関東/巻頭/完投/竿頭/敢闘/間道;舶来の織物/竿灯/完答/冠頭/
	-- https://github.com/happy663/dotfiles/issues/196
	local idx = 0

	-- 送りなし候補の処理
	for _, cs in pairs(candidates) do
		local kana = cs[1]

		for _, c in pairs(cs[2]) do
			local label = string.gsub(c, [[;.*$]], "")
			-- 重複チェック
			if not added_labels[label] then
				added_labels[label] = true

				-- ランク情報から基本優先度を取得
				local base_rank = rank_map[label] or 9999
				idx = idx + 1

				-- 読みの長さを考慮したスマートランク計算
				local actual_kana_length = vim.fn.strchars(kana) -- 実際の読みの文字数
				local input_kana_length = base_kana_length -- 入力された読みの文字数
				local rank

				if actual_kana_length == input_kana_length then
					rank = base_rank - 500 -- 読み完全一致ボーナス
				elseif actual_kana_length == input_kana_length + 1 then
					rank = base_rank - 100 -- 読み1文字差ボーナス
				else
					rank = base_rank + (actual_kana_length - input_kana_length) * 200 -- 長い読みペナルティ
				end
				-- - 補間: rank=-200 → normalized=9800 → "09800_補間"
				-- - 補完: rank=-199 → normalized=9801 → "09801_補完"
				-- - 保管: rank=-196 → normalized=9804 → "09804_保管"
				local normalized_rank = rank + 10000 -- マイナス値を避けるためにオフセットを追加

				-- print(
				-- 	string.format(
				-- 		"Processing: %s, Kana: %s(%d), input_kana_length: %d, base_rank: %d, rank: %d, normalized_rank: %d",
				-- 		label,
				-- 		kana,
				-- 		actual_kana_length,
				-- 		input_kana_length,
				-- 		base_rank,
				-- 		rank,
				-- 		normalized_rank
				-- 	)
				-- )

				local sort_text = string.format("%05d_%05d_%s", normalized_rank, idx, label) -- ランク、インデックス、ラベルでソート
				local item = {
					label = label,
					word = label,
					filterText = kana,
					sortText = sort_text,
				}

				-- print(string.format("  -> sortText: %s", sort_text))

				local document = string.match(c, [[;.*$]])
				if document then
					item.documentation = kana .. "\n" .. string.gsub(document, [[^;]], "")
				else
					item.documentation = kana
				end

				cnt = cnt + 1
				table.insert(items, item)
			end
		end
	end

	-- 送りあり候補の処理
	for index, okuri_item in ipairs(okuri_candidates) do
		local label = okuri_item.word
		if not added_labels[label] then
			added_labels[label] = true

			local base_rank = rank_map[label] or 9999
			local rank = base_rank + 500 -- 送りありペナルティ
			local normalized_rank = rank + 10000

			local sort_text = string.format("%05d_%05d_%s", normalized_rank, index, label) -- ランク、インデックス、ラベルでソート

			local item = {
				label = label,
				word = label,
				filterText = okuri_item.kana,
				sortText = sort_text,
				documentation = okuri_item.kana,
				data = {
					midasi = okuri_item.midasi,
					okuri = okuri_item.okuri,
					okuriari = true,
				},
			}

			cnt = cnt + 1
			table.insert(items, item)
		end
	end

	if cnt == 0 then
		callback()
		return
	end

	callback({
		items = items,
		isIncomplete = true,
	})
end

source.resolve = function(self, completion_item, callback)
	callback(completion_item)
end

source.execute = function(self, completion_item, callback)
	local kana = completion_item.filterText
	local word = completion_item.label

	-- 送りあり候補の場合
	if completion_item.data and completion_item.data.okuriari then
		local midasi = completion_item.data.midasi
		-- 送り仮名を除いた候補本体を取得
		local okuri = completion_item.data.okuri
		local okuri_len = vim.fn.strchars(okuri)
		local word_len = vim.fn.strchars(word)
		local word_without_okuri = vim.fn.strcharpart(word, 0, word_len - okuri_len)

		vim.fn["denops#request"]("skkeleton", "completeCallback", { midasi, word_without_okuri, "okuriari" })
	else
		-- 既存: 送りなし処理
		self:_register_henkan_result(kana, word)
	end

	callback(completion_item)
end

source._get_pre_edit_length = function(_)
	return vim.fn["denops#request"]("skkeleton", "getPreEditLength", {})
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

source._register_henkan_result = function(_, kana, word)
	return vim.fn["denops#request"]("skkeleton", "registerHenkanResult", { kana, word })
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
