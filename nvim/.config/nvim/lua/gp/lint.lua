--- nvim-lint integration for PARI/GP (`.gp`) files, backed by gp2c.
---
--- WHY gp2c
---
--- gp2c is PARI's GP-to-C translator, and it is the only static analyser GP
--- has. `gp2c -W` reports hard syntax errors (`file:line: syntax error, ...`,
--- exit 1) and soft warnings (`Warning:file:line: variable undeclared` /
--- `function prototype is unknown`) WITHOUT executing the script. That last
--- part is the deciding argument: the obvious alternative -- feeding the file
--- to `gp` itself -- runs arbitrary user code on every save, which for a
--- number-theory script can mean an unbounded computation, and `gp -q FILE`
--- additionally exits 0 on syntax errors and then drops into an interactive
--- REPL. gp2c only parses, and its exit code and line numbers are meaningful.
---
--- gp2c is NOT in the Arch repos. It is in the AUR as `gp2c` (depends on
--- `pari`, already installed here): `paru -S gp2c` / `yay -S gp2c`. That
--- package installs /usr/bin/gp2c plus its function-description database, so
--- no extra environment is needed once it is on PATH.
---
--- GRACEFUL DEGRADATION
---
--- nvim-lint reports an error every time it fails to spawn a linter, so a
--- missing gp2c would mean a notification on every save. `M.linter.condition`
--- (a LazyVim extension to nvim-lint, honoured by LazyVim's lint autocmd)
--- returns false when no gp2c can be found, and the linter is then simply
--- never run.
---
--- OVERRIDES (set them in lua/config/options.lua, which loads before plugins)
---
---   vim.g.gp2c_cmd       absolute path to a gp2c binary (e.g. an uninstalled
---                        build's src/gp2c)
---   vim.g.gp2c_func_dsc  absolute path to desc/func.dsc, needed only when
---                        gp2c was built but never `make install`ed
---
--- The diagnostics land in nvim-lint's own "gp2c" namespace and carry
--- `source = "gp2c"`, so they never collide with the gpfmt diagnostics
--- (namespace + `source = "gpfmt"`) produced by the formatter side.

local M = {}

local NULL_DEVICE = vim.fn.has("win32") == 1 and "NUL" or "/dev/null"

--- Resolve the gp2c executable, or nil if there is none.
---
--- Order: vim.g.gp2c_cmd, $GP2C, then `gp2c` on PATH.
---@return string|nil
function M.executable()
  local explicit = vim.g.gp2c_cmd or vim.env.GP2C
  if explicit and explicit ~= "" then
    return vim.fn.executable(explicit) == 1 and explicit or nil
  end
  return vim.fn.executable("gp2c") == 1 and "gp2c" or nil
end

--- Point an uninstalled gp2c at its function-description database.
---
--- nvim-lint reads `linter.env` as a plain table at spawn time and REPLACES
--- the child environment with it (plus PATH), so it cannot be a function and
--- leaving it nil is the right default -- then gp2c inherits Neovim's own
--- environment, including any GP2C_FUNC_DSC exported from the shell. We only
--- build an env table when vim.g.gp2c_func_dsc asks us to, and we do it just
--- before each run so that setting the variable at runtime takes effect.
---@param linter table
local function refresh_env(linter)
  local dsc = vim.g.gp2c_func_dsc
  if dsc and dsc ~= "" then
    local env = { GP2C_FUNC_DSC = dsc }
    -- nvim-lint concatenates "k=v", so a nil value would raise.
    for _, key in ipairs({ "PATH", "HOME" }) do
      if vim.env[key] then
        env[key] = vim.env[key]
      end
    end
    linter.env = env
  else
    linter.env = nil
  end
end

--- Absolute, symlink-resolved form of a path, for comparing gp2c's echoed
--- filename against the buffer's.
---@param path string
---@return string
local function canonical(path)
  if path == nil or path == "" then
    return ""
  end
  local full = vim.fn.fnamemodify(path, ":p")
  return (vim.loop.fs_realpath(full)) or full
end

--- Tidy a gp2c continuation line (the offending token/expression, which gp2c
--- prints on the line after the warning header).
---@param text string
---@return string
local function tidy(text)
  local out = text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if #out > 100 then
    out = out:sub(1, 97) .. "..."
  end
  return out
end

--- Build one diagnostic, clamping the line number into the buffer.
---
--- gp2c can report a line one past the end of the file (an unterminated
--- construct reports at EOF), and vim.diagnostic rejects out-of-range lnums.
---@param bufnr integer
---@param lnum1 integer 1-indexed line as printed by gp2c
---@param severity integer
---@param message string
---@return vim.Diagnostic
local function diagnostic(bufnr, lnum1, severity, message)
  local lnum = math.max(0, (tonumber(lnum1) or 1) - 1)
  local ok, count = pcall(vim.api.nvim_buf_line_count, bufnr)
  if ok and count > 0 then
    lnum = math.min(lnum, count - 1)
  end
  local end_col = 0
  local got, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, lnum, lnum + 1, false)
  if got and lines and lines[1] then
    end_col = #lines[1]
  end
  return {
    lnum = lnum,
    end_lnum = lnum,
    col = 0,
    end_col = end_col,
    severity = severity,
    source = "gp2c",
    message = message,
  }
end

--- Parse gp2c's stderr into diagnostics.
---
--- The three shapes that matter:
---
---   Warning:/path/f.gp:12: variable undeclared
---   s
---   /path/f.gp:5: syntax error, unexpected '\n'
---   Errors found: aborting...
---   Error:func.dsc:<loading>: Cannot find description file /usr/share/...
---
--- A warning header is always followed by one or more lines holding the
--- offending expression; they are folded into the message. Anything else is
--- ignored, so a clean file yields an empty list.
---@param output string
---@param bufnr integer
---@return vim.Diagnostic[]
function M.parse(output, bufnr)
  local diagnostics = {}
  if not output or output == "" then
    return diagnostics
  end

  local buffile = canonical(vim.api.nvim_buf_get_name(bufnr))
  local lines = vim.split(output, "\n", { plain = true })

  -- Does this line start a new gp2c record (rather than continue one)?
  local function is_header(line)
    return line:match("^Warning:")
      or line:match("^Error:")
      or line:match("^[^:]*[^:]:%d+: ")
      or line:match("^Errors found:")
  end

  --- Turn "file", "line", "text" into a message + line, accounting for gp2c
  --- reporting against a file other than the one in the buffer (GP's read()
  --- pulls in other scripts).
  local function locate(file, lnum1, text)
    if canonical(file) == buffile then
      return lnum1, text
    end
    return 1, string.format("%s:%s: %s", vim.fn.fnamemodify(file, ":t"), lnum1, text)
  end

  local i = 1
  while i <= #lines do
    local line = lines[i]
    local file, lnum1, text = line:match("^Warning:(.*):(%d+):%s*(.*)$")
    if file then
      -- Fold the continuation lines (the offending expression) into the text.
      local parts = {}
      local j = i + 1
      while j <= #lines and lines[j] ~= "" and not is_header(lines[j]) do
        table.insert(parts, lines[j])
        j = j + 1
      end
      if #parts > 0 then
        text = text .. ": " .. tidy(table.concat(parts, " "))
      end
      local at, message = locate(file, lnum1, text)
      table.insert(diagnostics, diagnostic(bufnr, at, vim.diagnostic.severity.WARN, message))
      i = j
    else
      local rest = line:match("^Error:%s*(.*)$")
      if rest and rest ~= "" then
        -- A gp2c-level failure (missing func.dsc, unreadable file). Surface it
        -- at the top of the buffer so a broken gp2c is visible, not silent.
        table.insert(diagnostics, diagnostic(bufnr, 1, vim.diagnostic.severity.ERROR, "gp2c: " .. rest))
      else
        file, lnum1, text = line:match("^(.*[^:]):(%d+):%s*(.*)$")
        if file and text ~= "" then
          local at, message = locate(file, lnum1, text)
          table.insert(diagnostics, diagnostic(bufnr, at, vim.diagnostic.severity.ERROR, message))
        end
      end
      i = i + 1
    end
  end

  return diagnostics
end

--- The nvim-lint linter definition.
---
--- `-W` turns on the type/global-usage warnings and still aborts with exit 1
--- on a syntax error, so one invocation covers both. `-o /dev/null` is not
--- cosmetic: gp2c writes the translated C to stdout by default, nvim-lint only
--- reads the stream named by `stream`, and an unread stdout pipe would block
--- gp2c as soon as the generated C exceeded the pipe buffer.
---@type table
M.linter = {
  cmd = function()
    -- (The environment refresh lives in `args` below, because nvim-lint
    -- evaluates the `args` functions, then reads `env`, then evaluates `cmd`.)
    local exe = M.executable()
    if exe then
      return exe
    end
    -- Belt and braces for the `condition` guard: LazyVim's lint autocmd honours
    -- `condition`, but a bare require("lint").try_lint() does not, and a cmd
    -- that cannot be spawned makes nvim-lint notify an ENOENT error. Falling
    -- back to /usr/bin/true produces no output, hence no diagnostics, silently.
    if vim.fn.executable("true") == 1 then
      return "true"
    end
    return "gp2c"
  end,
  stdin = false,
  append_fname = true,
  stream = "stderr",
  -- gp2c exits 1 when it finds a syntax error; that is a normal outcome here
  -- and must not raise nvim-lint's "exited with code" warning.
  ignore_exitcode = true,
  args = {
    function()
      refresh_env(M.linter)
      -- LazyVim registers this very table, but guard against a copy having
      -- been made so the env lands on whatever nvim-lint is about to spawn.
      local ok, lint = pcall(require, "lint")
      if ok and type(lint.linters.gp2c) == "table" and lint.linters.gp2c ~= M.linter then
        refresh_env(lint.linters.gp2c)
      end
      return "-W"
    end,
    "-o",
    NULL_DEVICE,
  },
  parser = function(output, bufnr)
    return M.parse(output, bufnr)
  end,
  -- LazyVim extension: consulted by LazyVim's lint autocmd before try_lint.
  -- Without gp2c installed the linter is skipped entirely instead of failing
  -- to spawn and notifying on every save.
  condition = function()
    return M.executable() ~= nil
  end,
}

return M
