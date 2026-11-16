-- Format .gp files on save with gpfmt (~/.local/bin/gpfmt), the same way
-- clang-format handles C/C++ here. gpfmt only ever changes whitespace, and it
-- re-tokenises its own output and refuses (non-zero exit, no stdout) if the
-- result would not be equivalent -- conform then leaves the buffer untouched.
return {
  "stevearc/conform.nvim",
  opts = {
    formatters = {
      gpfmt = {
        command = vim.fn.expand("~/.local/bin/gpfmt"),
        stdin = true,
        inherit = false,
        args = function(_, ctx)
          return {
            -- so gpfmt can find a .gpfmt / .editorconfig for this file
            "--stdin-filename", ctx.filename,
            -- a FALLBACK, not an override: a project's .gpfmt still wins over
            -- the buffer's shiftwidth, while an .editorconfig reaches us
            -- either way (Neovim applies it to the buffer after the ftplugin)
            "--indent-fallback", tostring(ctx.shiftwidth > 0 and ctx.shiftwidth or 2),
          }
        end,
      },
    },
    formatters_by_ft = {
      gp = { "gpfmt" },
    },
  },
}
