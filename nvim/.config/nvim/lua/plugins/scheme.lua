-- Scheme (R5RS) support: Conjure for in-editor evaluation, backed by Racket.
--
-- WHY RACKET
--
-- Racket's `#lang r5rs` is a conforming R5RS implementation: it provides the
-- R5RS bindings and nothing else, so code that runs under it is portable R5RS
-- rather than "whatever this Scheme happens to accept". Guile 3 (also on this
-- box) runs R5RS code but silently accepts its own extensions, which makes it
-- useless for proving a file is actually R5RS.
--
-- The `racket-minimal` package alone is NOT enough. It ships only `racket-lib`,
-- so `#lang r5rs` fails with "collection not found: r5rs/lang". The r5rs
-- collection and XREPL come from two Racket packages installed on top of it:
--
--   raco pkg install --auto -D r5rs-lib xrepl-lib
--
-- XREPL is what Conjure's Racket client uses for `K` documentation lookups
-- (`,doc <word>` in the REPL); evaluation works without it, docs do not.
--
-- WHY THE scheme FILETYPE IS REMAPPED
--
-- Conjure binds the `scheme` filetype to `conjure.client.mit-scheme.stdio` by
-- default, and MIT Scheme is not installed here (it is AUR-only). Opening a
-- .scm file would therefore try to spawn `mit-scheme` and fail. The override
-- below points .scm buffers at the Racket client instead, so both .scm and
-- .rkt evaluate through the same REPL.
--
-- Note that an R5RS file still needs `#lang r5rs` as its first line for Racket
-- to read it as R5RS rather than as Racket.
--
-- LINTING
--
-- racket-langserver drives DrRacket's public "Check Syntax" API, so its
-- diagnostics come from Racket's own expander rather than from a third-party
-- parser. That is what makes it an R5RS checker and not merely a Racket one:
-- the expander honours the `#lang r5rs` line, so a Racket-only identifier such
-- as `string-upcase` is reported as unbound in these files, exactly as it is
-- when the file is run.
--
-- It is installed through raco, NOT pacman, and nothing reminds you if it is
-- missing except an LSP that fails to start:
--
--   raco pkg install racket-langserver
--
-- nvim-lspconfig already ships the server definition (lsp/racket_langserver.lua)
-- and already lists `scheme` among its filetypes, so .scm files are covered
-- without remapping. Enabling it below is the whole integration.
--
-- Rejected alternatives: nvim-lint ships no Scheme/Lisp linter at all;
-- `scheme-langserver` (also in lspconfig) is Chez-based, targets R6RS/R7RS
-- rather than R5RS, and its own README warns of "many many bugs"; `raco review`
-- and `resyntax` are real Racket linters but have no nvim-lint entry, so each
-- would need hand-written glue.
--
-- MAPPINGS (localleader is "\" -- see lua/config/options.lua)
--
--   \ee   evaluate the form under the cursor
--   \er   evaluate the root (outermost) form under the cursor
--   \eb   evaluate the whole buffer
--   \ef   evaluate the file from disk
--   \E    evaluate the visual selection
--   \lg   toggle the result log
--   \ls   open the result log in a split
return {
  -- `racket` filetype detection, syntax and indent. Conjure's Racket quick
  -- start lists this as a prerequisite: without it .rkt files never get the
  -- filetype the Racket client is bound to.
  { "wlangstroth/vim-racket", ft = { "racket", "scheme" } },

  {
    "Olical/conjure",
    ft = { "scheme", "racket" },
    init = function()
      -- Send .scm buffers to the Racket client (see above).
      vim.g["conjure#filetype#scheme"] = "conjure.client.racket.stdio"
      -- Default is "racket"; spelled out so the REPL command is visible here.
      vim.g["conjure#client#racket#stdio#command"] = "racket"
      -- The HUD is a floating window that mirrors the result log and opens
      -- itself whenever the log changes -- including on REPL startup, so it
      -- covers the top-right of the screen the moment a .scm file is opened.
      -- Results still appear inline (`conjure#eval#inline_results`) and the
      -- log is still reachable on demand with \lg / \ls, so the HUD only
      -- duplicates what is already visible.
      vim.g["conjure#log#hud#enabled"] = false
      -- Conjure maps K to its own doc lookup, which shadows LSP/keywordprg in
      -- these buffers. Keep it -- `,doc` via XREPL is the only Scheme docs
      -- source here -- but leave a single place to turn it off.
      -- vim.g["conjure#mapping#doc_word"] = false
    end,
  },

  -- Diagnostics for .scm and .rkt (see LINTING above). lspconfig's shipped
  -- defaults are correct as-is -- `racket --lib racket-langserver`, filetypes
  -- racket + scheme -- so this only has to switch the server on.
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        racket_langserver = {
          -- R5RS files here are run with `plt-r5rs`, which REJECTS a `#lang`
          -- line, so these files correctly have none. racket-langserver
          -- assumes Racket conventions and flags every such file with
          -- "Missing language header" on line 1 -- advice that would break
          -- the file if followed. Drop that one check and keep the rest.
          handlers = {
            ["textDocument/publishDiagnostics"] = function(err, result, ctx, config)
              if result and result.diagnostics then
                result.diagnostics = vim.tbl_filter(function(d)
                  return d.source ~= "Language Header Check"
                end, result.diagnostics)
              end
              return vim.lsp.handlers["textDocument/publishDiagnostics"](err, result, ctx, config)
            end,
          },
        },
      },
    },
  },

  -- Colour each nesting depth differently. In Lisp the paren depth IS the
  -- structure, so this is closer to syntax highlighting than decoration: it is
  -- what makes a misplaced closing paren visible instead of something you find
  -- by counting. Driven by the same tree-sitter parsers installed below.
  { "HiPhish/rainbow-delimiters.nvim" },

  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      -- Conjure extracts the form under the cursor with tree-sitter. Its README
      -- is explicit that without a parser only visual-selection and motion
      -- evaluation work, which would cost us \ee and \er -- the two mappings
      -- actually used while writing code.
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "scheme", "racket" })
    end,
  },
}
