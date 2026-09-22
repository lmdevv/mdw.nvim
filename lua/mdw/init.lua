local compat = require("mdw.compat")
local config = require("mdw.config")
local index = require("mdw.index")
local pick = require("mdw.pick")
local workspace = require("mdw.workspace")

local M = {}

local USAGE = table.concat({
  "Usage:",
  "  :Mdw health",
  "  :Mdw search [query]",
  "  :Mdw index",
}, "\n")

local function on_buffer(event)
  local mode = (event.event == "TextChanged" or event.event == "TextChangedI" or event.event == "BufWritePost")
      and "buffer"
    or "auto"
  index.sync_buffer(event.buf, mode)
end

local function complete(arglead, cmdline)
  local before = cmdline:sub(1, #cmdline - #arglead)
  if before:match("^%s*Mdw%s+%S") then
    return {}
  end
  local commands = { "health", "search", "index" }
  local matches = {}
  for _, name in ipairs(commands) do
    if vim.startswith(name, arglead) then
      matches[#matches + 1] = name
    end
  end
  return matches
end

local function dispatch(args)
  local sub, rest = args:match("^(%S+)%s*(.*)$")
  if sub == nil then
    vim.notify(USAGE, vim.log.levels.INFO)
    return
  end
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
  else
    vim.notify("Unknown mdw command: " .. sub .. "\n" .. USAGE, vim.log.levels.ERROR)
  end
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
  pcall(vim.api.nvim_del_user_command, "Mdw")
  vim.api.nvim_create_user_command("Mdw", function(cmd)
    dispatch(vim.trim(cmd.args or ""))
  end, {
    nargs = "*",
    complete = complete,
    desc = "Markdown workspace search, index, and health",
  })
  pick.configure(config.get().search.enrich_files)
end

function M.search(query)
  local root = workspace.resolve(0)
  return require("mdw.search").query(root, query or "")
end

function M.rebuild()
  return index.rebuild(workspace.resolve(0))
end

return M
