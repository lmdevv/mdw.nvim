local scan = require("mdw.scan")
local workspace = require("mdw.workspace")

local M = {}

local caches = {}
local rebuilding = {}

local function mtime_of(path)
  local stat = vim.uv.fs_stat(path)
  if not stat or not stat.mtime then
    return nil
  end
  local mtime = stat.mtime
  if type(mtime) == "table" then
    return (mtime.sec or 0) * 1000000000 + (mtime.nsec or 0)
  end
  return mtime
end

local function buffer_text(bufnr)
  return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
end

local function read_file(path)
  local fd = vim.uv.fs_open(path, "r", 438)
  if not fd then
    return nil, "unreadable file"
  end
  local stat = vim.uv.fs_fstat(fd)
  if not stat then
    vim.uv.fs_close(fd)
    return nil, "unreadable file"
  end
  local data = ""
  if stat.size > 0 then
    data = vim.uv.fs_read(fd, stat.size, 0) or ""
  end
  vim.uv.fs_close(fd)
  if type(data) ~= "string" then
    return nil, "unreadable file"
  end
  return data
end

local function empty_cache(root)
  return {
    root = root,
    revision = 0,
    notes = {},
    errors = {},
    mtimes = {},
  }
end

local function store(cache, relpath, path, text, mtime)
  local filename = vim.fs.basename(path)
  local parsed, err = scan.parse(text, filename, workspace.stem(filename))
  cache.mtimes[relpath] = mtime
  if not parsed then
    cache.notes[relpath] = nil
    cache.errors[relpath] = err or "malformed file"
    return
  end
  parsed.path = path
  parsed.relpath = relpath
  cache.notes[relpath] = parsed
  cache.errors[relpath] = nil
end

local function each_file(dir, visit)
  local ok, iter = pcall(vim.fs.dir, dir)
  if not ok or type(iter) ~= "function" then
    return
  end
  for name, typ in iter do
    if name:sub(1, 1) ~= "." and name ~= "node_modules" then
      local path = dir .. "/" .. name
      if typ == "directory" then
        each_file(path, visit)
      elseif typ == "file" and workspace.is_note_name(name) then
        visit(path)
      end
    end
  end
end

local function modified_buffers(root)
  local overlays = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr)
      and vim.bo[bufnr].modified
      and workspace.is_note_name(vim.api.nvim_buf_get_name(bufnr))
    then
      local name = vim.api.nvim_buf_get_name(bufnr)
      local path = workspace.normalize(name)
      local relpath = workspace.relpath(root, path)
      if relpath and not workspace.skipped(relpath) then
        overlays[relpath] = {
          path = path,
          text = buffer_text(bufnr),
        }
      end
    end
  end
  return overlays
end

function M.reset()
  caches = {}
  rebuilding = {}
end

function M.get(root)
  return caches[workspace.normalize(root)]
end

function M.rebuild(root)
  root = workspace.normalize(root)
  rebuilding[root] = true
  local cache = empty_cache(root)
  local overlays = modified_buffers(root)
  each_file(root, function(path)
    path = workspace.normalize(path)
    local relpath = workspace.relpath(root, path)
    if relpath and not workspace.skipped(relpath) then
      local overlay = overlays[relpath]
      if overlay then
        store(cache, relpath, path, overlay.text, mtime_of(path))
        overlays[relpath] = nil
      else
        local text, err = read_file(path)
        if not text then
          cache.errors[relpath] = err
        else
          store(cache, relpath, path, text, mtime_of(path))
        end
      end
    end
  end)
  for relpath, overlay in pairs(overlays) do
    store(cache, relpath, overlay.path, overlay.text, nil)
  end
  cache.revision = (caches[root] and caches[root].revision or 0) + 1
  caches[root] = cache
  rebuilding[root] = nil
  return cache
end

function M.ensure(root)
  root = workspace.normalize(root)
  if caches[root] then
    return caches[root]
  end
  return M.rebuild(root)
end

function M.sync_buffer(bufnr, mode)
  if not workspace.is_note_name(vim.api.nvim_buf_get_name(bufnr)) then
    return
  end
  local root = workspace.resolve(bufnr)
  if rebuilding[root] then
    return
  end
  local cache = caches[root]
  if not cache then
    return
  end
  local path = workspace.normalize(vim.api.nvim_buf_get_name(bufnr))
  local relpath = workspace.relpath(root, path)
  if not relpath or workspace.skipped(relpath) then
    return
  end
  local modified = vim.bo[bufnr].modified
  if mode == "buffer" or modified then
    store(cache, relpath, path, buffer_text(bufnr), mtime_of(path))
    cache.revision = cache.revision + 1
    return
  end
  local mtime = mtime_of(path)
  if mtime == nil then
    cache.notes[relpath] = nil
    cache.errors[relpath] = nil
    cache.mtimes[relpath] = nil
    cache.revision = cache.revision + 1
    return
  end
  if cache.mtimes[relpath] == mtime and cache.notes[relpath] then
    return
  end
  local text, err = read_file(path)
  if not text then
    cache.notes[relpath] = nil
    cache.errors[relpath] = err
  else
    store(cache, relpath, path, text, mtime)
  end
  cache.revision = cache.revision + 1
end

function M.list(root)
  local cache = M.ensure(root)
  local notes = {}
  for _, note in pairs(cache.notes) do
    notes[#notes + 1] = note
  end
  table.sort(notes, function(a, b)
    return a.relpath < b.relpath
  end)
  return notes
end

function M.error_list(root)
  local cache = M.get(root)
  if not cache then
    return {}
  end
  local errors = {}
  for path, message in pairs(cache.errors) do
    errors[#errors + 1] = { path = path, message = message }
  end
  table.sort(errors, function(a, b)
    return a.path < b.path
  end)
  return errors
end

return M
