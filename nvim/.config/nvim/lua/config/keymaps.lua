-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua

vim.keymap.set("i", "jj", "<Esc>", { desc = "Exit insert mode" })

-- Jump over closing bracket/quote with Tab
vim.keymap.set("i", "<Tab>", function()
  local col = vim.fn.col(".")
  local char = vim.fn.getline("."):sub(col, col)
  if char:match("[%)%]%}'\"]") then
    return "<Right>"
  end
  return "<Tab>"
end, { expr = true, desc = "Jump over closing bracket or insert tab" })

local brd_buf = nil

vim.api.nvim_create_user_command("Brd", function()
  local dir = vim.fn.expand("%:p:h")
  local file = vim.fn.expand("%:t")
  local name = vim.fn.expand("%:t:r")
  local ext = vim.fn.expand("%:e")

  local cmd
  if vim.fn.filereadable(dir .. "/Makefile") == 1 then
    cmd = string.format("cd %s && make && ./main; make clean", dir)
  elseif ext == "c" then
    cmd = string.format("cd %s && gcc %s -o %s -lm && ./%s; rm -f %s", dir, file, name, name, name)
  elseif ext == "cpp" then
    cmd = string.format("cd %s && g++ %s -o %s && ./%s; rm -f %s", dir, file, name, name, name)
  elseif ext == "py" then
    cmd = string.format("cd %s && python3 %s", dir, file)
  elseif ext == "java" then
    cmd = string.format("cd %s && javac %s && java %s", dir, file, name)
  else
    vim.notify("Brd: unsupported file type '." .. ext .. "'", vim.log.levels.ERROR)
    return
  end

  if brd_buf and vim.api.nvim_buf_is_valid(brd_buf) then
    vim.api.nvim_buf_delete(brd_buf, { force = true })
  end

  vim.cmd(string.format("botright split | terminal bash -c '%s'", cmd))
  brd_buf = vim.api.nvim_get_current_buf()
  vim.cmd("startinsert")
end, {})
