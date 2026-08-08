-- PARI/GP filetype settings.
--
-- Neovim already ships syntax/gp.vim (highlighting works out of the box), but
-- there is no ftplugin, no treesitter grammar, and no LSP for GP -- none exist
-- upstream. This fills the gaps that actually matter day to day.

-- GP line comments are \\ , block comments are /* */.
-- Without this, gcc / gc do nothing in .gp files.
vim.bo.commentstring = "\\\\ %s"
vim.bo.comments = "s1:/*,mb:*,ex:*/,:\\\\"

-- K on a function name opens its real PARI documentation, the same way K opens
-- a man page in C. gphelp ships with the pari package.
vim.bo.keywordprg = "gphelp -detex"

-- GP indents with tabs in the upstream examples.
vim.bo.expandtab = false
vim.bo.shiftwidth = 8
vim.bo.tabstop = 8

-- <leader>r writes the buffer and runs it through gp in a terminal split.
-- Buffer-local, so it only exists inside .gp files and cannot collide with
-- LazyVim's global mappings elsewhere.
vim.keymap.set("n", "<leader>r", function()
  vim.cmd("write")
  local file = vim.fn.shellescape(vim.fn.expand("%:p"))
  vim.cmd("botright split | resize 15 | terminal gp -q " .. file)
  vim.cmd("startinsert")
end, { buffer = true, desc = "Run this GP file" })

-- <leader>R does the same but opens an interactive gp session with the file
-- already loaded, so you can poke at variables after it finishes.
vim.keymap.set("n", "<leader>R", function()
  vim.cmd("write")
  local file = vim.fn.shellescape(vim.fn.expand("%:p"))
  vim.cmd("botright split | resize 15 | terminal gp " .. file)
  vim.cmd("startinsert")
end, { buffer = true, desc = "Load this GP file into an interactive gp session" })
