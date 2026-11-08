-- Indent script for PARI/GP.
--
-- Lives in indent/ rather than ftplugin/ per $VIMRUNTIME/indent/README.txt:
-- indent scripts are a separate subsystem with their own `:filetype indent`
-- switch, their own b:did_indent guard, and their own b:undo_indent.
-- Putting indentexpr in an ftplugin ignores `:filetype indent off`.

if vim.b.did_indent then
  return
end
vim.b.did_indent = true

vim.bo.autoindent = true          -- indentexpr is not much help without it
vim.bo.smartindent = false        -- brace-only; superseded by indentexpr
vim.bo.indentexpr = "v:lua.require'gp.indent'.indentexpr()"
vim.bo.indentkeys = "0),0],0},!^F,o,O,e"

vim.b.undo_indent = "setl ai< si< inde< indk<"
