-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua

vim.keymap.set("i", "jj", "<Esc>", { desc = "Exit insert mode" })

vim.api.nvim_create_user_command("Brd", function()
  local src = vim.fn.expand("%:p")
  local bin = vim.fn.expand("%:p:r")
  vim.cmd(string.format(
    "split | terminal g++ %s -o %s && %s; rm -f %s",
    src, bin, bin, bin
  ))
end, {})
