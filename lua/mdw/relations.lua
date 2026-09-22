local index = require("mdw.index")
local resolve = require("mdw.resolve")
local workspace = require("mdw.workspace")

local M = {}

local function context(note, line)
  local path = note.path
  if type(path) ~= "string" then
    return ""
  end
  local bufnr = vim.fn.bufnr(path)
  local text
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    text = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1]
  end
  if text == nil then
    local fd = vim.uv.fs_open(path, "r", 438)
    if not fd then
      return ""
    end
    local stat = vim.uv.fs_fstat(fd)
    local data = ""
    if stat and stat.size > 0 then
      data = vim.uv.fs_read(fd, stat.size, 0) or ""
    end
    vim.uv.fs_close(fd)
    local lines = vim.split(data, "\n", { plain = true })
    text = lines[line] or ""
  end
  text = vim.trim(text or "")
  if vim.fn.strchars(text) > 80 then
    text = vim.fn.strcharpart(text, 0, 79) .. "…"
  end
  return text
end

function M.outline(note)
  local items = {}
  for _, heading in ipairs(note and note.headings or {}) do
    items[#items + 1] = {
      path = note.path,
      relpath = note.relpath,
      line = heading.line,
      col = 1,
      text = string.rep("  ", math.max(heading.level - 1, 0)) .. heading.text,
      kind = "outline",
    }
  end
  return items
end

function M.outgoing(root, note)
  local items = {}
  if not note then
    return items
  end
  for _, link in ipairs(note.links or {}) do
    local result = resolve.resolve(root, note.relpath, link)
    local label = link.raw
    if result.kind == "resolved" then
      label = result.matches[1].relpath
    elseif result.kind == "missing-note" and result.proposed then
      label = "missing " .. result.proposed
    elseif result.kind == "missing-location" then
      label = "missing " .. (result.detail or "location") .. " in " .. result.matches[1].relpath
    elseif result.kind == "ambiguous" then
      label = "ambiguous " .. (link.target or link.raw)
    elseif result.kind == "external" then
      label = result.target or link.raw
    end
    local line = result.kind == "resolved" and result.matches[1].line or link.line
    local path = result.kind == "resolved" and result.matches[1].path or note.path
    items[#items + 1] = {
      path = path,
      relpath = result.kind == "resolved" and result.matches[1].relpath or note.relpath,
      line = line,
      col = link.start_col or 1,
      text = label .. "\t" .. context(note, link.line),
      kind = "outgoing",
      result = result,
      source_path = note.path,
      source_line = link.line,
    }
  end
  return items
end

function M.backlinks(root, relpath)
  local items = {}
  for _, note in ipairs(index.list(root)) do
    for _, link in ipairs(note.links or {}) do
      local result = resolve.resolve(root, note.relpath, link)
      if result.kind == "resolved" and result.matches[1].relpath == relpath then
        items[#items + 1] = {
          path = note.path,
          relpath = note.relpath,
          line = link.line,
          col = link.start_col or 1,
          text = note.relpath .. ":" .. link.line .. "\t" .. context(note, link.line),
          kind = "backlink",
        }
      end
    end
  end
  table.sort(items, function(a, b)
    if a.relpath ~= b.relpath then
      return a.relpath < b.relpath
    end
    return a.line < b.line
  end)
  return items
end

function M.entries(root, view, relpath)
  local note = index.note(root, relpath)
  if view == "outline" then
    return M.outline(note)
  end
  if view == "outgoing" then
    return M.outgoing(root, note)
  end
  if view == "backlinks" then
    return M.backlinks(root, relpath)
  end
  return {}
end

function M.quickfix(root, view, relpath)
  local items = M.entries(root, view, relpath)
  local qf = {}
  for _, item in ipairs(items) do
    qf[#qf + 1] = {
      filename = item.path,
      lnum = item.line or 1,
      col = item.col or 1,
      text = item.text,
    }
  end
  vim.fn.setqflist({}, "r", { title = "mdw " .. view, items = qf })
  return qf
end

function M.current_relpath(bufnr)
  bufnr = bufnr or 0
  if vim.bo[bufnr].filetype == "mdw-sidebar" then
    local source = vim.b[bufnr].mdw_source
    if type(source) == "string" and source ~= "" then
      local root = workspace.resolve(bufnr)
      return root, workspace.relpath(root, source)
    end
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  if not workspace.is_note_name(name) then
    return nil, nil
  end
  local root = workspace.resolve(bufnr)
  local path = workspace.normalize(name)
  return root, workspace.relpath(root, path)
end

return M
