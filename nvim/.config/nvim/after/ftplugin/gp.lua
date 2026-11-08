-- PARI/GP filetype settings.
--
-- Neovim ships syntax/gp.vim (highlighting works out of the box), but there is
-- no ftplugin, no treesitter grammar and no LSP for GP -- none exist upstream.
-- This fills the gaps that actually matter day to day.

-- GP line comments are \\ , block comments are /* */.
-- Without this, gcc / gc do nothing in .gp files.
vim.bo.commentstring = "\\\\ %s"
vim.bo.comments = "s1:/*,mb:*,ex:*/,:\\\\"

-- K on a function name opens its real PARI documentation, the same way K opens
-- a man page in C. gphelp ships with the pari package.
vim.bo.keywordprg = "gphelp -detex"

-- Indent exactly like C/C++ does in this config: two spaces, no hard tabs.
-- (This used to be 8-wide hard tabs, which made every .gp file look four times
-- more indented than everything else.)
vim.bo.expandtab = true
vim.bo.shiftwidth = 2
vim.bo.tabstop = 2
vim.bo.softtabstop = 2

-- Indentation lives in indent/gp.lua, per the runtime's indent/README.txt.

-- Hard cap at 80 columns, matching PARI's coding guide. `t` is removed from formatoptions on purpose:
-- auto-wrapping CODE while typing would be a correctness bug in GP, because
-- outside a { } block a newline terminates the statement. `c` stays, so long
-- comments still wrap themselves.
vim.bo.textwidth = 80
-- gq goes through conform (and so through gpfmt) rather than Vim's internal
-- paragraph formatter, which knows nothing about GP.
vim.bo.formatexpr = "v:lua.require'conform'.formatexpr()"
vim.bo.formatoptions = vim.bo.formatoptions:gsub("t", "")

-- colorcolumn is WINDOW-local. Plain `vim.wo.colorcolumn = x` also writes the
-- window's GLOBAL value, which then follows the window into the next file and
-- overrides the global 80 that matches clang-format (measured). `vim.wo[0][0]`
-- is the buffer-scoped form core itself uses (runtime/ftplugin/lua.lua).
vim.wo[0][0].colorcolumn = "80"

-- Flag the lines gpfmt is not allowed to fix: over 80 columns and outside a
-- { } block, where inserting a newline would change what the code means.
local ns = vim.api.nvim_create_namespace("gp_line_length")

local function flag_long_lines(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= "gp" then
    return
  end
  local diagnostics = {}
  local depth = 0
  for lnum, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    -- Count DISPLAY columns, not bytes: `#line` on a UTF-8 line reports far
    -- more than the width the cap actually refers to.
    local width = vim.fn.strdisplaywidth(line)
    if width > 80 then
      table.insert(diagnostics, {
        lnum = lnum - 1,
        col = math.max(0, vim.fn.byteidx(line, 80)),
        end_col = #line,
        severity = vim.diagnostic.severity.WARN,
        source = "gpfmt",
        message = depth > 0
            and ("line is %d columns, over the 80 cap; saving will wrap it"):format(width)
          or ("line is %d columns, over the 80 cap. Outside a { } block a "):format(width)
            .. "newline ends the statement, so this cannot be wrapped. Wrap the "
            .. "function body in { } and it will format.",
      })
    end
    local _, opens = line:gsub("{", "")
    local _, closes = line:gsub("}", "")
    depth = math.max(0, depth + opens - closes)
  end
  vim.diagnostic.set(ns, buf, diagnostics)
end

-- One shared augroup rather than one per buffer: the autocmds are
-- buffer-scoped so they die with the buffer, but a per-buffer GROUP would
-- accumulate for the life of the session.
local ll_group = vim.api.nvim_create_augroup("gp_line_length", { clear = false })
vim.api.nvim_clear_autocmds({ group = ll_group, buffer = 0 })
vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "InsertLeave", "TextChanged" }, {
  buffer = 0,
  group = ll_group,
  callback = function(ev) flag_long_lines(ev.buf) end,
})
flag_long_lines(vim.api.nvim_get_current_buf())

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

-- Undo everything above when the filetype changes, per :help undo_ftplugin.
-- This runs in an `after/` plugin, so it must APPEND to whatever the main
-- ftplugin already registered, never overwrite it.
vim.b.undo_ftplugin = (vim.b.undo_ftplugin or "")
  .. "\n setlocal commentstring< comments< keywordprg< expandtab< shiftwidth<"
  .. " tabstop< softtabstop< textwidth< formatoptions< colorcolumn< formatexpr<"
  .. " | silent! nunmap <buffer> <leader>r"
  .. " | silent! nunmap <buffer> <leader>R"
  .. " | silent! autocmd! gp_line_length * <buffer>"
