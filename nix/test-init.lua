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
require("mini.pick").setup()
require("mini.statusline").setup({ use_icons = true })

local function type_command(command)
  return function()
    vim.api.nvim_feedkeys(":" .. command, "n", false)
  end
end

local function open_note(path)
  return function()
    vim.cmd.edit(vim.fn.fnameescape(path))
  end
end

require("mini.starter").setup({
  evaluate_single = false,
  header = table.concat({
    "mdw",
    "",
    "This Neovim is only the demo. It does not load your config.",
    "Leader is space. Press Enter on a row.",
  }, "\n"),
  footer = table.concat({
    "rumdl formats and lints. markdown-oxide is the language server.",
    "render-markdown draws the note. File search also matches title, alias, and tag.",
    "",
    "The same guide is in :e ../HOWTO.txt",
  }, "\n"),
  items = {
    { name = "links.md", action = open_note("links.md"), section = "Walk the vault" },
    { name = "exact.md  — title, alias, and tag", action = open_note("exact.md"), section = "Walk the vault" },
    { name = "nested.md  — heading and block", action = open_note("nested.md"), section = "Walk the vault" },
    { name = "label.md  — a label is not an alias", action = open_note("label.md"), section = "Walk the vault" },
    { name = "a/note.md  — ambiguous with b/note.md", action = open_note("a/note.md"), section = "Walk the vault" },
    { name = "misc.md  — tag budget", action = open_note("misc.md"), section = "Walk the vault" },
    { name = "bad.md  — skipped malformed frontmatter", action = open_note("bad.md"), section = "Walk the vault" },
    { name = "../elsewhere/loose.md  — outside this git repo", action = open_note("../elsewhere/loose.md"), section = "Walk the vault" },
    { name = "../other-repo/bee.md  — a second workspace", action = open_note("../other-repo/bee.md"), section = "Walk the vault" },

    { name = ":mdw search", action = function() require("mdw.pick").search("") end, section = "Commands" },
    { name = ":mdw dailies", action = "Mdw dailies", section = "Commands" },
    { name = ":mdw daily", action = "Mdw daily", section = "Commands" },
    { name = ":mdw sidebar on links.md", action = function()
      vim.cmd.edit("links.md")
      require("mdw.sidebar").toggle()
    end, section = "Commands" },
    { name = ":mdw health", action = "checkhealth mdw", section = "Commands" },
    { name = ":mdw new ", action = type_command("mdw new "), section = "Commands" },
    { name = ":mdw rename ", action = type_command("mdw rename "), section = "Commands" },
    { name = ":mdw format", action = "Mdw format", section = "Commands" },
    { name = ":mdw lint", action = "Mdw lint", section = "Commands" },

    { name = "<leader>sn  search notes", action = function() require("mdw.pick").search("") end, section = "Demo keys" },
    { name = "<leader>sf  search files", action = function() require("mini.pick").builtin.files() end, section = "Demo keys" },
    { name = "<leader>sh  health", action = "checkhealth mdw", section = "Demo keys" },
    { name = "<leader>ss  sidebar", action = function() require("mdw.sidebar").toggle() end, section = "Demo keys" },
    { name = "<leader>sd  today's daily note", action = "Mdw daily", section = "Demo keys" },
    { name = "gd  follow the link under the cursor", action = open_note("links.md"), section = "Demo keys" },
  },
})

require("catppuccin").setup({ flavour = "mocha" })
vim.cmd.colorscheme("catppuccin")

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown", "mdx" },
  callback = function()
    vim.wo.conceallevel = 2
    vim.wo.concealcursor = "nc"
    pcall(vim.treesitter.start)
  end,
})

require("mdw").setup({
  search = { enrich_files = true },
  render = { enabled = true },
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
  require("mini.pick").builtin.files()
end, { desc = "Search files" })

vim.keymap.set("n", "<leader>sh", function()
  vim.cmd("checkhealth mdw")
end, { desc = "mdw health" })

vim.keymap.set("n", "<leader>ss", function()
  require("mdw.sidebar").toggle()
end, { desc = "Note sidebar" })

vim.keymap.set("n", "<leader>sd", function()
  vim.cmd("Mdw daily")
end, { desc = "Daily note" })
