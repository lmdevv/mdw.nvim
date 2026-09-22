local compat = require("mdw.compat")
local config = require("mdw.config")
local index = require("mdw.index")
local pick = require("mdw.pick")
local workspace = require("mdw.workspace")

local M = {}

local COMMANDS = {
  "health",
  "search",
  "index",
  "follow",
  "sidebar",
  "outline",
  "backlinks",
  "outgoing",
  "qf",
  "trouble",
  "rename",
  "move",
  "new",
  "daily",
  "property",
  "aliases",
  "tags",
  "obsidian",
  "format",
  "lint",
  "image",
  "list",
}

local USAGE = table.concat({
  "Usage:",
  "  :mdw health",
  "  :mdw search [query]",
  "  :mdw index",
  "  :mdw follow",
  "  :mdw sidebar",
  "  :mdw outline | backlinks | outgoing",
  "  :mdw qf [outline|backlinks|outgoing]",
  "  :mdw rename {path}",
  "  :mdw new {path}",
  "  :mdw daily [today|yesterday|tomorrow|prev|next|YYYY-MM-DD]",
  "  :mdw property {key} {value}",
  "  :mdw aliases {names}",
  "  :mdw tags {names}",
  "  :mdw obsidian",
  "  :mdw format",
  "  :mdw lint",
  "  :mdw image",
  "  :mdw list continue | nest | unnest | check",
}, "\n")

local function map_follow(bufnr)
  if config.get().navigation.gd ~= true then
    return
  end
  if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].filetype == "mdw-sidebar" then
    return
  end
  if not workspace.is_note_name(vim.api.nvim_buf_get_name(bufnr)) then
    return
  end
  vim.keymap.set("n", "gd", function()
    if require("mdw.nav").follow(bufnr) then
      return
    end
    local clients = vim.lsp.get_clients({ bufnr = bufnr })
    if #clients > 0 then
      vim.lsp.buf.definition()
    end
  end, { buffer = bufnr, desc = "Follow mdw link or LSP definition" })
end

local function on_buffer(event)
  local mode = (event.event == "TextChanged" or event.event == "TextChangedI" or event.event == "BufWritePost")
      and "buffer"
    or "auto"
  index.sync_buffer(event.buf, mode)
  map_follow(event.buf)
  require("mdw.lists").map(event.buf)
  require("mdw.lsp").attach(event.buf)
  require("mdw.sidebar").on_note(event.buf)
end

local function on_write(event)
  local format = require("mdw.format")
  local cfg = config.get().format
  if cfg.enabled ~= true then
    return
  end
  if event.event == "BufWritePre" and cfg.format_on_save then
    local ok, err = format.format(event.buf)
    if not ok then
      vim.notify("mdw: " .. (err or "format failed"), vim.log.levels.ERROR)
    end
  elseif event.event == "BufWritePost" and cfg.lint and format.available() then
    local ok, err = format.lint(event.buf)
    if not ok then
      vim.notify("mdw: " .. (err or "lint failed"), vim.log.levels.ERROR)
    end
  end
end

local LIST_ACTIONS = { "continue", "nest", "unnest", "check" }

local function complete(arglead, cmdline)
  local before = cmdline:sub(1, #cmdline - #arglead)
  if before:match("^%s*[Mm]dw%s+list%s+$") then
    local matches = {}
    for _, name in ipairs(LIST_ACTIONS) do
      if vim.startswith(name, arglead) then
        matches[#matches + 1] = name
      end
    end
    return matches
  end
  if before:match("^%s*[Mm]dw%s+%S") then
    return {}
  end
  local matches = {}
  for _, name in ipairs(COMMANDS) do
    if vim.startswith(name, arglead) then
      matches[#matches + 1] = name
    end
  end
  return matches
end

local function current_note()
  return require("mdw.relations").current_relpath(0)
end

local function show_list(view, use_trouble)
  local root, relpath = current_note()
  if not root or not relpath then
    vim.notify("mdw: open a note first", vim.log.levels.ERROR)
    return
  end
  require("mdw.relations").quickfix(root, view, relpath)
  if use_trouble then
    local ok, trouble = pcall(require, "trouble")
    if ok and type(trouble.open) == "function" then
      trouble.open("quickfix")
      return
    end
    vim.notify("mdw: Trouble is not installed, showing the quickfix list", vim.log.levels.INFO)
  end
  vim.cmd("copen")
end

local function list_words(text)
  local items = {}
  for item in (text or ""):gmatch("[^,%s]+") do
    items[#items + 1] = item
  end
  return items
end

local function list_aliases(text)
  text = text or ""
  if text:find(",", 1, true) then
    local items = {}
    for item in text:gmatch("[^,]+") do
      item = vim.trim(item)
      if item ~= "" then
        items[#items + 1] = item
      end
    end
    return items
  end
  text = vim.trim(text)
  if text == "" then
    return {}
  end
  return { text }
end

local function edit_meta(key, value)
  local ok, err = require("mdw.meta").edit_buffer(0, key, value)
  if not ok then
    vim.notify("mdw: " .. (err or "could not edit frontmatter"), vim.log.levels.ERROR)
    return
  end
  index.sync_buffer(vim.api.nvim_get_current_buf(), "buffer")
end

local function dispatch(args, line1, line2)
  local sub, rest = args:match("^(%S+)%s*(.*)$")
  if sub == nil then
    vim.notify(USAGE, vim.log.levels.INFO)
    return
  end
  rest = vim.trim(rest or "")
  if sub == "health" then
    vim.cmd("checkhealth mdw")
  elseif sub == "search" then
    pick.search(rest)
  elseif sub == "index" then
    local root = workspace.resolve(0)
    local cache = index.rebuild(root)
    local errors = index.error_list(root)
    vim.notify(
      string.format("mdw indexed %d notes in %s (%d skipped)", vim.tbl_count(cache.notes), root, #errors),
      vim.log.levels.INFO
    )
  elseif sub == "follow" then
    if not require("mdw.nav").follow() then
      vim.notify("mdw: cursor is not on a note link", vim.log.levels.WARN)
    end
  elseif sub == "sidebar" then
    require("mdw.sidebar").toggle()
  elseif sub == "outline" or sub == "backlinks" or sub == "outgoing" then
    show_list(sub, false)
  elseif sub == "qf" or sub == "trouble" then
    local view = rest ~= "" and rest or "backlinks"
    if view ~= "outline" and view ~= "backlinks" and view ~= "outgoing" then
      vim.notify("mdw: use outline, backlinks, or outgoing", vim.log.levels.ERROR)
      return
    end
    show_list(view, sub == "trouble")
  elseif sub == "rename" or sub == "move" then
    local root, relpath = current_note()
    if not root or not relpath then
      vim.notify("mdw: open a note first", vim.log.levels.ERROR)
      return
    end
    local ok, err = require("mdw.refactor").rename(root, relpath, rest)
    if not ok then
      vim.notify("mdw: " .. (err or "rename failed"), vim.log.levels.ERROR)
    end
  elseif sub == "new" then
    local written, err = require("mdw.create").create({ relpath = rest, insert = false })
    if not written then
      vim.notify("mdw: " .. (err or "could not create the note"), vim.log.levels.ERROR)
      return
    end
    vim.cmd.edit(vim.fn.fnameescape(written))
  elseif sub == "daily" then
    local path, err = require("mdw.daily").open(rest)
    if not path then
      vim.notify("mdw: " .. (err or "could not open the daily note"), vim.log.levels.ERROR)
    end
  elseif sub == "property" then
    local key, value = rest:match("^(%S+)%s*(.*)$")
    if not key or value == "" then
      vim.notify("mdw: property needs a key and a value", vim.log.levels.ERROR)
      return
    end
    edit_meta(key, value)
  elseif sub == "aliases" then
    edit_meta("aliases", list_aliases(rest))
  elseif sub == "tags" then
    edit_meta("tags", list_words(rest))
  elseif sub == "obsidian" then
    local root, relpath = current_note()
    if not root or not relpath then
      vim.notify("mdw: open a note first", vim.log.levels.ERROR)
      return
    end
    local ok, err = require("mdw.obsidian").open(root, relpath)
    if not ok then
      vim.notify("mdw: " .. (err or "could not open Obsidian"), vim.log.levels.ERROR)
    end
  elseif sub == "format" then
    local ok, err = require("mdw.format").format()
    if not ok then
      vim.notify("mdw: " .. (err or "format failed"), vim.log.levels.ERROR)
    end
  elseif sub == "lint" then
    local ok, err = require("mdw.format").lint()
    if not ok then
      vim.notify("mdw: " .. (err or "lint failed"), vim.log.levels.ERROR)
    end
  elseif sub == "image" then
    local path, err = require("mdw.edit").paste_image()
    if not path then
      vim.notify("mdw: " .. (err or "could not paste an image"), vim.log.levels.ERROR)
    end
  elseif sub == "list" then
    local action = vim.trim(rest or "")
    local lists = require("mdw.lists")
    if action == "continue" then
      lists.continue()
    elseif action == "nest" then
      lists.nest(line1, line2)
    elseif action == "unnest" then
      lists.unnest(line1, line2)
    elseif action == "check" then
      lists.check(line1, line2)
    else
      vim.notify("mdw: list needs continue, nest, unnest, or check", vim.log.levels.ERROR)
    end
  else
    vim.notify("Unknown mdw command: " .. sub .. "\n" .. USAGE, vim.log.levels.ERROR)
  end
end

function M.typed_mdw(line)
  return line:match("^%s*mdw$") ~= nil
    or line:match("^%s*'<,'>%s*mdw$") ~= nil
    or line:match("^%s*%%%s*mdw$") ~= nil
    or line:match("^%s*[%d%.%$]+,?[%d%.%$]*%s*mdw$") ~= nil
end

function M.command_abbrev()
  if vim.fn.getcmdtype() == ":" and M.typed_mdw(vim.fn.getcmdline()) then
    return "Mdw"
  end
  return "mdw"
end

function M.setup(opts)
  if not compat.supported() then
    error("mdw requires Neovim 0.11 or newer (this is " .. compat.string() .. ")")
  end
  config.apply(opts)
  workspace.reset()
  index.reset()
  local group = vim.api.nvim_create_augroup("mdw", { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWritePost", "BufEnter", "FocusGained" }, {
    group = group,
    callback = on_buffer,
  })
  vim.api.nvim_create_autocmd({ "BufWritePre", "BufWritePost" }, {
    group = group,
    callback = on_write,
  })
  pcall(vim.api.nvim_del_user_command, "Mdw")
  pcall(vim.cmd, "cunabbrev mdw")
  vim.cmd("cnoreabbrev <expr> mdw v:lua.require('mdw').command_abbrev()")
  vim.api.nvim_create_user_command("Mdw", function(cmd)
    dispatch(vim.trim(cmd.args or ""), cmd.line1, cmd.line2)
  end, {
    nargs = "*",
    range = true,
    complete = complete,
    desc = "Markdown workspace notes",
  })
  pick.configure(config.get().search.enrich_files)
  require("mdw.render").reset()
  require("mdw.render").configure()
end

function M.search(query)
  local root = workspace.resolve(0)
  return require("mdw.search").query(root, query or "")
end

function M.rebuild()
  return index.rebuild(workspace.resolve(0))
end

return M
