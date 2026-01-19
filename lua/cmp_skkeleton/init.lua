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

	for _, cs in pairs(candidates) do
		local kana = cs[1]

		for _, c in pairs(cs[2]) do
			local label = string.gsub(c, [[;.*$]], "")
			-- 重複チェック
			if not added_labels[label] then
				added_labels[label] = true

				-- ランク情報から基本優先度を取得
				local base_rank = rank_map[label] or 9999

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

				local sort_text = string.format("%05d_%s", normalized_rank, label)
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
	self:_register_henkan_result(kana, word)

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

source._register_henkan_result = function(_, kana, word)
	return vim.fn["denops#request"]("skkeleton", "registerHenkanResult", { kana, word })
end

return source

