return {
  -- add tokyonight
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      style = "night",
      -- ── Palette ─────────────────────────────────────────────────────────────
      -- The 17 slots come from lua/theme_palette.lua, which matugen generates
      -- from [config.custom_colors] — the same block kitty, waybar, tmux, wofi,
      -- starship, lazygit and hyprland read. The editor therefore follows a
      -- palette switch instead of being left behind on the previous one.
      --
      -- This file keeps the MAPPING (slot -> tokyonight key) and is deliberately
      -- not templated, so matugen can never delete editor config it doesn't know
      -- about. Only the raw hexes are generated.
      --
      -- Falls back to Marigold if the generated file is missing, e.g. on a fresh
      -- clone before the first re-theme, so the editor is never unstyled.
      --
      -- NOTE: running nvim instances do not live-update. Restart to pick up a
      -- palette change.
      on_colors = function(c)
        local ok, p = pcall(require, "theme_palette")
        if not ok then
          p = {
            bg = "#1a1614", bg_dark = "#121010", bg_hl = "#2b2320",
            fg = "#f5e6d3", fg_light = "#d9c7b3", comment = "#8a7867",
            blue = "#ff8c42", cyan = "#7fb0a0", magenta = "#e0879b",
            green = "#a3b565", yellow = "#fabd2f", orange = "#ff6b35",
            red = "#f2543d", selection = "#4a3428", gray = "#2b2320",
            gray2 = "#3d332e", bright_black = "#75665a",
          }
        end

        c.bg = p.bg
        c.bg_dark = p.bg_dark
        c.bg_float = p.bg_dark
        c.bg_highlight = p.bg_hl
        c.bg_popup = p.bg_dark
        c.bg_sidebar = p.bg_dark
        c.bg_statusline = p.bg_dark
        c.bg_visual = p.selection
        c.fg = p.fg
        c.fg_dark = p.fg_light
        c.fg_float = p.fg
        c.fg_gutter = p.gray2
        c.fg_sidebar = p.fg_light
        c.comment = p.comment
        c.blue = p.blue -- primary accent, matches ANSI color4
        c.cyan = p.cyan
        c.teal = p.cyan
        c.magenta = p.magenta
        c.purple = p.magenta
        c.green = p.green
        c.yellow = p.yellow
        c.orange = p.orange
        c.red = p.red
        c.border = p.gray2
        c.terminal_black = p.bright_black

        -- tokyonight carries 21 further colour keys beyond the obvious ones,
        -- and they drive a lot of syntax: blue1 is `Type`, blue5 is `Special`,
        -- and error/warning/info/hint are the diagnostics. Leaving them unset
        -- meant C++ types rendered stock Tokyo Night blue (#2ac3de) against a
        -- warm desktop -- true under Marigold too, just less obvious than
        -- against a green one.
        c.blue0 = p.selection
        c.blue1 = p.cyan -- Type
        c.blue2 = p.cyan
        c.blue5 = p.magenta -- Special / punctuation, kept distinct from Type
        c.blue6 = p.fg_light
        c.blue7 = p.gray2
        c.black = p.bg_dark
        c.bg_dark1 = p.bg_dark
        c.bg_search = p.selection
        c.border_highlight = p.blue
        c.dark3 = p.bright_black
        c.dark5 = p.comment
        c.green1 = p.green
        c.green2 = p.green
        c.magenta2 = p.magenta
        c.red1 = p.red
        c.todo = p.blue

        -- Diagnostics keep their conventional meanings.
        c.error = p.red
        c.warning = p.yellow
        c.info = p.cyan
        c.hint = p.green
      end,

      -- ── Highlight overrides ─────────────────────────────────────────────
      -- Runs after on_colors, and `c` is the already-remapped table above, so
      -- these follow a palette switch for free with no second require and no
      -- hardcoded hex.
      --
      -- ColorColumn marks clang-format's 80-column ColumnLimit. Stock
      -- tokyonight picks a cool grey that reads as a bruise against the warm
      -- palette. fg_gutter (gray2) is the dimmest slot that still separates
      -- from both bg and bg_hl, so the rule stays visible on the cursorline
      -- row without competing with the text.
      --
      -- MatchParen marks the partner of the paren under the cursor. Stock
      -- tokyonight draws it as orange bold text, and orange is also one of
      -- the rainbow-delimiters depth colours (lua/plugins/scheme.lua), so in
      -- Scheme the matched pair differed from its neighbours by weight alone.
      -- A filled block cannot be confused with any depth colour, because the
      -- depth colours only ever set the foreground.
      --
      -- The other MatchParen* groups belong to lua/parenmatch.lua, which
      -- decides what gets painted. The paren AT the caret (Near, Unmatched)
      -- must never be given a background: a bar caret drawn on a filled cell
      -- disappears. Underline keeps it distinct from the depth colours.
      on_highlights = function(hl, c)
        hl.ColorColumn = { bg = c.fg_gutter }
        hl.MatchParen = { fg = c.bg_dark, bg = c.yellow, bold = true }
        hl.MatchParenNear = { fg = c.yellow, bold = true, underline = true }
        hl.MatchParenUnmatched = { fg = c.error, bold = true, underline = true }
        hl.MatchParenNote = { fg = c.comment }
        hl.MatchParenNoteError = { fg = c.error }

        -- Paren depth colours: RainbowDepth1..12, handed to rainbow-delimiters
        -- in lua/plugins/scheme.lua. Keep the count (12) the same in both.
        --
        -- The plugin's stock set is the seven palette accents, and several of
        -- those are near-twins (yellow/orange, blue/violet/cyan), so deep
        -- nesting read as about four colours. These are generated instead:
        -- twelve hues spaced evenly round the wheel, at the palette accents'
        -- average saturation and lightness so they still sit with the theme.
        -- Two things keep neighbours apart:
        --   * depth order steps five hues at a time, so each depth is 150
        --     degrees of hue from the one before it;
        --   * alternate hues are lighter and darker, so the two hues that are
        --     only 30 degrees apart also differ in brightness.
        -- hsluv ships inside tokyonight, so this adds no dependency.
        local hsluv = require("tokyonight.hsluv")
        local accents = { c.red, c.orange, c.yellow, c.green, c.cyan, c.blue, c.magenta }
        local sat, light = 0, 0
        for _, hex in ipairs(accents) do
          local hsl = hsluv.hex_to_hsluv(hex)
          sat, light = sat + hsl[2] / #accents, light + hsl[3] / #accents
        end
        local hue0 = hsluv.hex_to_hsluv(c.red)[1] + 10
        for depth = 1, 12 do
          local k = (depth - 1) * 5 % 12
          hl["RainbowDepth" .. depth] = {
            fg = hsluv.hsluv_to_hex({ (hue0 + k * 30) % 360, sat, light + (k % 2 == 0 and 6 or -6) }),
          }
        end
      end,
    },
    config = function(_, opts)
      require("tokyonight").setup(opts)
      vim.cmd([[colorscheme tokyonight]])
    end,
  },

  -- Configure LazyVim to load tokyonight
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "tokyonight",
    },
  },

  -- LuaSnip: replace native vim.snippet to fix position tracking errors
  {
    "L3MON4D3/LuaSnip",
    build = "make install_jsregexp",
    dependencies = { "rafamadriz/friendly-snippets" },
    config = function()
      require("luasnip").setup({
        region_check_events = "CursorMoved,InsertEnter",
        delete_check_events = "TextChanged,InsertLeave",
      })
      require("luasnip.loaders.from_vscode").lazy_load()
    end,
  },
  {
    "saghen/blink.cmp",
    opts = {
      snippets = { preset = "luasnip" },
      keymap = {
        preset = "default",
        ["<Tab>"] = { "snippet_forward", "fallback" },
        ["<S-Tab>"] = { "snippet_backward", "fallback" },
        ["<CR>"] = { "accept", "fallback" },
      },
    },
  },

  -- Show hidden files (dotfiles) in neo-tree
  {
    "nvim-neo-tree/neo-tree.nvim",
    opts = {
      filesystem = {
        filtered_items = {
          visible = true,
          hide_dotfiles = false,
          hide_gitignored = false,
        },
      },
    },
  },

  -- Disable markdownlint — too noisy, keep rendering/LSP without linting errors
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters_by_ft = {
        markdown = {},
      },
    },
  },

  -- Disable gitsigns (git gutter indicators)
  { "lewis6991/gitsigns.nvim", enabled = false },

  -- Disable flash.nvim (jump motion labels)
  { "folke/flash.nvim", enabled = false },

  -- Custom treesitter configuration for requested languages
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        "bash",
        "c",
        "cpp",
        "css",
        "html",
        "java",
        "javascript",
        "json",
        "lua",
        "python",
        "sql",
        "typescript",
        "vim",
        "yaml",
      },
    },
  },
}
