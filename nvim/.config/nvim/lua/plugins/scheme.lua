-- Scheme (strict R5RS) for class work.
--   lint:   scripts/r5rs-lint.rkt — expands the buffer as R5RS without running it
--   format: raco fmt, manual only (<leader>cf); autoformat on save is off (needs: raco pkg install fmt)
--   run:    <localleader>x → plt-r5rs on the current file
--   REPL:   Conjure, backed by plt-r5rs (<localleader>ee eval form, <localleader>lv log)
local lint_script = vim.fn.stdpath("config") .. "/scripts/r5rs-lint.rkt"

vim.g["conjure#filetypes"] = { "scheme" }
vim.g["conjure#filetype#scheme"] = "conjure.client.scheme.stdio"
vim.g["conjure#client#scheme#stdio#command"] = "plt-r5rs"
vim.g["conjure#client#scheme#stdio#prompt_pattern"] = "> $"
-- Conjure's scheme client assumes MIT Scheme (";Value: 25"); plt-r5rs prints bare values
vim.g["conjure#client#scheme#stdio#value_prefix_pattern"] = false
vim.g["conjure#client#scheme#stdio#enable_completions"] = false

-- Conjure doesn't kill its REPL when nvim quits; an orphaned plt-r5rs then spins at 100% CPU.
vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    vim.fn.system({ "pkill", "-P", tostring(vim.fn.getpid()), "-f", "r5rs/run.rkt" })
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = "scheme",
  callback = function(ev)
    vim.b[ev.buf].autoformat = false
    vim.keymap.set("n", "<localleader>x", function()
      vim.cmd("write")
      Snacks.terminal({ "plt-r5rs", vim.api.nvim_buf_get_name(ev.buf) }, { interactive = false, auto_close = false })
    end, { buffer = ev.buf, desc = "Run file (plt-r5rs)" })
  end,
})

return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "scheme" } },
  },

  {
    "mfussenegger/nvim-lint",
    opts = {
      linters_by_ft = { scheme = { "r5rs" } },
      linters = {
        r5rs = {
          cmd = "racket",
          stdin = true,
          args = { lint_script, "stdin.scm" },
          stream = "stdout",
          ignore_exitcode = true,
          parser = function(output, bufnr)
            local diagnostics = {}
            for line in vim.gsplit(output, "\n", { trimempty = true }) do
              local lnum, col, sev, msg = line:match("^(%d+):(%d+):(%a+):(.*)$")
              if lnum then
                table.insert(diagnostics, {
                  bufnr = bufnr,
                  lnum = tonumber(lnum) - 1,
                  col = tonumber(col),
                  severity = sev == "warning" and vim.diagnostic.severity.WARN or vim.diagnostic.severity.ERROR,
                  source = "r5rs",
                  message = msg,
                })
              end
            end
            return diagnostics
          end,
        },
      },
    },
  },

  {
    "stevearc/conform.nvim",
    opts = { formatters_by_ft = { scheme = { "racketfmt" } } },
  },

  { "HiPhish/rainbow-delimiters.nvim", event = "LazyFile" },

  { "Olical/conjure", ft = { "scheme" } },
}
