local config = require("mdw.config")
local obsidian = require("mdw.obsidian")
local workspace = require("mdw.workspace")

local M = {}

local function read_json(path)
  local handle = io.open(path, "rb")
  if not handle then
    return nil
  end
  local text = handle:read("*a")
  handle:close()
  local ok, decoded = pcall(vim.json.decode, text)
  if not ok or type(decoded) ~= "table" then
    return nil, "could not read " .. path
  end
  return decoded
end

function M.folder(root)
  local decoded, err = read_json(root .. "/.obsidian/templates.json")
  if err then
    return nil, err
  end
  if type(decoded) ~= "table" or type(decoded.folder) ~= "string" then
    return ""
  end
  local folder = decoded.folder:gsub("^/", ""):gsub("/$", "")
  if folder:find("%.%.") or workspace.skipped(folder) then
    return nil, "template folder escapes the workspace"
  end
  return folder
end

local function walk(dir, prefix, into)
  local ok, iter = pcall(vim.fs.dir, dir)
  if not ok or type(iter) ~= "function" then
    return
  end
  for name, typ in iter do
    if name:sub(1, 1) ~= "." and name ~= "node_modules" then
      local rel = prefix == "" and name or (prefix .. "/" .. name)
      if typ == "directory" then
        walk(dir .. "/" .. name, rel, into)
      elseif typ == "file" and workspace.is_note_name(name) then
        into[#into + 1] = workspace.stem(rel)
      end
    end
  end
end

function M.files(root)
  local folder, err = M.folder(root)
  if not folder then
    return nil, err
  end
  if folder == "" then
    return {}
  end
  local names = {}
  walk(root .. "/" .. folder, "", names)
  table.sort(names)
  return names
end

function M.path(root, name)
  if type(name) ~= "string" or name == "" or name:find("%.%.") or name:find("^/") or name:find("^%./") then
    return nil
  end
  local folder = M.folder(root)
  if type(folder) ~= "string" or folder == "" then
    return nil
  end
  local base = root .. "/" .. folder .. "/" .. name
  for _, ext in ipairs(workspace.extensions()) do
    local path = base .. "." .. ext
    if vim.uv.fs_stat(path) then
      return path
    end
  end
end

function M.read(root, name)
  local configured = (config.get().create.templates or {})[name]
  if type(configured) == "string" then
    return configured
  end
  local path = M.path(root, name)
  if not path then
    return nil, "unknown template: " .. name
  end
  local handle = io.open(path, "rb")
  if not handle then
    return nil, "could not read template: " .. name
  end
  local text = handle:read("*a")
  handle:close()
  return text
end

function M.names(root, backend)
  if backend == "obsidian" then
    return obsidian.templates(root)
  end
  local found = {}
  for name in pairs(config.get().create.templates or {}) do
    found[name] = true
  end
  local files, err = M.files(root)
  if not files then
    return nil, err
  end
  for _, name in ipairs(files) do
    found[name] = true
  end
  local names = {}
  for name in pairs(found) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

return M
