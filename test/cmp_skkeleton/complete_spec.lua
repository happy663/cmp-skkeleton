local source = require("cmp_skkeleton")

-- ヘルパー: モック済みインスタンスを生成
local function make_source(opts)
	local s = source.new()
	s._get_completion_result = function(_)
		return opts.candidates or {}
	end
	s._get_pre_edit_length = function(_)
		return opts.preedit_len or 0
	end
	s._get_ranks = function(_)
		return opts.ranks or {}
	end
	s._get_okuri_candidates = function(_)
		return opts.okuri or {}
	end
	return s
end

-- ヘルパー: callbackの結果を取り出す
local function collect(s, request)
	local result
	s:complete(request or {}, function(r)
		result = r
	end)
	return result
end

describe("source.complete", function()
	-- (a) 単一候補の基本動作
	it("returns correct fields for a single candidate", function()
		local s = make_source({
			candidates = { { "ほかん", { "補完" } } },
			preedit_len = 3,
			ranks = { { "補完", 1000 } },
		})
		local result = collect(s)
		assert.is_not_nil(result)
		assert.equals(1, #result.items)

		local item = result.items[1]
		assert.equals("補完", item.label)
		assert.equals("ほかん", item.filterText)
		assert.equals("ほかん", item.documentation)
		-- sortText形式: "%05d_%05d_%s"
		assert.is_truthy(item.sortText:match("^%d+_%d+_補完$"))
	end)

	-- (b) 複数候補のランク順序
	it("sorts by rank_map index (0-based)", function()
		local s = make_source({
			candidates = {
				{ "かんとう", { "関東", "巻頭", "完投" } },
			},
			preedit_len = 4,
			ranks = {
				-- 古い順に並べている。complete内で降順ソートされるため、
				-- 実際の rank_map は逆順: 完投=0(最優先), 関東=1, 巻頭=2
				{ "巻頭", 100 }, -- 最古 → 降順ソート後 index=2 → rank_map=2 → 下位
				{ "関東", 300 }, --       → 降順ソート後 index=1 → rank_map=1
				{ "完投", 500 }, -- 最新 → 降順ソート後 index=0 → rank_map=0 → 最優先
			},
		})
		local result = collect(s)
		-- sortText昇順で並べると、rank_map=0の完投が先頭に来る
		table.sort(result.items, function(a, b)
			return a.sortText < b.sortText
		end)
		assert.equals("完投", result.items[1].label)
		assert.equals("関東", result.items[2].label)
		assert.equals("巻頭", result.items[3].label)
	end)

	-- (c) 読み長さ違いのスマートランク
	it("applies smart rank: exact=-500, +1char=-100, longer=penalty", function()
		-- base_kana_length = min(5,6,8) = 5 (= "とうきょう")
		-- "とうきょう"(5文字)      -> exact match -> rank = base_rank - 500
		-- "とうきょうと"(6文字)    -> +1          -> rank = base_rank - 100
		-- "とうきょうとない"(8文字) -> +3          -> rank = base_rank + 3*200
		local s = make_source({
			candidates = {
				{ "とうきょう", { "東京" } },
				{ "とうきょうと", { "東京都" } },
				{ "とうきょうとない", { "東京都内" } },
			},
			preedit_len = 5,
			ranks = {}, -- 全てbase_rank=9999
		})
		local result = collect(s)
		table.sort(result.items, function(a, b)
			return a.sortText < b.sortText
		end)
		-- exact(9999-500=9499) < +1(9999-100=9899) < +3(9999+600=10599)
		assert.equals("東京", result.items[1].label)
		assert.equals("東京都", result.items[2].label)
		assert.equals("東京都内", result.items[3].label)
	end)

	-- (d-1) 異なるkanaエントリ間の重複ラベル除外
	it("deduplicates items with the same label across kana entries", function()
		local s = make_source({
			candidates = {
				{ "にほん", { "日本", "二本" } },
				{ "にほんご", { "日本語", "日本" } }, -- "日本" が再度出現
			},
			preedit_len = 3,
			ranks = {},
		})
		local result = collect(s)
		-- "日本" は1件のみ
		local count = 0
		for _, item in ipairs(result.items) do
			if item.label == "日本" then
				count = count + 1
			end
		end
		assert.equals(1, count)
	end)

	-- (d-2) 同一kanaエントリのvalue配列内での重複ラベル除外
	it("deduplicates items with the same label within a kana entry", function()
		local s = make_source({
			candidates = {
				{ "にほん", { "日本", "日本" } }, -- 同じkanaエントリ内で重複
			},
			preedit_len = 3,
			ranks = {},
		})
		local result = collect(s)
		assert.equals(1, #result.items)
		assert.equals("日本", result.items[1].label)
	end)

	-- (e) アノテーション付きdocumentation
	it("includes annotation in documentation after semicolon", function()
		local s = make_source({
			candidates = { { "かんどう", { "間道;舶来の織物" } } },
			preedit_len = 4,
			ranks = {},
		})
		local result = collect(s)
		local item = result.items[1]
		assert.equals("間道", item.label)
		assert.equals("かんどう\n舶来の織物", item.documentation)
	end)

	-- (f) 空候補でcallbackが引数なし
	it("calls callback with no args when no candidates", function()
		local s = make_source({
			candidates = {},
			preedit_len = 0,
			ranks = {},
		})
		local called_with_nil = false
		s:complete({}, function(r)
			if r == nil then
				called_with_nil = true
			end
		end)
		assert.is_true(called_with_nil)
	end)

	-- (g) 送りあり候補
	it("handles okuri candidates with +500 penalty and data.okuriari", function()
		local s = make_source({
			candidates = {},
			preedit_len = 0,
			ranks = {},
			okuri = {
				{ word = "動く", kana = "うごく", midasi = "うごk", okuri = "く" },
			},
		})
		local result = collect(s)
		assert.equals(1, #result.items)

		local item = result.items[1]
		assert.equals("動く", item.label)
		assert.equals("うごく", item.filterText)
		assert.is_true(item.data.okuriari)
		assert.equals("うごk", item.data.midasi)
		-- sortTextにpenalty(9999+500=10499, normalized=20499)が反映されている
		assert.is_truthy(item.sortText:match("^20499_"))
	end)

	-- (h) ranksのソート検証（値が大きいほど新しい → 降順ソート → rank_map順序）
	it("sorts ranks by value descending to build rank_map", function()
		local s = make_source({
			candidates = { { "てすと", { "テスト", "試験" } } },
			preedit_len = 3,
			ranks = {
				-- 古い順に並べている。complete内で降順ソートされるため逆順になる
				{ "試験", 500 }, -- 古い → 降順ソート後 index=1 → rank_map=1 → 下位
				{ "テスト", 1000 }, -- 新しい → 降順ソート後 index=0 → rank_map=0 → 最優先
			},
		})
		local result = collect(s)
		table.sort(result.items, function(a, b)
			return a.sortText < b.sortText
		end)
		-- テスト(rank_map=0) が 試験(rank_map=1) より前
		assert.equals("テスト", result.items[1].label)
		assert.equals("試験", result.items[2].label)
	end)
end)
