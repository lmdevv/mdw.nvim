local M = {}

local function yaml_quote(value)
  if value == "" then
    return '""'
  end
  if value:match("^[%w_][%w_%.%/%- ]*$") and not value:match("^(true|false|null|yes|no|on|off)$") and not value:match("^%-?%d") then
    return value
  end
  return '"' .. value:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

local function key_name(line)
  return line:match("^([%w_]+)%s*:")
end

local function render(key, value, flow)
  if type(value) == "string" then
    return { key .. ": " .. yaml_quote(value) }
  end
  if flow then
    local parts = {}
    for _, item in ipairs(value) do
      parts[#parts + 1] = yaml_quote(item)
    end
    return { key .. ": [" .. table.concat(parts, ", ") .. "]" }
  end
  if #value == 0 then
    return { key .. ": []" }
  end
  local lines = { key .. ":" }
  for _, item in ipairs(value) do
    lines[#lines + 1] = "  - " .. yaml_quote(item)
  end
  return lines
end

local function replace_range(lines, from, to, chunk)
  local out = {}
  for i = 1, from - 1 do
    out[#out + 1] = lines[i]
  end
  for _, line in ipairs(chunk) do
    out[#out + 1] = line
  end
  for i = to + 1, #lines do
    out[#out + 1] = lines[i]
  end
  return out
end

function M.apply(text, key, value)
  if type(text) ~= "string" or type(key) ~= "string" or key == "" or not key:match("^[%w_]+$") then
    return nil, "property name must be a word"
  end
  if type(value) ~= "string" and type(value) ~= "table" then
    return nil, "property value must be text or a list"
  end
  text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  local lines = vim.split(text, "\n", { plain = true })
  local has_frontmatter = lines[1] and vim.trim(lines[1]) == "---"
  if not has_frontmatter then
    local chunk = { "---" }
    for _, line in ipairs(render(key, value, false)) do
      chunk[#chunk + 1] = line
    end
    chunk[#chunk + 1] = "---"
    chunk[#chunk + 1] = ""
    for _, line in ipairs(lines) do
      chunk[#chunk + 1] = line
    end
    return table.concat(chunk, "\n")
  end
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
  local found = nil
  for index = 2, closing - 1 do
    local name = key_name(lines[index])
    if name and name:lower() == key:lower() then
      found = index
      break
    end
  end
  if not found then
    local chunk = render(key, value, false)
    local out = {}
    for i = 1, closing - 1 do
      out[#out + 1] = lines[i]
    end
    for _, line in ipairs(chunk) do
      out[#out + 1] = line
    end
    for i = closing, #lines do
      out[#out + 1] = lines[i]
    end
    return table.concat(out, "\n")
  end
  local rest = lines[found]:match("^[%w_]+%s*:(.*)$") or ""
  if rest:match("^%s*[|>]") then
    return nil, "unsupported frontmatter syntax for " .. key
  end
  local last = found
  local flow = rest:match("^%s*%[") ~= nil
  if vim.trim(rest) == "" then
    local saw_item = false
    for index = found + 1, closing - 1 do
      local line = lines[index]
      if line:match("^%s*$") or line:match("^%s*#") then
        break
      end
      if line:match("^%s+-%s+") or line:match("^%s+-%s*$") then
        saw_item = true
        last = index
      else
        return nil, "unsupported frontmatter syntax for " .. key
      end
    end
    if not saw_item then
      flow = false
    end
  end
  local chunk = render(key_name(lines[found]), value, flow)
  return table.concat(replace_range(lines, found, last, chunk), "\n")
end

function M.edit_buffer(bufnr, key, value)
  bufnr = bufnr or 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local updated, err = M.apply(table.concat(lines, "\n"), key, value)
  if not updated then
    return nil, err
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(updated, "\n", { plain = true }))
  return true
end

return M
