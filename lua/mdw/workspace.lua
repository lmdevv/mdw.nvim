local config = require("mdw.config")

local M = {}

local git_cache = {}

local function trim_slash(path)
  if path ~= "/" and path:sub(-1) == "/" then
    return path:sub(1, -2)
  end
  return path
end

function M.normalize(path)
  local absolute = trim_slash(vim.fs.normalize(vim.fn.fnamemodify(path, ":p")))
  local real = vim.uv.fs_realpath(absolute)
  if real then
    return trim_slash(vim.fs.normalize(real))
  end
  return absolute
end

function M.reset()
  git_cache = {}
end

function M.extensions()
  return config.get().notes.extensions
end

function M.is_note_name(name)
  if type(name) ~= "string" or name == "" or name:find("://", 1, true) then
    return false
  end
  local base = vim.fs.basename(name)
  local ext = base:match("%.([^%.]+)$")
  if not ext then
    return false
  end
  ext = ext:lower()
  for _, allowed in ipairs(M.extensions()) do
    if ext == allowed then
      return true
    end
  end
  return false
end

function M.stem(filename)
  local extensions = {}
  for _, ext in ipairs(M.extensions()) do
    extensions[#extensions + 1] = ext
  end
  table.sort(extensions, function(a, b)
    return #a > #b
  end)
  local lower = filename:lower()
  for _, ext in ipairs(extensions) do
    local suffix = "." .. ext
    if lower:sub(-#suffix) == suffix then
      return filename:sub(1, #filename - #suffix)
    end
  end
  return filename
end

local function configured_root()
  local root = config.get().workspace.root
  if type(root) ~= "string" or root == "" then
    return nil
  end
  if root:sub(1, 1) ~= "/" then
    root = vim.fn.getcwd() .. "/" .. root
  end
  return M.normalize(root)
end

local function git_root(dir)
  if git_cache[dir] ~= nil then
    return git_cache[dir] or nil
  end
  local ok, result = pcall(function()
    return vim.system({ "git", "-C", dir, "rev-parse", "--show-toplevel" }, { text = true }):wait()
  end)
  local root = nil
  if ok and result and result.code == 0 then
    local text = vim.trim(result.stdout or "")
    if text ~= "" then
      root = M.normalize(text)
    end
  end
  git_cache[dir] = root or false
  return root
end

function M.anchor(bufnr)
  bufnr = bufnr or 0
  local name = vim.api.nvim_buf_get_name(bufnr)
  if M.is_real_file(name) then
    return vim.fs.dirname(M.normalize(name))
  end
  return M.normalize(vim.fn.getcwd())
end

function M.is_real_file(path)
  return type(path) == "string" and path ~= "" and not path:find("://", 1, true)
end

function M.resolve(bufnr)
  bufnr = bufnr or 0
  local pinned = configured_root()
  if pinned then
    return pinned
  end
  if vim.bo[bufnr].filetype == "mdw-sidebar" then
    local source = vim.b[bufnr].mdw_source
    if type(source) == "string" and source ~= "" then
      local anchor = vim.fs.dirname(M.normalize(source))
      return git_root(anchor) or anchor
    end
  end
  local anchor = M.anchor(bufnr)
  return git_root(anchor) or anchor
end

function M.contains(root, path)
  root = M.normalize(root)
  path = M.normalize(path)
  return path == root or vim.startswith(path, root .. "/")
end

function M.relpath(root, path)
  root = M.normalize(root)
  path = M.normalize(path)
  local rel = vim.fs.relpath(root, path)
  if rel == nil or rel == "" or rel == "." or vim.startswith(rel, "..") then
    return nil
  end
  return rel
end

function M.skipped(relpath)
  for segment in relpath:gmatch("[^/]+") do
    if segment:sub(1, 1) == "." or segment == "node_modules" then
      return true
    end
  end
  return false
end

return M
