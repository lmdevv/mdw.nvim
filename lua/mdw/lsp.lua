local config = require("mdw.config")
local workspace = require("mdw.workspace")

local M = {}

function M.command()
  return config.get().lsp.command or "markdown-oxide"
end

function M.available()
  return vim.fn.executable(M.command()) == 1
end

function M.owns_rename()
  return config.get().lsp.rename == true
end

function M.attach(bufnr)
  if config.get().lsp.enabled ~= true or not M.available() then
    return false
  end
  if not workspace.is_note_name(vim.api.nvim_buf_get_name(bufnr)) then
    return false
  end
  local root = workspace.resolve(bufnr)
  local clients = vim.lsp.get_clients({ bufnr = bufnr, name = "markdown-oxide" })
  if #clients > 0 then
    return true
  end
  local client = vim.lsp.start({
    name = "markdown-oxide",
    cmd = { M.command() },
    root_dir = root,
  }, { bufnr = bufnr })
  return client ~= nil
end

return M
