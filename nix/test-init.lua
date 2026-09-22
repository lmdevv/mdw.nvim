-- Isolated init for the mdw test image. Plugins are on packpath before this file runs.
vim.cmd.packloadall()

vim.g.mapleader = " "
vim.g.maplocalleader = " "

require("mini.pick").setup()
require("mdw").setup({
  create = {
    templates = {
      note = "---\ntitle: {{title}}\n---\n\n# {{title}}\n\n{{date}}\n",
    },
    default_template = "note",
  },
  daily = {
    folder = "daily",
    template = "note",
  },
  lists = {
    maps = {
      continue = "<CR>",
      open = "o",
      nest = ">>",
      unnest = "<<",
      check = "<leader>x",
    },
  },
})

vim.keymap.set("n", "<leader>sn", function()
  require("mdw.pick").search("")
end, { desc = "Search notes" })

vim.keymap.set("n", "<leader>sf", function()
  require("mini.pick").builtin.files()
end, { desc = "Search files" })

vim.keymap.set("n", "<leader>sh", function()
  vim.cmd("checkhealth mdw")
end, { desc = "mdw health" })

vim.keymap.set("n", "<leader>ss", function()
  require("mdw.sidebar").toggle()
end, { desc = "Note sidebar" })

vim.keymap.set("n", "<leader>sd", function()
  local path, err = require("mdw.daily").open("today")
  if not path then
    vim.notify("mdw: " .. (err or "could not open the daily note"), vim.log.levels.ERROR)
  end
end, { desc = "Daily note" })
