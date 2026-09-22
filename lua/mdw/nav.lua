local create = require("mdw.create")
local index = require("mdw.index")
local relations = require("mdw.relations")
local resolve = require("mdw.resolve")
local ui = require("mdw.ui")
local workspace = require("mdw.workspace")

local M = {}

local function link_at(note, line, col)
  for _, link in ipairs(note.links or {}) do
    if link.line == line and col >= link.start_col and col <= link.end_col then
      return link
    end
  end
  return nil
end

local function open_match(match)
  vim.cmd.edit(vim.fn.fnameescape(match.path))
  local line = match.line or 1
  local col = math.max((match.col or 1) - 1, 0)
  pcall(vim.api.nvim_win_set_cursor, 0, { line, col })
end

function M.open_result(root, result)
  if result.kind == "resolved" then
    open_match(result.matches[1])
    return true
  end
  if result.kind == "ambiguous" then
    local items = {}
    for _, match in ipairs(result.matches) do
      local note = match.note
      items[#items + 1] = {
        text = match.relpath .. "\t" .. (note.title or "") .. "\t" .. match.line,
        choose = function()
          open_match(match)
        end,
      }
    end
    ui.choose("Mdw links", items)
    return true
  end
  if result.kind == "missing-location" then
    local match = result.matches[1]
    vim.notify(
      "mdw: missing " .. (result.detail or "location") .. " in " .. match.relpath,
      vim.log.levels.WARN
    )
    open_match({ path = match.path, line = 1, col = 1 })
    return true
  end
  if result.kind == "missing-note" then
    if not result.proposed then
      vim.notify("mdw: link target was not found", vim.log.levels.WARN)
      return true
    end
    if not ui.confirm("Create " .. result.proposed .. "?") then
      return true
    end
    local written, err = create.create({
      root = root,
      relpath = result.proposed,
      confirm = false,
    })
    if not written then
      vim.notify("mdw: " .. (err or "could not create the note"), vim.log.levels.ERROR)
      return true
    end
    open_match({ path = written, line = 1, col = 1 })
    return true
  end
  if result.kind == "external" then
    if result.path and workspace.contains(root, result.path) then
      vim.cmd.edit(vim.fn.fnameescape(result.path))
      return true
    end
    if result.target and result.target:match("^https?://") then
      vim.ui.open(result.target)
      return true
    end
    vim.notify("mdw: " .. (result.target or "link") .. " is outside the workspace", vim.log.levels.INFO)
    return true
  end
  vim.notify("mdw: this link is not supported", vim.log.levels.WARN)
  return true
end

function M.follow(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local root, relpath = relations.current_relpath(bufnr)
  if not root or not relpath then
    return false
  end
  local note = index.note(root, relpath)
  if not note then
    index.sync_buffer(bufnr, "buffer")
    note = index.note(root, relpath)
  end
  if not note then
    return false
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local link = link_at(note, cursor[1], cursor[2] + 1)
  if not link then
    return false
  end
  local result = resolve.resolve(root, relpath, link)
  M.open_result(root, result)
  return true
end

return M
