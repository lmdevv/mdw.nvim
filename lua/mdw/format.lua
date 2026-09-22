local config = require("mdw.config")
local workspace = require("mdw.workspace")

local M = {}

local namespace = vim.api.nvim_create_namespace("mdw-rumdl")

function M.run(cmd, opts)
  return vim.system(cmd, opts):wait()
end

local function tool()
  local command = config.get().format.command or "rumdl"
  if vim.fn.executable(command) ~= 1 then
    return nil, "rumdl was not found: " .. command
  end
  return command
end

local function filename(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if workspace.is_note_name(name) then
    local root = workspace.resolve(bufnr)
    return workspace.relpath(root, name) or vim.fs.basename(name), root
  end
  return "note.md", vim.fn.getcwd()
end

local function severity(name)
  if name == "error" then
    return vim.diagnostic.severity.ERROR
  end
  if name == "info" then
    return vim.diagnostic.severity.INFO
  end
  return vim.diagnostic.severity.WARN
end

function M.format(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if config.get().format.enabled ~= true then
    return nil, "formatting is disabled"
  end
  local command, err = tool()
  if not command then
    return nil, err
  end
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  local name, root = filename(bufnr)
  local result = M.run({
    command,
    "fmt",
    "--stdin",
    "--stdin-filename",
    name,
    "--silent",
    "--color",
    "never",
  }, { stdin = text, cwd = root, text = true })
  if not vim.api.nvim_buf_is_valid(bufnr) or vim.api.nvim_buf_get_changedtick(bufnr) ~= tick then
    return nil, "the buffer changed while rumdl was running"
  end
  if not result or result.code ~= 0 then
    local message = result and vim.trim(result.stderr ~= "" and result.stderr or result.stdout or "") or "rumdl failed"
    if message == "" then
      message = "rumdl failed"
    end
    return nil, message
  end
  local formatted = result.stdout or ""
  if formatted:sub(-1) == "\n" then
    formatted = formatted:sub(1, -2)
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(formatted, "\n", { plain = true }))
  return true
end

function M.lint(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if config.get().format.enabled ~= true or config.get().format.lint ~= true then
    vim.diagnostic.reset(namespace, bufnr)
    return true
  end
  local command, err = tool()
  if not command then
    return nil, err
  end
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  local name, root = filename(bufnr)
  local result = M.run({
    command,
    "check",
    "--stdin",
    "--stdin-filename",
    name,
    "--output-format",
    "json",
    "--color",
    "never",
  }, { stdin = text, cwd = root, text = true })
  if not vim.api.nvim_buf_is_valid(bufnr) or vim.api.nvim_buf_get_changedtick(bufnr) ~= tick then
    return nil, "the buffer changed while rumdl was running"
  end
  local ok, decoded = pcall(vim.json.decode, result and result.stdout or "")
  if not ok or type(decoded) ~= "table" then
    if result and result.code ~= 0 then
      return nil, vim.trim(result.stderr or "") ~= "" and vim.trim(result.stderr) or "rumdl check failed"
    end
    vim.diagnostic.reset(namespace, bufnr)
    return true
  end
  local items = {}
  for _, item in ipairs(decoded) do
    if type(item) == "table" and type(item.line) == "number" then
      items[#items + 1] = {
        lnum = math.max(item.line - 1, 0),
        col = math.max((item.column or 1) - 1, 0),
        message = tostring(item.rule or "rumdl") .. ": " .. tostring(item.message or ""),
        severity = severity(item.severity),
        source = "rumdl",
      }
    end
  end
  vim.diagnostic.set(namespace, bufnr, items)
  return true
end

function M.available()
  return vim.fn.executable(config.get().format.command or "rumdl") == 1
end

return M
