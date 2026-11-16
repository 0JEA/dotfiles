-- In Scheme, ' and ` are quote and quasiquote: prefix operators with no
-- closing partner. mini.pairs (LazyVim's autopair plugin) maps both globally
-- to insert a matched pair, which turns 'x into ''x. A buffer-local insert
-- mapping wins over the global one, so these type the single character.
-- Parens and double quotes still pair.
vim.keymap.set("i", "'", "'", { buffer = true, desc = "Scheme quote, unpaired" })
vim.keymap.set("i", "`", "`", { buffer = true, desc = "Scheme quasiquote, unpaired" })

vim.b.undo_ftplugin = (vim.b.undo_ftplugin or "")
  .. "\n silent! iunmap <buffer> '"
  .. "\n silent! iunmap <buffer> `"
