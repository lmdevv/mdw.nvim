local index = require("mdw.index")
local workspace = require("mdw.workspace")

local M = {}

local function note_key(relpath)
  local base = vim.fs.basename(relpath)
  local stem = workspace.stem(base)
  local dir = vim.fs.dirname(relpath)
  if dir == nil or dir == "." or dir == "" then
    return stem
  end
  return dir .. "/" .. stem
end

local function add_match(found, seen, note, line)
  if seen[note.relpath .. ":" .. tostring(line or 1)] then
    return
  end
  seen[note.relpath .. ":" .. tostring(line or 1)] = true
  found[#found + 1] = {
    note = note,
    path = note.path,
    relpath = note.relpath,
    line = line or 1,
    col = 1,
  }
end

local function locations(note, heading, block)
  if block and block ~= "" then
    local hits = {}
    for _, item in ipairs(note.blocks or {}) do
      if item.id == block then
        hits[#hits + 1] = item.line
      end
    end
    return hits, "block"
  end
  if heading and heading ~= "" then
    local hits = {}
    for _, item in ipairs(note.headings or {}) do
      if item.text == heading then
        hits[#hits + 1] = item.line
      end
    end
    return hits, "heading"
  end
  return { 1 }, nil
end

local function join_rel(dir, rel)
  if rel:sub(1, 1) == "/" then
    return nil
  end
  local parts = {}
  if dir ~= nil and dir ~= "" and dir ~= "." then
    parts = vim.split(dir, "/", { plain = true })
  end
  for part in rel:gmatch("[^/]+") do
    if part == ".." then
      if #parts == 0 then
        return nil
      end
      table.remove(parts)
    elseif part ~= "." and part ~= "" then
      parts[#parts + 1] = part
    end
  end
  return table.concat(parts, "/")
end

local function with_note_extension(relpath)
  if workspace.is_note_name(relpath) then
    return relpath
  end
  local ext = vim.fs.basename(relpath):match("%.([^%.]+)$")
  if ext then
    return nil
  end
  return relpath .. ".md"
end

function M.proposed_wikilink(source_relpath, target)
  local cleaned = vim.trim(target or "")
  if cleaned == "" then
    return nil
  end
  local rel
  if cleaned:find("/", 1, true) then
    rel = join_rel("", cleaned)
  else
    local dir = vim.fs.dirname(source_relpath or "")
    rel = join_rel(dir, cleaned)
  end
  if not rel or rel == "" then
    return nil
  end
  return with_note_extension(rel) or (rel .. ".md")
end

local function wikilink_candidates(notes, target)
  local found = {}
  local seen = {}
  local lowered = target:lower()
  local slashed = target:find("/", 1, true) ~= nil
  for _, note in ipairs(notes) do
    local key = note_key(note.relpath)
    local stem = workspace.stem(note.filename or vim.fs.basename(note.relpath))
    local path_hit = note.relpath == target or key == target
    local stem_hit = not slashed and stem:lower() == lowered
    local alias_hit = false
    if not slashed then
      for _, alias in ipairs(note.aliases or {}) do
        if alias:lower() == lowered then
          alias_hit = true
          break
        end
      end
    end
    if path_hit or stem_hit or alias_hit then
      add_match(found, seen, note, 1)
    end
  end
  return found
end

local function finish(matches, heading, block, missing_proposed)
  if #matches == 0 then
    if missing_proposed then
      return { kind = "missing-note", proposed = missing_proposed, matches = {} }
    end
    return { kind = "missing-note", proposed = nil, matches = {} }
  end
  if #matches > 1 then
    return { kind = "ambiguous", matches = matches }
  end
  local match = matches[1]
  local lines, detail = locations(match.note, heading, block)
  if #lines == 0 then
    return {
      kind = "missing-location",
      detail = detail,
      matches = { match },
    }
  end
  if #lines > 1 then
    local many = {}
    for _, line in ipairs(lines) do
      many[#many + 1] = {
        note = match.note,
        path = match.path,
        relpath = match.relpath,
        line = line,
        col = 1,
      }
    end
    return { kind = "ambiguous", matches = many }
  end
  match.line = lines[1]
  return { kind = "resolved", matches = { match } }
end

function M.resolve(root, source_relpath, link)
  if type(link) ~= "table" then
    return { kind = "unsupported", matches = {} }
  end
  if link.syntax == "url" or (link.target or ""):match("^%w+://") then
    return { kind = "external", target = link.target, matches = {} }
  end
  local notes = index.list(root)
  local target = vim.trim(link.target or "")
  if target == "" then
    local source = nil
    for _, note in ipairs(notes) do
      if note.relpath == source_relpath then
        source = note
        break
      end
    end
    if not source then
      return { kind = "missing-note", proposed = nil, matches = {} }
    end
    return finish({ {
      note = source,
      path = source.path,
      relpath = source.relpath,
      line = 1,
      col = 1,
    } }, link.heading, link.block, nil)
  end
  if link.syntax == "markdown" then
    local dir = vim.fs.dirname(source_relpath or "")
    local rel = join_rel(dir, target)
    if not rel then
      return { kind = "external", target = link.target, matches = {} }
    end
    local note_rel = with_note_extension(rel)
    if not note_rel then
      local full = root .. "/" .. rel
      if vim.uv.fs_stat(full) then
        return { kind = "external", target = link.target, path = full, matches = {} }
      end
      return { kind = "external", target = link.target, matches = {} }
    end
    local found = {}
    for _, note in ipairs(notes) do
      if note.relpath == note_rel or note.relpath == rel then
        add_match(found, {}, note, 1)
      end
    end
    return finish(found, link.heading, link.block, note_rel)
  end
  local found = wikilink_candidates(notes, target)
  return finish(found, link.heading, link.block, M.proposed_wikilink(source_relpath, target))
end

return M
