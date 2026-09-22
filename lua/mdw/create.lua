local config = require("mdw.config")
local index = require("mdw.index")
local obsidian = require("mdw.obsidian")
local ui = require("mdw.ui")
local workspace = require("mdw.workspace")

local M = {}

function M.render(body, vars)
  local warnings = {}
  local rendered = (body or ""):gsub("{{%s*([%w_]+)%s*}}", function(name)
    local value = vars[name]
    if value == nil then
      warnings[#warnings + 1] = name
      return "{{" .. name .. "}}"
    end
    return tostring(value)
  end)
  return rendered, warnings
end

local function template_body(name)
  if name == nil or name == "" then
    return ""
  end
  local templates = config.get().create.templates or {}
  local body = templates[name]
  if type(body) ~= "string" then
    return nil, "unknown template: " .. name
  end
  return body
end

local function vars_for(title, when)
  local stamp = when or os.time()
  return {
    title = title or "",
    date = os.date("%Y-%m-%d", stamp),
    time = os.date("%H:%M", stamp),
  }
end

function M.prepare(opts)
  opts = opts or {}
  local relpath = opts.relpath
  if type(relpath) ~= "string" or relpath == "" or workspace.skipped(relpath) or relpath:find("^/") or relpath:find("%.%.") then
    return nil, "choose a note path inside the workspace"
  end
  if not workspace.is_note_name(relpath) then
    relpath = relpath .. ".md"
  end
  local title = opts.title
  if title == nil or title == "" then
    title = workspace.stem(vim.fs.basename(relpath))
  end
  local template = opts.template
  if template == nil then
    template = config.get().create.default_template
  end
  local backend = opts.backend or config.get().create.backend
  local body, err
  if backend == "obsidian" then
    body = ""
  else
    body, err = template_body(template)
    if body == nil then
      return nil, err
    end
  end
  local rendered, warnings = M.render(body, vars_for(title, opts.when))
  return {
    relpath = relpath,
    title = title,
    template = template,
    body = rendered,
    warnings = warnings,
    backend = backend,
  }
end

local function write_local(root, prepared)
  local path = root .. "/" .. prepared.relpath
  if vim.uv.fs_stat(path) then
    return nil, prepared.relpath .. " already exists"
  end
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local handle = io.open(path, "wb")
  if not handle then
    return nil, "could not write " .. prepared.relpath
  end
  handle:write(prepared.body)
  if prepared.body ~= "" and prepared.body:sub(-1) ~= "\n" then
    handle:write("\n")
  end
  handle:close()
  return path
end

function M.create(opts)
  opts = opts or {}
  local root = opts.root or workspace.resolve(0)
  local prepared, err = M.prepare(opts)
  if not prepared then
    return nil, err
  end
  local path = root .. "/" .. prepared.relpath
  if vim.uv.fs_stat(path) then
    return nil, prepared.relpath .. " already exists"
  end
  if opts.confirm ~= false then
    local prompt = "Create " .. prepared.relpath .. "?"
    if prepared.template and prepared.template ~= "" then
      prompt = "Create " .. prepared.relpath .. " from " .. prepared.template .. "?"
    end
    if not ui.confirm(prompt) then
      return nil, "cancelled"
    end
  end
  if vim.uv.fs_stat(path) then
    return nil, prepared.relpath .. " already exists"
  end
  local written, write_err
  if prepared.backend == "obsidian" then
    written, write_err = obsidian.create(root, prepared.relpath, prepared.template)
  else
    written, write_err = write_local(root, prepared)
  end
  if not written then
    return nil, write_err
  end
  index.rebuild(root)
  if #prepared.warnings > 0 then
    vim.notify("mdw left unknown template fields: " .. table.concat(prepared.warnings, ", "), vim.log.levels.WARN)
  end
  if opts.insert and opts.origin then
    local link = "[[" .. workspace.stem(vim.fs.basename(prepared.relpath)) .. "]]"
    vim.api.nvim_buf_set_text(opts.origin, opts.row or 0, opts.col or 0, opts.row or 0, opts.col or 0, { link })
  end
  return written, nil, prepared
end

return M
