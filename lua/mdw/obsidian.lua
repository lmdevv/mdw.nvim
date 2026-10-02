local config = require("mdw.config")
local workspace = require("mdw.workspace")

local M = {}

function M.command()
  local name = config.get().obsidian.command
  if type(name) ~= "string" or name == "" then
    name = "obsidian"
  end
  if name == "obsidian" and vim.fn.executable("obsidian-cli") == 1 then
    return "obsidian-cli"
  end
  return name
end

function M.available()
  return vim.fn.executable(M.command()) == 1
end

function M.argv(args)
  local full = { M.command() }
  for _, arg in ipairs(args or {}) do
    full[#full + 1] = arg
  end
  return full
end

function M.run(root, args)
  if not M.available() then
    return nil, "obsidian CLI was not found: "
      .. M.command()
      .. "; enable Settings > General > Command line interface in Obsidian"
  end
  local ok, result = pcall(function()
    return vim.system(M.argv(args), { cwd = root, text = true }):wait(10000)
  end)
  if not ok then
    return nil, tostring(result)
  end
  if result.code == 124 then
    return nil, "obsidian CLI timed out; enable Settings > General > Command line interface and check obsidian.command"
  end
  if result.code ~= 0 then
    local message = vim.trim(result.stderr ~= "" and result.stderr or result.stdout or "")
    if message == "" then
      message = "obsidian command failed"
    end
    return nil, message
  end
  return result
end

function M.create(root, relpath, template_name)
  local args = { "create", "path=" .. relpath }
  if type(template_name) == "string" and template_name ~= "" then
    args[#args + 1] = "template=" .. template_name
  end
  local result, err = M.run(root, args)
  if not result then
    return nil, err
  end
  local path = root .. "/" .. relpath
  if not vim.uv.fs_stat(path) then
    return nil, "obsidian create did not write " .. relpath
  end
  return path
end

function M.open(root, relpath)
  return M.run(root, { "open", "path=" .. relpath })
end

function M.vault_root(bufnr)
  local markers = vim.fs.find(".obsidian", { path = workspace.anchor(bufnr), upward = true, type = "directory" })
  return markers[1] and workspace.normalize(vim.fs.dirname(markers[1])) or nil
end

function M.open_current(bufnr, preview)
  bufnr = bufnr or 0
  local path = vim.api.nvim_buf_get_name(bufnr)
  if vim.bo[bufnr].buftype ~= "" or not workspace.is_note_name(path) then
    return nil, "open a note first"
  end
  local root = M.vault_root(bufnr)
  if not root then
    return nil, "current note is not inside an Obsidian vault (.obsidian directory not found)"
  end
  local relpath = workspace.relpath(root, path)
  if not relpath then
    return nil, "current note is outside the Obsidian vault"
  end
  local stat = vim.uv.fs_stat(path)
  if vim.bo[bufnr].modified or not stat or stat.type ~= "file" then
    return nil, "save the current note before opening it in Obsidian (:write)"
  end
  local result, err = M.open(root, relpath)
  if not result or not preview then
    return result, err
  end
  local code = "(async () => { const file = app.vault.getFileByPath("
    .. vim.json.encode(relpath)
    .. "); if (!file) throw new Error('Note not found in Obsidian'); "
    .. "await app.workspace.getLeaf(false).openFile(file, {state: {mode: 'preview'}, active: true}); })()"
  return M.run(root, { "eval", "code=" .. code })
end

function M.templates(root)
  local result, err = M.run(root, { "templates" })
  if not result then
    return nil, err
  end
  local names = {}
  local seen = {}
  for line in (result.stdout or ""):gmatch("[^\r\n]+") do
    line = vim.trim(line):gsub("^[-*]%s+", "")
    line = line:gsub("%.md$", ""):gsub("%.markdown$", "")
    if line ~= "" and not seen[line] then
      seen[line] = true
      names[#names + 1] = line
    end
  end
  table.sort(names)
  return names
end

return M
