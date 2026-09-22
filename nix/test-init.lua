-- Isolated demo. These plugins and keys are not part of mdw itself.
vim.cmd.packloadall()

vim.g.mapleader = " "
vim.g.maplocalleader = " "

vim.opt.termguicolors = true
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.signcolumn = "yes"
vim.opt.cursorline = true
vim.opt.wrap = true
vim.opt.linebreak = true
vim.opt.scrolloff = 4
vim.opt.splitright = true
vim.opt.winborder = "rounded"
vim.opt.fillchars = { eob = " " }
vim.opt.list = false

require("mini.icons").setup()
require("mini.statusline").setup({ use_icons = true })

require("snacks").setup({
  image = {
    doc = {
      inline = true,
      max_width = 18,
      max_height = 10,
    },
    math = { enabled = false },
  },
  picker = {},
  dashboard = {
    width = 44,
    preset = {
      header = "mdw",
    },
    sections = {
      { section = "header" },
      {
        padding = 1,
        key = "o",
        desc = "Open the walkthrough",
        action = ":edit Welcome.md",
      },
    },
  },
})

require("catppuccin").setup({ flavour = "mocha" })
vim.cmd.colorscheme("catppuccin")

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown", "mdx" },
  callback = function(event)
    vim.wo.conceallevel = 2
    vim.wo.concealcursor = "nc"
    pcall(vim.treesitter.start, event.buf)
  end,
})

require("mdw").setup({
  search = { picker = "snacks", enrich_files = true },
  render = {
    enabled = true,
    opts = {
      link = { image = "" },
    },
  },
  lsp = { enabled = true },
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
  Snacks.picker.files()
end, { desc = "Search files" })

vim.keymap.set("n", "<leader>sh", function()
  vim.cmd("checkhealth mdw")
end, { desc = "Health" })

vim.keymap.set("n", "<leader>ss", function()
  require("mdw.sidebar").toggle()
end, { desc = "Sidebar" })

vim.keymap.set("n", "<leader>sd", function()
  vim.cmd("Mdw daily")
end, { desc = "Today's daily note" })

local miniclue = require("mini.clue")
miniclue.setup({
  triggers = {
    { mode = "n", keys = "<Leader>" },
    { mode = "n", keys = "g" },
  },
  clues = {
    { mode = "n", keys = "<Leader>s", desc = "+Show" },
    miniclue.gen_clues.g(),
  },
  window = {
    delay = 0,
    config = { width = "auto" },
  },
})

vim.api.nvim_create_autocmd("BufEnter", {
  callback = function()
    pcall(miniclue.ensure_buf_triggers)
  end,
})
