return {
  -- add tokyonight
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      style = "night",
      -- ── MARIGOLD ────────────────────────────────────────────────────────────
      -- These MUST mirror [config.custom_colors] in
      -- ~/dotfiles/theme/matugen/config.toml. nvim is not part of the matugen
      -- pipeline, so this is the one place the palette is duplicated by hand.
      -- If the editor background ever stops matching the terminal, this drifted.
      --
      -- cyan/teal and magenta/rose stay COOL on purpose — see the note in
      -- config.toml. All-orange syntax highlighting loses hue distinction.
      on_colors = function(c)
        c.bg = "#1a1614"
        c.bg_dark = "#121010"
        c.bg_float = "#121010"
        c.bg_highlight = "#2b2320"
        c.bg_popup = "#121010"
        c.bg_sidebar = "#121010"
        c.bg_statusline = "#121010"
        c.bg_visual = "#4a3428"
        c.fg = "#f5e6d3"
        c.fg_dark = "#d9c7b3"
        c.fg_float = "#f5e6d3"
        c.fg_gutter = "#3d332e"
        c.fg_sidebar = "#d9c7b3"
        c.comment = "#8a7867"
        c.blue = "#ff8c42" -- primary accent, matches ANSI color4
        c.cyan = "#7fb0a0"
        c.teal = "#7fb0a0"
        c.magenta = "#e0879b"
        c.purple = "#e0879b"
        c.green = "#a3b565"
        c.yellow = "#fabd2f"
        c.orange = "#ff6b35"
        c.red = "#f2543d"
        c.border = "#3d332e"
        c.terminal_black = "#75665a"
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
