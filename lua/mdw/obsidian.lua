local config = require("mdw.config")

local M = {}

function M.command()
  local name = config.get().obsidian.command
  if type(name) ~= "string" or name == "" then
    return "obsidian"
  end
  return name
end

function M.available()
  return vim.fn.executable(M.command()) == 1
end

function M.argv(root, args)
  local full = { M.command(), "vault=" .. root }
  for _, arg in ipairs(args or {}) do
    full[#full + 1] = arg
  end
  return full
end

function M.run(root, args)
  if not M.available() then
    return nil, "obsidian CLI was not found: " .. M.command()
  end
  local result = vim.system(M.argv(root, args), { text = true }):wait()
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
