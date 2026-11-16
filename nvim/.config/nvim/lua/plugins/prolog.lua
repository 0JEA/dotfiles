-- Prolog (SWI-Prolog) for class work.
--   LSP:    lsp_server pack (diagnostics, hover, go-to-def, completion)
--           needs: swipl -g "pack_install(lsp_server,[interactive(false)])" -t halt
--   run:    <localleader>x → load the current file into an interactive swipl prompt
--   syntax: Vim's built-in regex highlighting (nvim-treesitter has no prolog parser)
--   format: none; autoformat off

-- .pl is Perl by default
vim.g.filetype_pl = "prolog"

vim.api.nvim_create_autocmd("FileType", {
  pattern = "prolog",
  callback = function(ev)
    vim.b[ev.buf].autoformat = false
    vim.bo[ev.buf].commentstring = "% %s"
    vim.keymap.set("n", "<localleader>x", function()
      vim.cmd("write")
      Snacks.terminal({ "swipl", vim.api.nvim_buf_get_name(ev.buf) }, { auto_close = true })
    end, { buffer = ev.buf, desc = "Load file in swipl" })
  end,
})

return {
  {
    "neovim/nvim-lspconfig",
    opts = { servers = { prolog_ls = { mason = false } } },
  },
}
