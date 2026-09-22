local index = require("mdw.index")
local resolve = require("mdw.resolve")
local ui = require("mdw.ui")
local workspace = require("mdw.workspace")

local M = {}

local function drop_extension(relpath)
  local base = vim.fs.basename(relpath)
  local stem = workspace.stem(base)
  local dir = vim.fs.dirname(relpath)
  if dir == nil or dir == "." or dir == "" then
    return stem
  end
  return dir .. "/" .. stem
end

local function relative_link(from_rel, to_rel)
  local from_dir = vim.fs.dirname(from_rel)
  local from_parts = {}
  if from_dir ~= nil and from_dir ~= "." and from_dir ~= "" then
    from_parts = vim.split(from_dir, "/", { plain = true })
  end
  local to_parts = vim.split(to_rel, "/", { plain = true })
  local index_at = 1
  while from_parts[index_at] and to_parts[index_at] and from_parts[index_at] == to_parts[index_at] do
    index_at = index_at + 1
  end
  local out = {}
  for _ = index_at, #from_parts do
    out[#out + 1] = ".."
  end
  for cursor = index_at, #to_parts do
    out[#out + 1] = to_parts[cursor]
  end
  if #out == 0 then
    return to_parts[#to_parts]
  end
  return table.concat(out, "/")
end

local function format_link(link, from_rel, to_rel)
  if link.syntax == "wikilink" then
    local body = drop_extension(to_rel)
    if link.block and link.block ~= "" then
      body = body .. "#^" .. link.block
    elseif link.heading and link.heading ~= "" then
      body = body .. "#" .. link.heading
    end
    if link.label and link.label ~= "" then
      body = body .. "|" .. link.label
    end
    local bang = link.embed and "!" or ""
    return bang .. "[[" .. body .. "]]"
  end
  if link.syntax == "markdown" then
    local dest = relative_link(from_rel, to_rel)
    if link.block and link.block ~= "" then
      dest = dest .. "#^" .. link.block
    elseif link.heading and link.heading ~= "" then
      dest = dest .. "#" .. link.heading
    end
    local bang = link.embed and "!" or ""
    return bang .. "[" .. (link.label or "") .. "](" .. dest .. ")"
  end
  return nil
end

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

local function dirty_path(path)
  local bufnr = vim.fn.bufnr(path)
  return bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].modified
end

function M.plan(root, from_rel, to_rel)
  if type(to_rel) ~= "string" or to_rel == "" or to_rel:find("%.%.") or workspace.skipped(to_rel) then
    return nil, "choose a destination inside the workspace"
  end
  if not workspace.is_note_name(to_rel) then
    to_rel = to_rel .. ".md"
  end
  if from_rel == to_rel then
    return nil, "that note is already at " .. to_rel
  end
  local source = index.note(root, from_rel)
  if not source then
    return nil, "current note is not in the index"
  end
  local destination = root .. "/" .. to_rel
  if vim.uv.fs_stat(destination) then
    return nil, to_rel .. " already exists"
  end
  local edits = {}
  local files = {}
  for _, note in ipairs(index.list(root)) do
    for _, link in ipairs(note.links or {}) do
      if link.syntax == "wikilink" or link.syntax == "markdown" then
        local result = resolve.resolve(root, note.relpath, link)
        if result.kind == "resolved" and result.matches[1].relpath == from_rel then
          local updated = format_link(link, note.relpath == from_rel and to_rel or note.relpath, to_rel)
          if updated and updated ~= link.raw then
            local bucket = files[note.relpath]
            if not bucket then
              bucket = {
                relpath = note.relpath,
                path = note.path,
                mtime = mtime_of(note.path),
                changes = {},
              }
              files[note.relpath] = bucket
              edits[#edits + 1] = bucket
            end
            bucket.changes[#bucket.changes + 1] = {
              line = link.line,
              start_col = link.start_col,
              end_col = link.end_col,
              before = link.raw,
              after = updated,
            }
          end
        end
      end
    end
  end
  return {
    root = root,
    from_rel = from_rel,
    to_rel = to_rel,
    from_path = source.path,
    to_path = destination,
    from_mtime = mtime_of(source.path),
    edits = edits,
  }
end

function M.preview(plan)
  local lines = {
    "Rename " .. plan.from_rel .. " -> " .. plan.to_rel,
  }
  local count = 0
  for _, file in ipairs(plan.edits) do
    for _, change in ipairs(file.changes) do
      count = count + 1
      if count <= 12 then
        lines[#lines + 1] = file.relpath .. ":" .. change.line .. "  " .. change.before .. " -> " .. change.after
      end
    end
  end
  if count > 12 then
    lines[#lines + 1] = "and " .. (count - 12) .. " more"
  end
  if count == 0 then
    lines[#lines + 1] = "No references to update"
  end
  return table.concat(lines, "\n"), count
end

local function read_file(path)
  local handle = io.open(path, "rb")
  if not handle then
    return nil
  end
  local text = handle:read("*a")
  handle:close()
  return text
end

local function write_file(path, text)
  local handle = io.open(path, "wb")
  if not handle then
    return false
  end
  handle:write(text)
  handle:close()
  return true
end

local function apply_changes(path, changes)
  local text = read_file(path)
  if not text then
    return nil, "could not read " .. path
  end
  text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  local lines = vim.split(text, "\n", { plain = true })
  local by_line = {}
  for _, change in ipairs(changes) do
    by_line[change.line] = by_line[change.line] or {}
    by_line[change.line][#by_line[change.line] + 1] = change
  end
  for line, group in pairs(by_line) do
    table.sort(group, function(a, b)
      return a.start_col > b.start_col
    end)
    local current = lines[line]
    if not current then
      return nil, "line " .. line .. " is missing in " .. path
    end
    for _, change in ipairs(group) do
      local slice = current:sub(change.start_col, change.end_col)
      if slice ~= change.before then
        return nil, "a reference changed in " .. path
      end
      current = current:sub(1, change.start_col - 1) .. change.after .. current:sub(change.end_col + 1)
    end
    lines[line] = current
  end
  return table.concat(lines, "\n")
end

local function conflicts(plan)
  if dirty_path(plan.from_path) then
    return plan.from_rel .. " has unsaved changes"
  end
  if plan.from_mtime ~= mtime_of(plan.from_path) then
    return plan.from_rel .. " changed on disk"
  end
  if vim.uv.fs_stat(plan.to_path) then
    return plan.to_rel .. " already exists"
  end
  for _, file in ipairs(plan.edits) do
    if dirty_path(file.path) then
      return file.relpath .. " has unsaved changes"
    end
    if file.mtime ~= mtime_of(file.path) then
      return file.relpath .. " changed on disk"
    end
  end
  return nil
end

local function reload(path)
  local bufnr = vim.fn.bufnr(path)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) and not vim.bo[bufnr].modified then
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("edit")
    end)
  end
end

function M.apply(plan)
  local problem = conflicts(plan)
  if problem then
    return nil, problem
  end
  local updated = {}
  for _, file in ipairs(plan.edits) do
    local text, err = apply_changes(file.path, file.changes)
    if not text then
      return nil, err, { partial = #updated > 0, updated = updated }
    end
    if not write_file(file.path, text) then
      return nil, "could not write " .. file.relpath, { partial = #updated > 0, updated = updated }
    end
    updated[#updated + 1] = file.relpath
    reload(file.path)
  end
  vim.fn.mkdir(vim.fs.dirname(plan.to_path), "p")
  local renamed, rename_err = vim.uv.fs_rename(plan.from_path, plan.to_path)
  if not renamed then
    return nil, "could not rename the note (" .. tostring(rename_err) .. ")", { partial = true, updated = updated }
  end
  local bufnr = vim.fn.bufnr(plan.from_path)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    vim.api.nvim_buf_set_name(bufnr, plan.to_path)
    vim.bo[bufnr].modified = false
  end
  index.rebuild(plan.root)
  return true
end

function M.rename(root, from_rel, to_rel)
  if require("mdw.lsp").owns_rename() then
    return nil, "rename is handled by the language server"
  end
  local plan, err = M.plan(root, from_rel, to_rel)
  if not plan then
    return nil, err
  end
  local preview = M.preview(plan)
  vim.notify(preview, vim.log.levels.INFO)
  if not ui.confirm("Rename " .. plan.from_rel .. " to " .. plan.to_rel .. "?") then
    return nil, "cancelled"
  end
  return M.apply(plan)
end

return M
