-- Lint .gp files with gp2c, the same way conform handles formatting in
-- gp-format.lua. gp2c is PARI's GP-to-C translator and the only static
-- analyser GP has: `gp2c -W` reports syntax errors and undeclared-variable /
-- unknown-prototype warnings without executing the script, which matters
-- because the alternative (running the file through `gp`) would execute
-- arbitrary, possibly very long, number-theory code on every save.
--
-- gp2c is not in the Arch repos; install the AUR package `gp2c`
-- (`paru -S gp2c`). Until then require("gp.lint").linter.condition returns
-- false and LazyVim's lint autocmd skips the linter entirely, so nothing is
-- reported and nothing errors.
--
-- Diagnostics use nvim-lint's own "gp2c" namespace and source = "gp2c", which
-- keeps them clear of the gpfmt diagnostics (source = "gpfmt", own namespace).
return {
  "mfussenegger/nvim-lint",
  opts = {
    -- LazyVim extension: entries here are merged into require("lint").linters.
    linters = {
      gp2c = require("gp.lint").linter,
    },
    linters_by_ft = {
      gp = { "gp2c" },
    },
  },
}
