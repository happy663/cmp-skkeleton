local source = require("cmp_skkeleton")

local function make_cmp()
	local handlers = {}
	local state = {
		visible = false,
		active_entry = nil,
	}
	local cmp = {
		event = {
			on = function(_, event, callback)
				handlers[event] = callback
			end,
		},
		visible = function()
			return state.visible
		end,
		get_active_entry = function()
			return state.active_entry
		end,
	}
	return cmp, handlers, state
end

describe("nvim-cmp integration", function()
	it("registers a backend that reports menu and selection state", function()
		local cmp, _, state = make_cmp()
		local registered_name
		local registered_backend
		local s = source.new()
		s._register_completion_backend = function(_, name, backend)
			registered_name = name
			registered_backend = backend
		end

		s:setup(cmp, function(callback)
			callback()
		end)

		assert.equals("nvim-cmp", registered_name)
		assert.equals("<Cmd>lua require('cmp').confirm({ select = true })", registered_backend.confirm_key)
		assert.same({ pum_visible = false, selected = -1 }, registered_backend.complete_info())

		state.visible = true
		assert.same({ pum_visible = true, selected = -1 }, registered_backend.complete_info())

		state.active_entry = {}
		assert.same({ pum_visible = true, selected = 0 }, registered_backend.complete_info())
	end)

	it("defers backend registration until skkeleton becomes available", function()
		local cmp = make_cmp()
		local available = false
		local deferred
		local registered_name
		local s = source.new()
		s._register_completion_backend = function(_, name)
			if not available then
				error("E117: Unknown function")
			end
			registered_name = name
		end
		s._defer_completion_backend_registration = function(_, callback)
			deferred = callback
		end

		assert.has_no.errors(function()
			s:setup(cmp, function(callback)
				callback()
			end)
		end)
		assert.is_function(deferred)
		assert.is_nil(registered_name)

		available = true
		deferred()
		assert.equals("nvim-cmp", registered_name)
	end)

	it("finalizes only selected skkeleton entries on complete_done", function()
		local cmp, handlers = make_cmp()
		local finalized
		local s = source.new()
		s._register_completion_backend = function() end
		s._finalize_completion = function(_, item)
			finalized = item
		end
		s:setup(cmp, function(callback)
			callback()
		end)

		local item = { label = "アップル" }
		handlers.complete_done({
			entry = {
				source = { name = "buffer" },
				completion_item = item,
			},
		})
		assert.is_nil(finalized)

		handlers.complete_done({
			entry = {
				source = { name = "skkeleton" },
				completion_item = item,
			},
		})
		assert.equals(item, finalized)
	end)

	it("ignores complete_done without a selected entry", function()
		local cmp, handlers = make_cmp()
		local called = false
		local s = source.new()
		s._register_completion_backend = function() end
		s._finalize_completion = function()
			called = true
		end
		s:setup(cmp, function(callback)
			callback()
		end)

		handlers.complete_done({ entry = nil })
		assert.is_false(called)
	end)
end)
