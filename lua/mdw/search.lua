local M = {}

local RANKS = {
  exact = 1,
  prefix = 2,
  substring = 3,
  filename = 4,
  path = 5,
  tag = 6,
  note = 7,
}

function M.parse_query(query)
  query = vim.trim(query or "")
  local tags = {}
  local tokens = {}
  if query ~= "" then
    for token in query:gmatch("%S+") do
      local tag = token:match("^#(.+)$")
      local cleaned = tag and tag:gsub("^#+", ""):gsub("[/%-]+$", "") or nil
      local valid = cleaned
        and cleaned ~= ""
        and cleaned:match("^[%w_][%w_%-/]*$")
        and not cleaned:find("//", 1, true)
      if valid then
        tags[#tags + 1] = cleaned
      else
        tokens[#tokens + 1] = token
      end
    end
  end
  local sensitive = false
  for _, token in ipairs(tokens) do
    if token:find("%u") then
      sensitive = true
      break
    end
  end
  return {
    empty = #tags == 0 and #tokens == 0,
    tag_filters = tags,
    text_tokens = tokens,
    phrase = table.concat(tokens, " "),
    sensitive = sensitive,
  }
end

local function fold(value, sensitive)
  if sensitive then
    return value
  end
  return value:lower()
end

local function consider(best, rank, reason)
  if best == nil or rank < best.rank then
    return { rank = rank, reason = reason }
  end
  return best
end

local function classify_text(note, text, sensitive)
  local needle = fold(text, sensitive)
  local best = nil
  local title = fold(note.title or "", sensitive)
  if title == needle then
    best = consider(best, RANKS.exact, "title")
  elseif vim.startswith(title, needle) then
    best = consider(best, RANKS.prefix, "title")
  elseif needle ~= "" and title:find(needle, 1, true) then
    best = consider(best, RANKS.substring, "title")
  end
  for _, alias in ipairs(note.aliases or {}) do
    local folded = fold(alias, sensitive)
    if folded == needle then
      best = consider(best, RANKS.exact, "alias")
    elseif vim.startswith(folded, needle) then
      best = consider(best, RANKS.prefix, "alias")
    elseif needle ~= "" and folded:find(needle, 1, true) then
      best = consider(best, RANKS.substring, "alias")
    end
  end
  local filename = fold(note.filename or "", sensitive)
  if needle ~= "" and filename:find(needle, 1, true) then
    best = consider(best, RANKS.filename, "filename")
  end
  local relpath = fold(note.relpath or "", sensitive)
  if needle ~= "" and relpath:find(needle, 1, true) then
    best = consider(best, RANKS.path, "path")
  end
  for _, tag in ipairs(note.tags or {}) do
    local folded = fold(tag, sensitive)
    if needle ~= "" and folded:find(needle, 1, true) then
      best = consider(best, RANKS.tag, "tag")
    end
  end
  return best
end

local function tags_match(note, filters)
  for _, filter in ipairs(filters) do
    local want = filter:lower()
    local found = false
    for _, tag in ipairs(note.tags or {}) do
      if tag:lower() == want then
        found = true
        break
      end
    end
    if not found then
      return false
    end
  end
  return true
end

local function display(note)
  local parts = { note.relpath or "" }
  if note.title and note.title ~= "" and note.title_source ~= "filename" then
    parts[#parts + 1] = note.title
  end
  if note.aliases and #note.aliases > 0 then
    parts[#parts + 1] = table.concat(note.aliases, ", ")
  end
  if note.tags and #note.tags > 0 then
    local tags = {}
    for _, tag in ipairs(note.tags) do
      tags[#tags + 1] = "#" .. tag
    end
    parts[#parts + 1] = table.concat(tags, " ")
  end
  return table.concat(parts, "\t")
end

local function match_note(note, parsed)
  if not tags_match(note, parsed.tag_filters) then
    return nil
  end
  if parsed.empty then
    return { rank = RANKS.note, reason = "note" }
  end
  if #parsed.text_tokens == 0 then
    return { rank = RANKS.tag, reason = "tag" }
  end
  local best = nil
  for _, token in ipairs(parsed.text_tokens) do
    local classified = classify_text(note, token, parsed.sensitive)
    if not classified then
      return nil
    end
    best = consider(best, classified.rank, classified.reason)
  end
  if parsed.phrase ~= "" then
    local phrase = classify_text(note, parsed.phrase, parsed.sensitive)
    if phrase then
      best = consider(best, phrase.rank, phrase.reason)
    end
  end
  return best
end

function M.query_notes(notes, query)
  local parsed = type(query) == "table" and query or M.parse_query(query)
  local results = {}
  for _, note in ipairs(notes) do
    local matched = match_note(note, parsed)
    if matched then
      results[#results + 1] = {
        note = note,
        path = note.path,
        relpath = note.relpath,
        title = note.title,
        reason = matched.reason,
        rank = matched.rank,
        text = display(note),
      }
    end
  end
  table.sort(results, function(a, b)
    if a.rank ~= b.rank then
      return a.rank < b.rank
    end
    return a.relpath < b.relpath
  end)
  return results
end

function M.query(root, query)
  local notes = require("mdw.index").list(root)
  return M.query_notes(notes, query)
end

return M
