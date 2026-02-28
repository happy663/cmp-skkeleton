-- 送り仮名処理ユーティリティモジュール
-- vim-skk/skkeleton の okuri.ts と okurisplits.ts から移植

local M = {}

-- 送り仮名テーブル: ひらがな→ローマ字マッピング
-- libskkなどの動作に準拠
M.okuri_table = {
	["ぁ"] = "x",
	["あ"] = "a",
	["ぃ"] = "x",
	["い"] = "i",
	["ぅ"] = "x",
	["う"] = "u",
	["ぇ"] = "x",
	["え"] = "e",
	["ぉ"] = "x",
	["お"] = "o",
	["か"] = "k",
	["が"] = "g",
	["き"] = "k",
	["ぎ"] = "g",
	["く"] = "k",
	["ぐ"] = "g",
	["け"] = "k",
	["げ"] = "g",
	["こ"] = "k",
	["ご"] = "g",
	["さ"] = "s",
	["ざ"] = "z",
	["し"] = "s",
	["じ"] = "j",
	["す"] = "s",
	["ず"] = "z",
	["せ"] = "s",
	["ぜ"] = "z",
	["そ"] = "s",
	["ぞ"] = "z",
	["た"] = "t",
	["だ"] = "d",
	["ち"] = "t",
	["ぢ"] = "d",
	["っ"] = "x",
	["つ"] = "t",
	["づ"] = "d",
	["て"] = "t",
	["で"] = "d",
	["と"] = "t",
	["ど"] = "d",
	["な"] = "n",
	["に"] = "n",
	["ぬ"] = "n",
	["ね"] = "n",
	["の"] = "n",
	["は"] = "h",
	["ば"] = "b",
	["ぱ"] = "p",
	["ひ"] = "h",
	["び"] = "b",
	["ぴ"] = "p",
	["ふ"] = "h",
	["ぶ"] = "b",
	["ぷ"] = "p",
	["へ"] = "h",
	["べ"] = "b",
	["ぺ"] = "p",
	["ほ"] = "h",
	["ぼ"] = "b",
	["ぽ"] = "p",
	["ま"] = "m",
	["み"] = "m",
	["む"] = "m",
	["め"] = "m",
	["も"] = "m",
	["ゃ"] = "x",
	["や"] = "y",
	["ゅ"] = "x",
	["ゆ"] = "y",
	["ょ"] = "x",
	["よ"] = "y",
	["ら"] = "r",
	["り"] = "r",
	["る"] = "r",
	["れ"] = "r",
	["ろ"] = "r",
	["ゎ"] = "x",
	["わ"] = "w",
	["ゐ"] = "x",
	["ゑ"] = "x",
	["を"] = "w",
	["ん"] = "n",
}

--- 送り仮名から辞書キーを生成
--- @param word string 読みの本体部分（例: "おく"）
--- @param okuri string 送り仮名部分（例: "る"）
--- @return string 辞書キー（例: "okur"）
function M.get_okuri_str(word, okuri)
	-- 「送っ」のような段階で変換する際は、タ行の入力がされているように振る舞う
	-- libskkなどはこの動作を行う
	-- 根拠として、促音のほとんどがタ行という調査結果が挙げられる
	-- https://blog.atusy.net/2023/08/01/skk-azik-and-sokuon-okuri/
	if okuri == "っ" then
		return word .. "t"
	end

	-- 促音以外の最初の文字を抽出
	local first_char = vim.fn.matchstr(okuri, "[^っ]")
	local alpha = M.okuri_table[first_char] or ""
	return word .. alpha
end

--- 入力を送り仮名候補パターンに分割
--- @param text string 入力文字列（例: "おくる"）
--- @return table[] 分割結果の配列（例: {{"おく", "る"}, {"おく", "る"}}）
function M.okuri_splits(text)
	if text == "" then
		return {}
	end

	-- UTF-8文字列を文字配列に変換
	local chars = {}
	for char in text:gmatch("[^\128-\191][\128-\191]*") do
		table.insert(chars, char)
	end

	local len = #chars
	if len < 2 then
		return {}
	end

	-- 後ろから1文字ずつ送り仮名として分割
	-- 例: "おくる" (3文字) -> {{"おく", "る"}, {"お", "くる"}}
	local results = {}
	for i = len - 1, 1, -1 do
		local word = table.concat(chars, "", 1, i)
		local okuri = table.concat(chars, "", i + 1, len)
		table.insert(results, { word, okuri })
	end

	return results
end

return M
