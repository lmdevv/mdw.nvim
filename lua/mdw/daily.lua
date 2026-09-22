local config = require("mdw.config")
local create = require("mdw.create")
local workspace = require("mdw.workspace")

local M = {}

local FORMATS = {
  ["YYYY-MM-DD"] = "%Y-%m-%d",
  ["%Y-%m-%d"] = "%Y-%m-%d",
}

local function read_obsidian(root)
  local path = root .. "/.obsidian/daily-notes.json"
  local handle = io.open(path, "rb")
  if not handle then
    return nil
  end
  local text = handle:read("*a")
  handle:close()
  local ok, decoded = pcall(vim.json.decode, text)
  if not ok or type(decoded) ~= "table" then
    return nil, "could not read .obsidian/daily-notes.json"
  end
  return {
    format = decoded.format,
    folder = decoded.folder,
    template = decoded.template,
  }
end

function M.spec(root)
  local cfg = config.get().daily
  local imported, err = nil, nil
  if config.get().obsidian.import_daily then
    imported, err = read_obsidian(root)
    if err then
      return nil, err
    end
  end
  local format = cfg.format
  if format == nil and imported and imported.format and imported.format ~= "" then
    format = imported.format
  end
  format = format or "YYYY-MM-DD"
  local lua_format = FORMATS[format]
  if not lua_format then
    return nil, "unsupported daily format: " .. format
  end
  local folder = cfg.folder
  if folder == nil then
    folder = imported and imported.folder or ""
  end
  if folder == nil then
    folder = ""
  end
  folder = folder:gsub("^/", ""):gsub("/$", "")
  local template = cfg.template
  if template == nil and imported then
    template = imported.template
  end
  if template == "" then
    template = nil
  end
  return {
    format = format,
    lua_format = lua_format,
    folder = folder,
    template = template,
  }
end

local function stamp_from_parts(year, month, day)
  return os.time({ year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = 12 })
end

function M.parse_when(when)
  if when == nil or when == "" or when == "today" then
    return os.time(), "open"
  end
  if when == "yesterday" then
    local now = os.date("*t")
    now.day = now.day - 1
    return os.time(now), "open"
  end
  if when == "tomorrow" then
    local now = os.date("*t")
    now.day = now.day + 1
    return os.time(now), "open"
  end
  if when == "prev" or when == "next" then
    return os.time(), when
  end
  local year, month, day = when:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  if year then
    return stamp_from_parts(year, month, day), "open"
  end
  return nil, "use today, yesterday, tomorrow, prev, next, or YYYY-MM-DD"
end

function M.relpath(spec, stamp)
  local name = os.date(spec.lua_format, stamp) .. ".md"
  if spec.folder ~= "" then
    return spec.folder .. "/" .. name
  end
  return name
end

local function daily_dates(root, spec)
  if spec.format ~= "YYYY-MM-DD" and spec.format ~= "%Y-%m-%d" then
    return nil, "prev and next require YYYY-MM-DD"
  end
  local dir = root
  if spec.folder ~= "" then
    dir = root .. "/" .. spec.folder
  end
  local dates = {}
  local ok, iter = pcall(vim.fs.dir, dir)
  if ok and type(iter) == "function" then
    for name, typ in iter do
      local date = typ == "file" and name:match("^(%d%d%d%d%-%d%d%-%d%d)%.md$") or nil
      if date then
        dates[#dates + 1] = date
      end
    end
  end
  table.sort(dates)
  return dates
end

function M.neighbor(root, spec, when, step)
  local dates, err = daily_dates(root, spec)
  if not dates then
    return nil, err
  end
  local origin = os.date("%Y-%m-%d", when)
  local name = vim.api.nvim_buf_get_name(0)
  local current = workspace.is_note_name(name) and vim.fs.basename(name):match("^(%d%d%d%d%-%d%d%-%d%d)%.md$") or nil
  if current then
    origin = current
  end
  local pick = nil
  if step < 0 then
    for _, date in ipairs(dates) do
      if date < origin then
        pick = date
      end
    end
  else
    for _, date in ipairs(dates) do
      if date > origin and not pick then
        pick = date
      end
    end
  end
  if not pick then
    return nil, "no daily note in that direction"
  end
  if spec.folder ~= "" then
    return spec.folder .. "/" .. pick .. ".md"
  end
  return pick .. ".md"
end

function M.open(when, opts)
  opts = opts or {}
  local root = opts.root or workspace.resolve(0)
  local spec, spec_err = M.spec(root)
  if not spec then
    return nil, spec_err
  end
  local stamp, mode = M.parse_when(when)
  if not stamp then
    return nil, mode
  end
  local relpath
  if mode == "prev" or mode == "next" then
    local neighbor, err = M.neighbor(root, spec, stamp, mode == "prev" and -1 or 1)
    if not neighbor then
      return nil, err
    end
    relpath = neighbor
  else
    relpath = M.relpath(spec, stamp)
  end
  local path = root .. "/" .. relpath
  if vim.uv.fs_stat(path) or mode == "prev" or mode == "next" then
    vim.cmd.edit(vim.fn.fnameescape(path))
    return path
  end
  local title = os.date(spec.lua_format, stamp)
  local written, err = create.create({
    root = root,
    relpath = relpath,
    title = title,
    template = spec.template,
    when = stamp,
    confirm = opts.confirm ~= false,
    backend = opts.backend,
  })
  if not written then
    return nil, err
  end
  vim.cmd.edit(vim.fn.fnameescape(written))
  return written
end

return M
