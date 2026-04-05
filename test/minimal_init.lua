local plenary_path = os.getenv("PLENARY_PATH") or (os.getenv("HOME") .. "/.local/share/nvim/lazy/plenary.nvim")
local plugin_path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")

vim.opt.runtimepath:append(plenary_path)
vim.opt.runtimepath:append(plugin_path)
