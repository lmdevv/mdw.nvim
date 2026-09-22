-- Isolated init for the mdw test image. Plugins are on packpath before this file runs.
vim.cmd.packloadall()

vim.g.mapleader = " "
vim.g.maplocalleader = " "

require("mini.pick").setup()
require("mdw").setup()

vim.keymap.set("n", "<leader>sn", function()
  require("mdw.pick").search("")
end, { desc = "Search notes" })

vim.keymap.set("n", "<leader>sf", function()
  require("mini.pick").builtin.files()
end, { desc = "Search files" })

vim.keymap.set("n", "<leader>sh", function()
  vim.cmd("checkhealth mdw")
end, { desc = "mdw health" })
