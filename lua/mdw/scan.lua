local M = {}

local function parse_scalar(raw)
  raw = vim.trim(raw)
  if raw == "" then
    return nil, "empty"
  end
  local quote = raw:sub(1, 1)
  if quote == '"' or quote == "'" then
    if #raw < 2 or raw:sub(-1) ~= quote then
      return nil, "bad-quote"
    end
    local inner = raw:sub(2, -2)
    if quote == '"' then
      inner = inner:gsub('\\"', '"'):gsub("\\\\", "\\")
    end
    return inner, "string"
  end
  local lower = raw:lower()
  if lower == "true"
    or lower == "false"
    or lower == "yes"
    or lower == "no"
    or lower == "on"
    or lower == "off"
    or lower == "null"
    or raw == "~"
  then
    return raw, "other"
  end
  if raw:match("^%-?%d+%.?%d*$") or raw:match("^%-?%.%d+$") then
    return raw, "other"
  end
  return raw, "string"
end

local function parse_flow(inner)
  local items = {}
  local buf = {}
  local quote = nil
  local i = 1
  local function push()
    local text = vim.trim(table.concat(buf))
    buf = {}
    if text == "" then
      return true
    end
    local value, kind = parse_scalar(text)
    if kind == "bad-quote" then
      return false
    end
    items[#items + 1] = { value = value, kind = kind }
    return true
  end
  while i <= #inner do
    local char = inner:sub(i, i)
    if quote then
      if char == "\\" and quote == '"' and i < #inner then
        buf[#buf + 1] = inner:sub(i, i + 1)
        i = i + 2
      elseif char == quote then
        buf[#buf + 1] = char
        quote = nil
        i = i + 1
      else
        buf[#buf + 1] = char
        i = i + 1
      end
    elseif char == '"' or char == "'" then
      quote = char
      buf[#buf + 1] = char
      i = i + 1
    elseif char == "," then
      if not push() then
        return nil
      end
      i = i + 1
    else
      buf[#buf + 1] = char
      i = i + 1
    end
  end
  if quote ~= nil or not push() then
    return nil
  end
  return items
end

local function add_unique(list, seen, value, fold)
  if value == nil or value == "" then
    return
  end
  local key = fold and value:lower() or value
  if seen[key] then
    return
  end
  seen[key] = true
  list[#list + 1] = value
end

local function clean_tag(value)
  if type(value) ~= "string" then
    return nil
  end
  local tag = value:gsub("^#+", "")
  tag = tag:gsub("[/%-]+$", "")
  if tag == "" or tag:find("//", 1, true) or not tag:match("^[%w_][%w_%-/]*$") then
    return nil
  end
  return tag
end

local function add_tag_value(tags, seen, value, split_words)
  if type(value) ~= "string" then
    return true
  end
  if split_words then
    for part in value:gmatch("[^,%s]+") do
      local tag = clean_tag(part)
      if tag then
        add_unique(tags, seen, tag, true)
      end
    end
    return true
  end
  local tag = clean_tag(value)
  if tag then
    add_unique(tags, seen, tag, true)
  end
  return true
end

local function parse_frontmatter(lines)
  local data = {
    title = nil,
    aliases = {},
    tags = {},
  }
  local alias_seen = {}
  local tag_seen = {}
  local current = nil
  local mode = nil

  for index, line in ipairs(lines) do
    local where = "frontmatter line " .. index
    if vim.trim(line) ~= "" and not line:match("^%s*#") then
      local item = line:match("^%s*%-%s*(.*)$")
      local key, value = line:match("^%s*([%w_%-]+)%s*:%s*(.*)$")
      if item and not key then
        if current == nil or mode ~= "list" then
          return nil, "unsupported frontmatter syntax at " .. where
        end
        if vim.trim(item) ~= "" then
          local scalar, kind = parse_scalar(item)
          if kind == "bad-quote" then
            return nil, "unclosed quote at " .. where
          end
          if current == "alias" or current == "aliases" then
            if kind == "string" then
              add_unique(data.aliases, alias_seen, scalar, true)
            end
          elseif current == "tag" or current == "tags" then
            add_tag_value(data.tags, tag_seen, kind == "string" and scalar or nil, false)
          end
        end
      elseif key then
        local lowered = key:lower()
        value = vim.trim(value)
        if value == "|" or value == ">" or value:match("^|[%+%-]?$") or value:match("^>[%+%-]?$") then
          return nil, "multiline YAML scalars are not supported at " .. where
        end
        current = lowered
        if value == "" then
          mode = "list"
        elseif value:sub(1, 1) == "[" then
          mode = "scalar"
          if value:sub(-1) ~= "]" then
            return nil, "unclosed flow list at " .. where
          end
          local flow = parse_flow(value:sub(2, -2))
          if not flow then
            return nil, "unclosed quote at " .. where
          end
          if lowered == "title" then
            data.title = nil
          end
          for _, entry in ipairs(flow) do
            if lowered == "alias" or lowered == "aliases" then
              if entry.kind == "string" then
                add_unique(data.aliases, alias_seen, entry.value, true)
              end
            elseif lowered == "tag" or lowered == "tags" then
              if entry.kind == "string" then
                add_tag_value(data.tags, tag_seen, entry.value, false)
              end
            end
          end
        else
          mode = "scalar"
          local scalar, kind = parse_scalar(value)
          if kind == "bad-quote" then
            return nil, "unclosed quote at " .. where
          end
          if lowered == "title" then
            data.title = kind == "string" and scalar or nil
          elseif lowered == "alias" or lowered == "aliases" then
            if kind == "string" then
              add_unique(data.aliases, alias_seen, scalar, true)
            end
          elseif lowered == "tag" or lowered == "tags" then
            if kind == "string" then
              add_tag_value(data.tags, tag_seen, scalar, true)
            end
          end
        end
      else
        return nil, "unsupported frontmatter syntax at " .. where
      end
    end
  end

  return data
end

local function cover(skip, from, to)
  for pos = from, to do
    skip[pos] = true
  end
end

local function masked(line)
  local skip = {}
  local n = #line
  local i = 1
  while i <= n do
    local char = line:sub(i, i)
    local pair = line:sub(i, i + 1)
    if char == "`" then
      local ticks = line:match("^`+", i)
      local closer = line:find(ticks, i + #ticks, true)
      if closer then
        cover(skip, i, closer + #ticks - 1)
        i = closer + #ticks
      else
        cover(skip, i, n)
        break
      end
    elseif pair == "[[" then
      local close = line:find("]]", i + 2, true)
      if close then
        cover(skip, i, close + 1)
        i = close + 2
      else
        cover(skip, i, n)
        break
      end
    elseif char == "<" then
      local close = line:find(">", i + 1, true)
      local inner = close and line:sub(i + 1, close - 1) or ""
      if close and (inner:match("^https?://") or inner:match("^[%w.+_-]+@[%w.-]+")) then
        cover(skip, i, close)
        i = close + 1
      else
        i = i + 1
      end
    else
      local url = line:match("^https?://%S+", i)
      if url then
        cover(skip, i, i + #url - 1)
        i = i + #url
      elseif char == "[" or pair == "![" then
        local start = i
        local cursor = pair == "![" and i + 1 or i
        local dest = line:find("%]%(", cursor)
        if dest then
          local depth = 1
          local k = dest + 2
          while k <= n and depth > 0 do
            local next_char = line:sub(k, k)
            if next_char == "(" then
              depth = depth + 1
            elseif next_char == ")" then
              depth = depth - 1
            end
            k = k + 1
          end
          if depth == 0 then
            cover(skip, dest, k - 1)
            i = k
          else
            i = start + 1
          end
        else
          i = start + 1
        end
      else
        i = i + 1
      end
    end
  end
  return skip
end

local function tags_in_line(line)
  local tags = {}
  local skip = masked(line)
  local i = 1
  while i <= #line do
    if line:sub(i, i) == "#" and not skip[i] then
      local prev = i > 1 and line:sub(i - 1, i - 1) or ""
      if prev ~= "#" and not prev:match("[%w_]") then
        local raw = line:match("^([%w_][%w_%-/]*)", i + 1)
        if raw then
          local tag = clean_tag(raw)
          if tag then
            tags[#tags + 1] = tag
          end
          i = i + 1 + #raw
        else
          i = i + 1
        end
      else
        i = i + 1
      end
    else
      i = i + 1
    end
  end
  return tags
end

local function fence_open(line)
  local indent, marker, rest = line:match("^(%s*)(`+)(.*)$")
  if not marker then
    indent, marker, rest = line:match("^(%s*)(~+)(.*)$")
  end
  if not marker or #indent >= 4 or #marker < 3 then
    return nil
  end
  if marker:sub(1, 1) == "`" and rest:find("`", 1, true) then
    return nil
  end
  return { char = marker:sub(1, 1), len = #marker }
end

local function fence_closes(line, fence)
  local indent = line:match("^(%s*)") or ""
  if #indent >= 4 then
    return false
  end
  local marker = line:sub(#indent + 1):match("^(" .. fence.char .. "+)%s*$")
  return marker ~= nil and #marker >= fence.len
end

local function heading_parts(line)
  local indent, hashes, text = line:match("^(%s*)(#+)[%s]+(.-)%s*$")
  if not indent or #indent >= 4 or not hashes or #hashes < 1 or #hashes > 6 then
    return nil
  end
  text = vim.trim(text:gsub("%s+%^[A-Za-z0-9%-]+%s*$", ""):gsub("%s+#+$", ""))
  if text == "" then
    return nil
  end
  return text, #hashes
end

local function first_heading(line)
  return heading_parts(line)
end

local function block_id(line)
  return line:match("%s+%^([A-Za-z0-9%-]+)%s*$") or line:match("^%^([A-Za-z0-9%-]+)%s*$")
end

local function decode_pct(text)
  return (text:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

local function split_target(raw)
  raw = decode_pct(vim.trim(raw))
  local hash = raw:find("#", 1, true)
  if not hash then
    return raw, nil, nil
  end
  local base = raw:sub(1, hash - 1)
  local rest = raw:sub(hash + 1)
  if rest:sub(1, 1) == "^" then
    return base, nil, rest:sub(2)
  end
  return base, rest, nil
end

local function code_spans(line)
  local spans = {}
  local n = #line
  local i = 1
  while i <= n do
    if line:sub(i, i) == "`" then
      local ticks = line:match("^`+", i)
      local closer = ticks and line:find(ticks, i + #ticks, true) or nil
      if closer then
        spans[#spans + 1] = { i, closer + #ticks - 1 }
        i = closer + #ticks
      else
        spans[#spans + 1] = { i, n }
        break
      end
    else
      i = i + 1
    end
  end
  return spans
end

local function in_spans(spans, pos)
  for _, span in ipairs(spans) do
    if pos >= span[1] and pos <= span[2] then
      return true
    end
  end
  return false
end

local function links_in_line(line, lnum)
  local links = {}
  local spans = code_spans(line)
  local n = #line
  local i = 1
  while i <= n do
    if in_spans(spans, i) then
      i = i + 1
    else
      local embed = false
      local start = i
      if line:sub(i, i) == "!" and line:sub(i + 1, i + 2) == "[[" then
        embed = true
        start = i
        i = i + 1
      end
      if line:sub(i, i + 1) == "[[" then
        local close = line:find("]]", i + 2, true)
        if close and not in_spans(spans, i) then
          local inner = line:sub(i + 2, close - 1)
          local pipe = inner:find("|", 1, true)
          local raw_target = inner
          local label = nil
          if pipe then
            raw_target = inner:sub(1, pipe - 1)
            label = inner:sub(pipe + 1)
          end
          local target, heading, block = split_target(raw_target)
          links[#links + 1] = {
            line = lnum,
            start_col = start,
            end_col = close + 1,
            syntax = "wikilink",
            embed = embed,
            target = target,
            label = label,
            heading = heading,
            block = block,
            raw = line:sub(start, close + 1),
          }
          i = close + 2
        else
          i = start + 1
        end
      elseif line:sub(i, i) == "[" then
        local dest = line:find("%]%(", i)
        if dest and not in_spans(spans, i) then
          local depth = 1
          local k = dest + 2
          while k <= n and depth > 0 do
            local next_char = line:sub(k, k)
            if next_char == "(" then
              depth = depth + 1
            elseif next_char == ")" then
              depth = depth - 1
            end
            k = k + 1
          end
          if depth == 0 then
            local label = line:sub(i + 1, dest - 1)
            local body = line:sub(dest + 2, k - 2)
            if body:sub(1, 1) == "<" and body:sub(-1) == ">" then
              body = body:sub(2, -2)
            end
            local bang = i > 1 and line:sub(i - 1, i - 1) == "!"
            local from = bang and i - 1 or i
            local target, heading, block = split_target(body)
            links[#links + 1] = {
              line = lnum,
              start_col = from,
              end_col = k - 1,
              syntax = "markdown",
              embed = bang,
              target = target,
              label = label,
              heading = heading,
              block = block,
              raw = line:sub(from, k - 1),
            }
            i = k
          else
            i = i + 1
          end
        else
          local url = line:match("^<?(https?://[^%s>]+)>?", i)
          if url and not in_spans(spans, i) then
            local raw = line:match("^<?https?://[^%s>]+>?", i)
            links[#links + 1] = {
              line = lnum,
              start_col = i,
              end_col = i + #raw - 1,
              syntax = "url",
              embed = false,
              target = url,
              label = nil,
              heading = nil,
              block = nil,
              raw = raw,
            }
            i = i + #raw
          else
            i = i + 1
          end
        end
      else
        local url = line:match("^(https?://%S+)", i)
        if url and (i == 1 or line:sub(i - 1, i - 1):match("%s")) then
          url = url:gsub("[%)%].,;]+$", "")
          links[#links + 1] = {
            line = lnum,
            start_col = i,
            end_col = i + #url - 1,
            syntax = "url",
            embed = false,
            target = url,
            label = nil,
            heading = nil,
            block = nil,
            raw = url,
          }
          i = i + #url
        else
          i = i + 1
        end
      end
    end
  end
  return links
end

function M.parse(text, filename, stem)
  if type(text) ~= "string" then
    return nil, "unreadable file"
  end
  if text:sub(1, 3) == "\239\187\191" then
    text = text:sub(4)
  end
  if text:find("\0", 1, true) then
    return nil, "file contains a null byte"
  end
  text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  local lines = vim.split(text, "\n", { plain = true })
  local body_from = 1
  local frontmatter = {
    title = nil,
    aliases = {},
    tags = {},
  }

  if lines[1] and vim.trim(lines[1]) == "---" then
    local closing = nil
    for index = 2, #lines do
      local trimmed = vim.trim(lines[index])
      if trimmed == "---" or trimmed == "..." then
        closing = index
        break
      end
    end
    if not closing then
      return nil, "unclosed frontmatter"
    end
    local block = {}
    for index = 2, closing - 1 do
      block[#block + 1] = lines[index]
    end
    local parsed, err = parse_frontmatter(block)
    if not parsed then
      return nil, err
    end
    frontmatter = parsed
    body_from = closing + 1
  end

  local heading = nil
  local tags = {}
  local headings = {}
  local blocks = {}
  local links = {}
  local seen = {}
  for _, tag in ipairs(frontmatter.tags) do
    add_unique(tags, seen, tag, true)
  end

  local fence = nil
  for index = body_from, #lines do
    local line = lines[index]
    if fence then
      if fence_closes(line, fence) then
        fence = nil
      end
    else
      local opened = fence_open(line)
      if opened then
        fence = opened
      else
        if heading == nil then
          heading = first_heading(line)
        end
        local heading_text, level = heading_parts(line)
        if heading_text then
          headings[#headings + 1] = { text = heading_text, level = level, line = index }
        end
        local found_block = block_id(line)
        if found_block then
          blocks[#blocks + 1] = { id = found_block, line = index }
        end
        for _, link in ipairs(links_in_line(line, index)) do
          links[#links + 1] = link
        end
        for _, tag in ipairs(tags_in_line(line)) do
          add_unique(tags, seen, tag, true)
        end
      end
    end
  end

  local title = frontmatter.title
  local title_source = "frontmatter"
  if title == nil then
    if heading ~= nil then
      title = heading
      title_source = "heading"
    else
      title = stem
      title_source = "filename"
    end
  end
  return {
    filename = filename,
    stem = stem,
    title = title,
    title_source = title_source,
    aliases = frontmatter.aliases,
    tags = tags,
    headings = headings,
    blocks = blocks,
    links = links,
  }
end

return M
