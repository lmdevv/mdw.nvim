local config = require("mdw.config")
local index = require("mdw.index")
local obsidian = require("mdw.obsidian")
local ui = require("mdw.ui")
local workspace = require("mdw.workspace")

local M = {}

local MOMENT = {
  { "YYYY", "%Y" },
  { "YY", "%y" },
  { "MM", "%m" },
  { "DD", "%d" },
  { "HH", "%H" },
  { "mm", "%M" },
  { "ss", "%S" },
}

local function moment(fmt, stamp, fallback)
  if fmt == "" then
    return os.date(fallback, stamp)
  end
  local lua = {}
  local index = 1
  while index <= #fmt do
    local matched = false
    for _, pair in ipairs(MOMENT) do
      local token = pair[1]
      if fmt:sub(index, index + #token - 1) == token then
        lua[#lua + 1] = pair[2]
        index = index + #token
        matched = true
        break
      end
    end
    if not matched then
      local char = fmt:sub(index, index)
      if char:match("%a") or char == "%" then
        return nil
      end
      lua[#lua + 1] = char
      index = index + 1
    end
  end
  return os.date(table.concat(lua), stamp)
end

function M.render(body, vars)
  vars = vars or {}
  local stamp = vars._stamp or os.time()
  local warnings = {}
  local rendered = (body or ""):gsub("{{%s*([%w_]+)%s*:?%s*([^}]-)%s*}}", function(name, fmt)
    fmt = vim.trim(fmt or "")
    if name == "date" or name == "time" then
      local fallback = name == "date" and "%Y-%m-%d" or "%H:%M"
      local value = moment(fmt, stamp, fallback)
      if value then
        return value
      end
    elseif fmt == "" and vars[name] ~= nil then
      return tostring(vars[name])
    end
    warnings[#warnings + 1] = name
    if fmt == "" then
      return "{{" .. name .. "}}"
    end
    return "{{" .. name .. ":" .. fmt .. "}}"
  end)
  return rendered, warnings
end

local function note_relpath(relpath)
  if type(relpath) ~= "string" or relpath == "" or workspace.skipped(relpath) or relpath:find("^/") or relpath:find("%.%.") then
    return nil, "choose a note path inside the workspace"
  end
  if not workspace.is_note_name(relpath) then
    relpath = relpath .. ".md"
  end
  return relpath
end

local function template_body(root, name)
  if name == nil or name == "" then
    return ""
  end
  return require("mdw.templates").read(root, name)
end

local function vars_for(title, when)
  local stamp = when or os.time()
  return {
    title = title or "",
    date = os.date("%Y-%m-%d", stamp),
    time = os.date("%H:%M", stamp),
    _stamp = stamp,
  }
end

function M.parse_args(text)
  text = text or ""
  local found = {}
  local function consume(source)
    for _, key in ipairs({ "template", "backend" }) do
      local patterns = {
        "^" .. key .. '="([^"]*)"%s*',
        "%s+" .. key .. '="([^"]*)"',
        "^" .. key .. "=(%S+)%s*",
        "%s+" .. key .. "=(%S+)",
      }
      for _, pattern in ipairs(patterns) do
        local value = source:match(pattern)
        if value ~= nil then
          found[key] = value
          return (source:gsub(pattern, " ", 1)), true
        end
      end
    end
    return source, false
  end
  local again = true
  while again do
    text, again = consume(text)
  end
  return vim.trim(text), found.template, found.backend
end

function M.prepare(opts)
  opts = opts or {}
  local relpath, rel_err = note_relpath(opts.relpath)
  if not relpath then
    return nil, rel_err
  end
  local title = opts.title
  if title == nil or title == "" then
    title = workspace.stem(vim.fs.basename(relpath))
  end
  local template = opts.template
  if template == "" then
    template = nil
  elseif template == nil then
    template = config.get().create.default_template
  end
  local backend = opts.backend or config.get().create.backend
  if backend ~= "local" and backend ~= "obsidian" then
    return nil, "backend must be local or obsidian"
  end
  local body, err
  if backend == "obsidian" then
    body = ""
  else
    body, err = template_body(opts.root, template)
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

function M.start(opts, done)
  opts = vim.tbl_extend("force", {}, opts or {})
  local root = opts.root or workspace.resolve(0)
  opts.root = root
  local relpath, rel_err = note_relpath(opts.relpath)
  if not relpath then
    done(nil, rel_err)
    return
  end
  opts.relpath = relpath
  if vim.uv.fs_stat(root .. "/" .. relpath) then
    done(nil, relpath .. " already exists")
    return
  end
  local backend = opts.backend or config.get().create.backend
  if opts.template == nil and config.get().create.default_template == nil then
    local names, err = require("mdw.templates").names(root, backend)
    if not names then
      done(nil, err)
      return
    end
    if #names > 1 then
      local items = {}
      for _, name in ipairs(names) do
        local chosen = name
        items[#items + 1] = {
          text = chosen,
          choose = function()
            local next_opts = vim.tbl_extend("force", {}, opts)
            next_opts.template = chosen
            local written, write_err, prepared = M.create(next_opts)
            done(written, write_err, prepared)
          end,
        }
      end
      items[#items + 1] = {
        text = "(blank)",
        choose = function()
          local next_opts = vim.tbl_extend("force", {}, opts)
          next_opts.template = ""
          local written, write_err, prepared = M.create(next_opts)
          done(written, write_err, prepared)
        end,
      }
      ui.choose("mdw templates", items)
      return
    end
    if #names == 1 then
      opts.template = names[1]
    end
  end
  local written, write_err, prepared = M.create(opts)
  done(written, write_err, prepared)
end

function M.create(opts)
  opts = opts or {}
  local root = opts.root or workspace.resolve(0)
  opts.root = root
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
