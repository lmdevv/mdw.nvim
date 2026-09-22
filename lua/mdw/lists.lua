local config = require("mdw.config")

local M = {}

local function level()
  return config.get().lists.level or 2
end

local function fence_open(line)
  local indent, marker = line:match("^(%s*)([`~]+)")
  if not marker or #indent >= 4 or #marker < 3 then
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

local function inside_fence(lines, lnum)
  local fence = nil
  for index = 1, lnum do
    local line = lines[index] or ""
    if fence then
      if fence_closes(line, fence) then
        fence = nil
      end
    elseif fence_open(line) then
      fence = fence_open(line)
    end
  end
  return fence ~= nil
end

local function pack(indent, extra)
  extra.indent = indent
  extra.text = extra.text or ""
  return extra
end

local function parse(line)
  local indent, rest = (line or ""):match("^(%s*)(.*)$")
  indent = indent or ""
  rest = rest or ""
  local marker, box = rest:match("^([-*+])%s+%[([ xX])%]%s*$")
  if marker then
    return pack(indent, { kind = "bullet", marker = marker, box = box })
  end
  local text
  marker, box, text = rest:match("^([-*+])%s+%[([ xX])%]%s+(.*)$")
  if marker then
    return pack(indent, { kind = "bullet", marker = marker, box = box, text = text })
  end
  marker = rest:match("^([-*+])%s*$")
  if marker then
    return pack(indent, { kind = "bullet", marker = marker })
  end
  marker, text = rest:match("^([-*+])%s+(.*)$")
  if marker then
    return pack(indent, { kind = "bullet", marker = marker, text = text })
  end
  local num, delim
  num, delim, box = rest:match("^(%d+)([.)])%s+%[([ xX])%]%s*$")
  if num then
    return pack(indent, { kind = "ordered", num = tonumber(num), delim = delim, box = box })
  end
  num, delim, box, text = rest:match("^(%d+)([.)])%s+%[([ xX])%]%s+(.*)$")
  if num then
    return pack(indent, { kind = "ordered", num = tonumber(num), delim = delim, box = box, text = text })
  end
  num, delim = rest:match("^(%d+)([.)])%s*$")
  if num then
    return pack(indent, { kind = "ordered", num = tonumber(num), delim = delim })
  end
  num, delim, text = rest:match("^(%d+)([.)])%s+(.*)$")
  if num then
    return pack(indent, { kind = "ordered", num = tonumber(num), delim = delim, text = text })
  end
  return nil
end

local function head(item)
  local marker = item.kind == "ordered" and (tostring(item.num) .. item.delim) or item.marker
  local base = item.indent .. marker
  if item.box then
    return base .. " [" .. item.box .. "] "
  end
  return base .. " "
end

local function join(item)
  return head(item) .. (item.text or "")
end

local function change_indent(indent, direction, width)
  if indent:find("\t") and not indent:find(" ") then
    if direction < 0 then
      return indent:sub(1, math.max(#indent - 1, 0))
    end
    return indent .. "\t"
  end
  local spaces = #indent
  if direction < 0 then
    spaces = math.max(0, spaces - width)
  else
    spaces = spaces + width
  end
  return string.rep(" ", spaces)
end

local function renumber(bufnr, lnum)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local item = parse(lines[lnum] or "")
  if not item or item.kind ~= "ordered" then
    return
  end
  local indent = item.indent
  local delim = item.delim
  local function kind_of(line)
    if line == nil or line:match("^%s*$") then
      return "stop"
    end
    local parsed = parse(line)
    if not parsed or #parsed.indent < #indent then
      return "stop"
    end
    if parsed.indent == indent then
      if parsed.kind == "ordered" and parsed.delim == delim then
        return "item"
      end
      return "stop"
    end
    return "child"
  end
  local start = lnum
  while start > 1 and kind_of(lines[start - 1]) ~= "stop" do
    start = start - 1
  end
  local number = 0
  local last = start - 1
  for index = start, #lines do
    local kind = kind_of(lines[index])
    if kind == "stop" then
      break
    end
    last = index
    if kind == "item" then
      number = number + 1
      local parsed = parse(lines[index])
      parsed.num = number
      lines[index] = join(parsed)
    end
  end
  if last < start then
    return
  end
  local chunk = {}
  for index = start, last do
    chunk[#chunk + 1] = lines[index]
  end
  vim.api.nvim_buf_set_lines(bufnr, start - 1, last, false, chunk)
end

local function place(row, col)
  local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
  if col < 0 then
    col = 0
  end
  if col > #line then
    col = #line
  end
  pcall(vim.api.nvim_win_set_cursor, 0, { row, col })
end

local function plain_break(row, insert, scripted)
  if scripted then
    vim.api.nvim_buf_set_lines(0, row, row, false, { "" })
    place(row + 1, 0)
    return
  end
  if insert then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
    return
  end
  vim.cmd("normal! o")
end

function M.continue(opts)
  local scripted = type(opts) == "table" and opts.row ~= nil
  local insert = (scripted and opts.insert == true) or (not scripted and vim.fn.mode():sub(1, 1) == "i")
  local row, col
  if scripted then
    row = opts.row
    col = opts.col
  else
    row, col = unpack(vim.api.nvim_win_get_cursor(0))
    if not insert then
      col = nil
    end
  end
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local line = lines[row] or ""
  if inside_fence(lines, row) or not parse(line) then
    plain_break(row, insert, scripted)
    return false
  end
  local item = parse(line)
  local prefix = head(item)
  if insert and col ~= nil and col < #prefix then
    plain_break(row, insert, scripted)
    return false
  end
  if item.text == "" then
    if item.indent == "" then
      vim.api.nvim_buf_set_lines(0, row - 1, row, false, { "" })
      place(row, 0)
    else
      item.indent = change_indent(item.indent, -1, level())
      if item.kind == "ordered" then
        item.num = 1
      end
      vim.api.nvim_buf_set_lines(0, row - 1, row, false, { join(item) })
      if item.kind == "ordered" then
        renumber(0, row)
      end
      local updated = parse(vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or "")
      place(row, updated and #head(updated) or 0)
    end
    if not scripted and not insert then
      vim.cmd("startinsert")
    end
    return true
  end
  local before_text = item.text
  local after_text = ""
  if insert and col ~= nil then
    local cut = math.max(col - #prefix, 0)
    before_text = item.text:sub(1, cut)
    after_text = item.text:sub(cut + 1)
  end
  item.text = before_text
  local nxt = {
    indent = item.indent,
    kind = item.kind,
    marker = item.marker,
    delim = item.delim,
    num = item.kind == "ordered" and ((item.num or 1) + 1) or nil,
    box = item.box and " " or nil,
    text = after_text,
  }
  vim.api.nvim_buf_set_lines(0, row - 1, row, false, { join(item), join(nxt) })
  if item.kind == "ordered" then
    renumber(0, row + 1)
  end
  local updated = parse(vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1] or "")
  place(row + 1, updated and #head(updated) or 0)
  if not scripted and not insert then
    vim.cmd("startinsert")
  end
  return true
end

local function each(first, last, mutate, do_renumber)
  local start_line = math.min(first, last)
  local end_line = math.max(first, last)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local original = vim.list_slice(lines, 1, #lines)
  local ordered = {}
  for lnum = start_line, end_line do
    if not inside_fence(lines, lnum) then
      local item = parse(lines[lnum] or "")
      if item then
        local replacement = mutate(item)
        if replacement then
          lines[lnum] = join(replacement)
          if do_renumber and replacement.kind == "ordered" then
            ordered[#ordered + 1] = lnum
          end
        end
      end
    end
  end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  for _, lnum in ipairs(ordered) do
    renumber(0, lnum)
  end
  local cursor_row, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))
  if cursor_row >= start_line and cursor_row <= end_line then
    local old_item = parse(original[cursor_row] or "")
    local new_item = parse(vim.api.nvim_buf_get_lines(0, cursor_row - 1, cursor_row, false)[1] or "")
    if old_item and new_item then
      local delta = #head(new_item) - #head(old_item)
      if cursor_col >= #head(old_item) then
        cursor_col = cursor_col + delta
      end
    end
    place(cursor_row, cursor_col)
  end
end

local function shift(direction, first, last)
  local width = level()
  each(first, last, function(item)
    local indent = change_indent(item.indent, direction, width)
    if indent == item.indent then
      return nil
    end
    item.indent = indent
    if direction > 0 and item.kind == "ordered" then
      item.num = 1
    end
    return item
  end, true)
end

local function resolved_range(first, last)
  if first ~= nil then
    return first, last or first
  end
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" then
    return vim.fn.line("v"), vim.fn.line(".")
  end
  return vim.api.nvim_win_get_cursor(0)[1], vim.api.nvim_win_get_cursor(0)[1]
end

local function current_is_list()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  if inside_fence(lines, row) then
    return false
  end
  return parse(lines[row] or "") ~= nil
end

local function visual_mode()
  local mode = vim.fn.mode()
  return mode == "v" or mode == "V" or mode == "\22"
end

function M.nest(first, last)
  if first == nil and not visual_mode() and not current_is_list() then
    vim.cmd("normal! >>")
    return
  end
  local start_line, end_line = resolved_range(first, last)
  shift(1, start_line, end_line)
end

function M.unnest(first, last)
  if first == nil and not visual_mode() and not current_is_list() then
    vim.cmd("normal! <<")
    return
  end
  local start_line, end_line = resolved_range(first, last)
  shift(-1, start_line, end_line)
end

function M.check(first, last)
  local start_line, end_line = resolved_range(first, last)
  each(start_line, end_line, function(item)
    if item.box == nil then
      item.box = " "
    elseif item.box == " " then
      item.box = "x"
    else
      item.box = " "
    end
    return item
  end, false)
end

local function map_key(bufnr, mode, lhs, rhs, desc)
  if type(lhs) ~= "string" or lhs == "" then
    return
  end
  vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, silent = true, desc = desc })
end

function M.map(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if not require("mdw.workspace").is_note_name(name) then
    return
  end
  local maps = config.get().lists.maps or {}
  map_key(bufnr, "i", maps.continue, function()
    M.continue()
  end, "Continue Markdown list")
  map_key(bufnr, "n", maps.open, function()
    M.continue()
  end, "Open a continued Markdown list item")
  map_key(bufnr, "n", maps.nest, function()
    M.nest()
  end, "Nest Markdown list item")
  map_key(bufnr, "x", maps.nest, ":Mdw list nest<CR>", "Nest Markdown list items")
  map_key(bufnr, "n", maps.unnest, function()
    M.unnest()
  end, "Unnest Markdown list item")
  map_key(bufnr, "x", maps.unnest, ":Mdw list unnest<CR>", "Unnest Markdown list items")
  map_key(bufnr, "n", maps.check, function()
    M.check()
  end, "Toggle Markdown checkbox")
  map_key(bufnr, "x", maps.check, ":Mdw list check<CR>", "Toggle Markdown checkboxes")
end

return M
