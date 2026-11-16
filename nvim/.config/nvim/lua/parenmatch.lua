-- Paren matching: which two brackets belong together.
--
-- Replaces the stock matchparen plugin. The stock plugin paints both ends of
-- the pair with one highlight and has one rule for which bracket counts as
-- "the one at the cursor". That falls short in four places, all of which
-- matter most in Lisp, where the brackets are the structure:
--
--   * a filled block painted on the bracket at the caret hides a bar caret;
--   * with the caret between two brackets there is no telling which of them
--     the lit partner belongs to;
--   * an empty () lights up although there is nothing to find;
--   * "no partner" and "partner is off screen" both show nothing at all.
--
-- THE RULES
--
-- Nothing is shown unless the caret touches a bracket.
--
-- Normal and visual mode: the cursor is ON a character. If that character is
-- a bracket, it is the active one.
--
-- Insert and replace mode: the caret sits BETWEEN two characters, so up to two
-- brackets touch it. The active one is the first of these that applies:
--   1. a closing bracket just left of the caret  -> "what did I just close?"
--   2. any bracket just right of the caret       -> "what is this one's pair?"
--   3. an opening bracket just left of the caret -> "where does this end?"
-- Rule 1 comes first so that typing ")" always lights the opener of the ")"
-- just typed. With auto-pairs there is usually another ")" already waiting to
-- the right; putting that one first would light a form the keypress did not
-- close, which teaches the wrong structure.
--
-- What is drawn for the active bracket:
--   * its PARTNER gets the filled block (MatchParen);
--   * the active bracket itself gets a foreground-only mark (MatchParenNear).
--     It never gets a background, so the caret stays visible, and it settles
--     which of two neighbouring brackets is meant.
--   * an empty pair, "()", draws nothing: both ends are already at the caret.
--     If the caret touches a second bracket, that one becomes active instead.
--
-- Brackets inside strings, comments and character literals are text, not
-- structure. Code brackets never pair with them. A text bracket pairs only
-- with another text bracket on the same line, and is never reported as
-- unmatched.
--
-- LISP EXTRAS (filetypes in STRUCTURAL below)
--
-- In these languages every code bracket must have a partner, so the search
-- covers the whole buffer instead of just the visible lines, which allows:
--   * partner off screen: a dim note at the right edge of the caret's line
--     giving its line number and text;
--   * no partner anywhere: the bracket is marked as an error and the note
--     says which bracket is missing.
-- Elsewhere a lone bracket is often legitimate (a shell `case` pattern, "1)"
-- in prose), so other filetypes keep the stock behaviour: search the visible
-- lines and stay silent when nothing is found.
--
-- Highlight groups are defined in on_highlights in lua/plugins/example.lua.

local M = {}

local api, fn = vim.api, vim.fn
local ns = api.nvim_create_namespace("parenmatch")

local STRUCTURAL = {
  scheme = true,
  racket = true,
  lisp = true,
  clojure = true,
  fennel = true,
  janet = true,
  query = true,
}

-- Search budgets in milliseconds, the same as the stock plugin's. A search
-- that runs out of time is treated as "unknown", never as "no partner".
local TIMEOUT_INSERT, TIMEOUT_NORMAL = 60, 300

-- Longest stretch of the partner's line quoted in the off-screen note.
local NOTE_WIDTH = 48

-- Fallbacks so the groups exist under any colourscheme. tokyonight sets all of
-- them explicitly, and `default` never overrides an explicit definition.
local function define_default_highlights()
  api.nvim_set_hl(0, "MatchParenNear", { default = true, bold = true, underline = true })
  api.nvim_set_hl(0, "MatchParenUnmatched", { default = true, link = "DiagnosticUnderlineError" })
  api.nvim_set_hl(0, "MatchParenNote", { default = true, link = "Comment" })
  api.nvim_set_hl(0, "MatchParenNoteError", { default = true, link = "DiagnosticError" })
end

-- 'matchpairs' as two lookups: bracket -> its partner, and opener -> true.
local function bracket_tables(buf)
  local partner, opener = {}, {}
  for pair in vim.gsplit(vim.bo[buf].matchpairs, ",", { plain = true }) do
    local open, close = pair:match("^(.):(.)$")
    if open then
      partner[open], partner[close], opener[open] = close, open, true
    end
  end
  return partner, opener
end

-- True when the character at (lnum, col), both 1-based, is text rather than
-- code: part of a string, a comment or a character literal.
--
-- With tree-sitter this asks for the smallest named node at the position and
-- goes by its type: a bracket in code sits in a list, a call, a block and so
-- on, while a bracket in text sits in a string, comment or character node.
-- The stock plugin asks for highlight captures instead
-- (get_captures_at_pos); that was measured at about 0.27 ms a call against
-- 0.004 ms for the node lookup, and this runs once per bracket the search
-- passes, so with captures a 100-line define used up the whole time budget
-- and showed nothing.
local TEXT_NODE = { "comment", "string", "char", "regex" }

local function is_text(buf, lnum, col)
  if vim.treesitter.highlighter.active[buf] then
    local ok, node = pcall(vim.treesitter.get_node, { bufnr = buf, pos = { lnum - 1, col - 1 } })
    if ok and node then
      local kind = node:type()
      for _, word in ipairs(TEXT_NODE) do
        if kind:find(word, 1, true) then
          return true
        end
      end
    end
    return false
  end
  -- No tree-sitter highlighting: fall back to regex syntax names, using the
  -- same list the stock plugin checks.
  for _, id in ipairs(fn.synstack(lnum, col)) do
    local name = fn.synIDattr(id, "name"):lower()
    for _, kind in ipairs({ "string", "character", "singlequote", "escape", "symbol", "comment" }) do
      if name:find(kind, 1, true) then
        return true
      end
    end
  end
  return false
end

-- Find the partner of the bracket `ch` at (lnum, col).
-- Returns { lnum, col } when found, the string "unmatched" when the whole
-- buffer was searched and there is none, or nil when it is simply not known.
local function find_partner(buf, lnum, col, ch, partner, opener, structural, timeout)
  local forward = opener[ch] == true
  local open = forward and ch or partner[ch]
  local close = forward and partner[ch] or ch
  local text = is_text(buf, lnum, col)

  -- A bracket only pairs with brackets of its own kind: code with code, text
  -- with text. During the search the cursor sits on each candidate in turn.
  local function skip()
    return is_text(buf, fn.line("."), fn.col(".")) ~= text and 1 or 0
  end

  local whole_buffer = structural and not text
  local stopline
  if text then
    stopline = lnum
  elseif whole_buffer then
    stopline = 0
  else
    stopline = forward and fn.line("w$") or fn.line("w0")
  end

  -- searchpairpos() starts from the cursor, so park it on the bracket for the
  -- duration when the bracket is the one to the left of the caret.
  local saved = fn.getcurpos()
  local moved = saved[2] ~= lnum or saved[3] ~= col
  if moved then
    fn.cursor(lnum, col)
  end
  local started = vim.uv.hrtime()
  local ok, pos =
    pcall(fn.searchpairpos, "\\V" .. open, "", "\\V" .. close, forward and "nW" or "nbW", skip, stopline, timeout)
  local elapsed_ms = (vim.uv.hrtime() - started) / 1e6
  if moved then
    fn.setpos(".", saved)
  end

  if not ok then
    return nil
  end
  if pos[1] > 0 then
    return pos
  end
  if whole_buffer and elapsed_ms < timeout then
    return "unmatched"
  end
  return nil
end

local function clear(win)
  if not api.nvim_win_is_valid(win) then
    return
  end
  for _, id in ipairs(vim.w[win].parenmatch_ids or {}) do
    pcall(fn.matchdelete, id, win)
  end
  vim.w[win].parenmatch_ids = nil
  api.nvim_buf_clear_namespace(api.nvim_win_get_buf(win), ns, 0, -1)
end

-- Window-local highlight of single cells, like the stock plugin uses, so a
-- second window on the same buffer is not painted with this window's pair.
local function paint(win, group, lnum, col)
  local ids = vim.w[win].parenmatch_ids or {}
  ids[#ids + 1] = fn.matchaddpos(group, { { lnum, col } }, 10, -1, { window = win })
  vim.w[win].parenmatch_ids = ids
end

-- A short note at the right-hand edge of the caret's line. Right-aligned so it
-- stays clear of the text being typed and of anything else printed at the end
-- of the line (diagnostics, Conjure results).
local function note(buf, lnum, text, group)
  api.nvim_buf_set_extmark(buf, ns, lnum - 1, 0, {
    virt_text = { { text, group } },
    virt_text_pos = "right_align",
    hl_mode = "combine",
  })
end

local function update()
  local win = api.nvim_get_current_win()
  clear(win)
  -- Leave the built-in completion menu alone, as the stock plugin does.
  if fn.pumvisible() == 1 then
    return
  end

  local buf = api.nvim_win_get_buf(win)
  local partner, opener = bracket_tables(buf)
  local lnum, col = fn.line("."), fn.col(".")
  local line = api.nvim_get_current_line()
  local mode = api.nvim_get_mode().mode:sub(1, 1)
  local between = mode == "i" or mode == "R"

  -- Columns of the brackets that could be the active one, in priority order
  -- (see THE RULES above).
  local candidates = {}
  local here = line:sub(col, col)
  if between then
    local left = col > 1 and line:sub(col - 1, col - 1) or ""
    if partner[left] and not opener[left] then
      candidates[#candidates + 1] = col - 1
    end
    if partner[here] then
      candidates[#candidates + 1] = col
    end
    if opener[left] then
      candidates[#candidates + 1] = col - 1
    end
  elseif partner[here] then
    candidates[1] = col
  end
  if #candidates == 0 then
    return
  end

  -- Classification below reads the syntax tree; make sure it reflects the
  -- keystroke that triggered this update rather than the previous redraw.
  if vim.treesitter.highlighter.active[buf] then
    local ok, parser = pcall(vim.treesitter.get_parser, buf)
    if ok and parser then
      pcall(parser.parse, parser)
    end
  end

  local structural = STRUCTURAL[vim.bo[buf].filetype] == true
  local timeout = between and TIMEOUT_INSERT or TIMEOUT_NORMAL

  for _, c in ipairs(candidates) do
    local ch = line:sub(c, c)
    local found = find_partner(buf, lnum, c, ch, partner, opener, structural, timeout)

    if found == "unmatched" then
      paint(win, "MatchParenUnmatched", lnum, c)
      note(buf, lnum, "no matching " .. partner[ch] .. " ", "MatchParenNoteError")
      return
    end
    if not found then
      return
    end

    local m_lnum, m_col = found[1], found[2]
    local empty_pair = m_lnum == lnum and math.abs(m_col - c) == 1
    if not empty_pair then
      paint(win, "MatchParenNear", lnum, c)
      paint(win, "MatchParen", m_lnum, m_col)
      local top, bottom = fn.line("w0"), fn.line("w$")
      if m_lnum < top or m_lnum > bottom then
        local quoted = vim.trim(fn.getline(m_lnum))
        if fn.strchars(quoted) > NOTE_WIDTH then
          quoted = fn.strcharpart(quoted, 0, NOTE_WIDTH - 1) .. "…"
        end
        local arrow = m_lnum < top and "↑" or "↓"
        note(buf, lnum, ("%s %d: %s "):format(arrow, m_lnum, quoted), "MatchParenNote")
      end
      return
    end
    -- Empty pair: nothing to show for this bracket; try the next candidate.
  end
end

function M.setup()
  -- Retire the stock plugin: drop its autocommands and any pair it has
  -- already painted, and stop it loading if it has not loaded yet. Done here,
  -- not in the lazy.nvim disabled list, so that if this module ever fails to
  -- load the stock plugin is still there.
  pcall(api.nvim_clear_autocmds, { group = "matchparen" })
  for _, win in ipairs(api.nvim_list_wins()) do
    for _, id in ipairs(vim.w[win].matchparen_ids or {}) do
      pcall(fn.matchdelete, id, win)
    end
    vim.w[win].matchparen_ids = {}
    vim.w[win].paren_hl_on = 0
  end
  vim.g.loaded_matchparen = 1

  define_default_highlights()

  local group = api.nvim_create_augroup("parenmatch", { clear = true })
  api.nvim_create_autocmd("ColorScheme", { group = group, callback = define_default_highlights })
  api.nvim_create_autocmd(
    { "CursorMoved", "CursorMovedI", "WinEnter", "BufWinEnter", "WinScrolled", "TextChanged", "TextChangedI" },
    { group = group, callback = update }
  )
  -- Entering or leaving insert mode changes which bracket is active without
  -- necessarily moving the cursor (for example at the start of a line).
  api.nvim_create_autocmd("ModeChanged", {
    group = group,
    callback = function()
      local event = vim.v.event
      if (event.old_mode or ""):find("^[iR]") or (event.new_mode or ""):find("^[iR]") then
        update()
      end
    end,
  })
  api.nvim_create_autocmd({ "WinLeave", "BufLeave", "TextChangedP" }, {
    group = group,
    callback = function()
      clear(api.nvim_get_current_win())
    end,
  })

  vim.schedule(update)
end

return M
