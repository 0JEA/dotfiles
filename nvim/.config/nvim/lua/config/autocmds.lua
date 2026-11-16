-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
-- Add any additional autocmds here

-- Bracket matching. The rules and the reasons are at the top of
-- lua/parenmatch.lua.
require("parenmatch").setup()
