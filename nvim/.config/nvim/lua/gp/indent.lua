-- Indent engine for PARI/GP.
--
-- GP has no treesitter grammar and no LSP, so `smartindent` was the only thing
-- available -- and it only understands braces, not the parenthesised control
-- flow (`if(...)`, `for(...)`) that GP actually uses.
--
-- The rule matches what clang-format does for C in this config, so typing and
-- saving agree instead of fighting each other: a `{` block indents by
-- shiftwidth, and anything left open inside brackets ALIGNS to the column just
-- after the opening bracket.
--
--     f(n) = {
--       my(x = foo(1,
--                  2));
--     }
--
-- Lexer rules, all verified against gp 2.17:
--   `\\` starts a line comment, but not inside a string
--   `\`  alone is integer division, so `\\` must be matched first
--   `/* */` block comments span lines
--   `'x` is a quoted variable, NOT a string delimiter

local M = {}

local LIMIT = 80        -- must match gpfmt's column limit

local cache = {}

local function is_closer(c)
  return c == ")" or c == "]" or c == "}"
end

--- Index just past the code on a line, i.e. where a `\\` comment begins.
--- A naive find() would stop at a `\\` inside a string literal.
local function code_end_of(text)
  local i, len, in_string = 1, #text, false
  while i <= len do
    local c, two = text:sub(i, i), text:sub(i, i + 1)
    if in_string then
      if c == "\\" then i = i + 2
      else
        if c == '"' then in_string = false end
        i = i + 1
      end
    elseif two == "\\\\" then
      return i - 1
    elseif c == '"' then
      in_string = true; i = i + 1
    else
      i = i + 1
    end
  end
  return len
end

--- Count closing brackets at the head of a line.
local function leading_closers(text)
  local n = 0
  for i = 1, #text do
    if is_closer(text:sub(i, i)) then n = n + 1 else break end
  end
  return n
end

--- The alignment stack in force at the start of every line.
---
--- Indent for each line is DERIVED from the stack, never read from the line's
--- existing leading whitespace. Two reasons: it makes the result identical to
--- gpfmt by construction, and it makes the scan immune to the buffer changing
--- underneath it. `gg=G` is a single undo block, so `changedtick` does not
--- advance while the operator runs; a scan that read existing indentation
--- would work from stale text and need several passes to converge.
local function scan(bufnr, sw)
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  local hit = cache[bufnr]
  if hit and hit.tick == tick and hit.sw == sw then
    return hit.states
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local states = {}
  local stack = { 0 }
  local in_block = false
  local in_string = false

  for n, line in ipairs(lines) do
    states[n] = { stack = vim.deepcopy(stack), in_block = in_block, in_string = in_string }

    -- A line that starts inside a string literal is program DATA; re-indenting
    -- it changes what the program prints. Scan it only to find the closing
    -- quote, and never touch it.
    if in_string then
      local i, len = 1, #line
      while i <= len do
        local c = line:sub(i, i)
        if c == "\\" then i = i + 2
        else
          i = i + 1
          if c == '"' then in_string = false; break end
        end
      end
      -- The line itself is left alone, but code AFTER the closing quote must
      -- still update the bracket stack, or the `)` closing the call is never
      -- popped and every line below is indented from too deep a stack.
      if not in_string then
        local col = i - 1
        while i <= len do
          local c = line:sub(i, i)
          if c == "(" or c == "[" or c == "{" then
            local rest = line:sub(i + 1):match("^%s*(.-)%s*$")
            stack[#stack + 1] = stack[#stack] + sw
          elseif is_closer(c) and #stack > 1 then
            stack[#stack] = nil
          elseif c == '"' then
            in_string = true
          end
          i = i + 1
          col = col + 1
        end
      end
      goto continue
    end

    local stripped = line:match("^%s*(.-)%s*$") or ""
    if in_block then
      local close = line:find("*/", 1, true)
      if close then
        in_block = false
        -- code after the closing `*/` still updates the bracket stack
        local i, len = close + 2, #line
        local col = i - 1
        while i <= len do
          local c = line:sub(i, i)
          if c == "(" or c == "[" or c == "{" then
            local rest = line:sub(i + 1):match("^%s*(.-)%s*$")
            stack[#stack + 1] = stack[#stack] + sw
          elseif is_closer(c) and #stack > 1 then
            stack[#stack] = nil
          end
          i = i + 1; col = col + 1
        end
      end
      goto continue
    end
    if stripped == "" then goto continue end

    do
      -- indent this line would be given, by the same rule as indentexpr
      local indent = stack[math.max(1, #stack - leading_closers(stripped))]
      local i, len = 1, #stripped
      local col = indent          -- CODEPOINT column, matching gpfmt

      while i <= len do
        local two, c = stripped:sub(i, i + 1), stripped:sub(i, i)

        if in_block then
          if two == "*/" then in_block = false; i = i + 2; col = col + 2
          else i = i + 1; col = col + 1 end
        elseif in_string then
          if c == "\\" then i = i + 2; col = col + 2
          else
            if c == '"' then in_string = false end
            i = i + 1; col = col + 1
          end
        elseif two == "\\\\" then
          break                                   -- line comment
        elseif two == "/*" then
          in_block = true; i = i + 2; col = col + 2
        elseif c == '"' then
          in_string = true
          i = i + 1; col = col + 1
          -- consume the literal; if it does not close, it runs to the next line
          while i <= len do
            local d = stripped:sub(i, i)
            if d == "\\" then i = i + 2; col = col + 2
            else
              i = i + 1; col = col + 1
              if d == '"' then in_string = false; break end
            end
          end
        else
          if c == "(" or c == "[" or c == "{" then
            local tail = stripped:sub(i + 1)
            local rest = tail:sub(1, code_end_of(tail)):match("^%s*(.-)%s*$")
            -- Block indent, one level per open bracket, matching gpfmt.
            stack[#stack + 1] = stack[#stack] + sw
          elseif is_closer(c) and #stack > 1 then
            stack[#stack] = nil
          end
          i = i + 1
          -- advance the codepoint column only on a non-continuation byte
          if c:byte() < 0x80 or c:byte() >= 0xC0 then col = col + 1 else col = col end
        end
      end
    end

    ::continue::
  end

  states[#lines + 1] = { stack = vim.deepcopy(stack), in_block = in_block, in_string = in_string }
  cache[bufnr] = { tick = tick, sw = sw, states = states }
  return states
end

--- `indentexpr` entry point. Returns a column count, or -1 to keep as-is.
function M.indentexpr()
  local bufnr = vim.api.nvim_get_current_buf()
  local sw = vim.bo[bufnr].shiftwidth
  local state = scan(bufnr, sw)[vim.v.lnum]

  if state == nil then return -1 end
  if state.in_block then return -1 end   -- inside /* */: leave the author alone
  if state.in_string then return -1 end  -- inside a string: it is DATA

  local text = (vim.fn.getline(vim.v.lnum) or ""):gsub("^%s+", "")
  local stack = state.stack
  local idx = math.max(1, #stack - leading_closers(text))
  return stack[idx]
end

vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
  group = vim.api.nvim_create_augroup("gp_indent_cache", { clear = true }),
  callback = function(ev) cache[ev.buf] = nil end,
})

return M
