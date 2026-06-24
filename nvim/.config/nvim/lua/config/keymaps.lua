-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua

vim.keymap.set("i", "jj", "<Esc>", { desc = "Exit insert mode" })

vim.api.nvim_create_user_command("Brd", function()
  local cwd = vim.fn.expand("%:p:h")
  local bin = "/tmp/" .. vim.fn.fnamemodify(cwd, ":t")
  vim.cmd(string.format(
    "split | terminal cd '%s' && g++ $(find . -name '*.cpp') -o '%s' && '%s'; rm -f '%s'",
    cwd, bin, bin, bin
  ))
end, {})
