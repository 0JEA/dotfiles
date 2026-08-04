return {
  -- Precognition: The HUD that shows where your motions will land
  {
    "tris203/precognition.nvim",
    event = "VeryLazy", -- Only load when needed to keep startup fast
    enabled = false,
    opts = {
      startVisible = true,
      showBlankVirtLine = true,
    },
  },
}
