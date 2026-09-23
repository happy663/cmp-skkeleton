local source = require("cmp_skkeleton")

local function completion_item(overrides)
	local metadata = {
		id = "completion-1",
		bufnr = vim.api.nvim_get_current_buf(),
		row = 0,
		marker_col = 0,
		marker = "▽",
		midasi = "apple",
		word = "アップル",
		type = "okurinasi",
		inserted = "アップル",
	}

	for key, value in pairs(overrides or {}) do
		metadata[key] = value
	end

	return {
		label = metadata.inserted,
		filterText = metadata.midasi,
		data = { cmp_skkeleton = metadata },
	}
end

describe("completion finalization", function()
	before_each(function()
		vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
	end)

	it("removes only the marker recorded for the selected completion", function()
		local prefix = "▽既存 "
		local line = prefix .. "▽アップルを入力"
		vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })

		local calls = {}
		local s = source.new()
		s._complete_callback = function(_, midasi, word, completion_type, inserted)
			table.insert(calls, { midasi, word, completion_type, inserted })
		end

		local finalized = s:_finalize_completion(completion_item({ marker_col = #prefix }))

		assert.is_true(finalized)
		assert.equals(prefix .. "アップルを入力", vim.api.nvim_get_current_line())
		assert.same({ { "apple", "アップル", "okurinasi", "アップル" } }, calls)
	end)

	it("finalizes the same completion only once", function()
		vim.api.nvim_buf_set_lines(0, 0, -1, false, { "▽アップル" })

		local call_count = 0
		local s = source.new()
		s._complete_callback = function()
			call_count = call_count + 1
		end
		local item = completion_item()

		assert.is_true(s:_finalize_completion(item))
		assert.is_false(s:_finalize_completion(item))
		assert.equals(1, call_count)
		assert.equals("アップル", vim.api.nvim_get_current_line())
	end)

	it("does not finalize stale metadata pointing at another marker", function()
		vim.api.nvim_buf_set_lines(0, 0, -1, false, { "▽別候補" })

		local called = false
		local s = source.new()
		s._complete_callback = function()
			called = true
		end

		assert.is_false(s:_finalize_completion(completion_item()))
		assert.is_false(called)
		assert.equals("▽別候補", vim.api.nvim_get_current_line())
	end)

	it("keeps the marker retryable when completeCallback fails", function()
		vim.api.nvim_buf_set_lines(0, 0, -1, false, { "▽アップル" })

		local attempts = 0
		local s = source.new()
		s._complete_callback = function()
			attempts = attempts + 1
			if attempts == 1 then
				error("denops unavailable")
			end
		end
		local item = completion_item()

		assert.is_false(s:_finalize_completion(item))
		assert.equals("▽アップル", vim.api.nvim_get_current_line())
		assert.is_true(s:_finalize_completion(item))
		assert.equals("アップル", vim.api.nvim_get_current_line())
		assert.equals(2, attempts)
	end)

	it("notifies skkeleton when markerHenkan is empty", function()
		vim.api.nvim_buf_set_lines(0, 0, -1, false, { "アップル" })

		local called = false
		local s = source.new()
		s._complete_callback = function()
			called = true
		end

		assert.is_true(s:_finalize_completion(completion_item({ marker = "" })))
		assert.is_true(called)
		assert.equals("アップル", vim.api.nvim_get_current_line())
	end)

	it("uses the shared finalizer from execute", function()
		local item = completion_item()
		local finalized_item
		local callback_item
		local s = source.new()
		s._finalize_completion = function(_, value)
			finalized_item = value
			return true
		end

		s:execute(item, function(value)
			callback_item = value
		end)

		assert.equals(item, finalized_item)
		assert.equals(item, callback_item)
	end)
end)
