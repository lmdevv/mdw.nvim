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
    "Press space. The next key appears.",
    "Press Enter on Open the walkthrough, then follow gd from each note.",
    "This Neovim does not load your config.",
  }, "\n"),
  footer = table.concat({
    "Inline images need a terminal with the Kitty graphics protocol.",
    "rumdl formats and lints. markdown-oxide is the language server.",
  }, "\n"),
  items = {
    { name = "Open the walkthrough", action = open_note("Welcome.md"), section = "Start" },

    { name = "space s n    search notes", action = function()
      require("mdw.pick").search("")
    end, section = "Keys" },
    { name = "space s f    search files", action = function()
      require("mini.pick").builtin.files()
    end, section = "Keys" },
    { name = "space s h    health", action = "checkhealth mdw", section = "Keys" },
    { name = "space s s    sidebar", action = function()
      vim.cmd.edit("Welcome.md")
      require("mdw.sidebar").toggle()
    end, section = "Keys" },
    { name = "space s d    today's daily note", action = "Mdw daily", section = "Keys" },
    { name = "g d          follow the link under the cursor", action = open_note("Welcome.md"), section = "Keys" },
    { name = "Enter, o     continue a list item", action = open_note("Edit.md"), section = "Keys" },
    { name = ">>  <<       nest or unnest a list item", action = open_note("Edit.md"), section = "Keys" },
    { name = "space x      toggle a checkbox", action = open_note("Edit.md"), section = "Keys" },
  },
})

require("catppuccin").setup({ flavour = "mocha" })
vim.cmd.colorscheme("catppuccin")

pcall(function()
  require("image").setup({
    backend = "kitty",
    processor = "magick_cli",
    integrations = {
      markdown = {
        enabled = true,
        download_remote_images = false,
        only_render_image_at_cursor = false,
      },
      asciidoc = { enabled = false },
      typst = { enabled = false },
      neorg = { enabled = false },
      syslang = { enabled = false },
    },
    max_height_window_percentage = 30,
  })
end)

local function rescan_images(buf, tries)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local ok, parser = pcall(vim.treesitter.get_parser, buf, "markdown")
  local inline = ok and parser and parser:children().markdown_inline or nil
  if inline == nil then
    if tries < 20 then
      vim.defer_fn(function()
        rescan_images(buf, tries + 1)
      end, 50)
    end
    return
  end
  parser:parse(true)
  vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = buf })
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown", "mdx" },
  callback = function(event)
    vim.wo.conceallevel = 2
    vim.wo.concealcursor = "nc"
    pcall(vim.treesitter.start, event.buf)
    -- image.nvim scans once, before the markdown inline parser and
    -- render-markdown extmarks exist. A later buffer switch scans again,
    -- which is why the picture only appeared after leaving the note.
    vim.defer_fn(function()
      rescan_images(event.buf, 0)
    end, 200)
  end,
})

require("mdw").setup({
  search = { enrich_files = true },
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
  require("mini.pick").builtin.files()
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
