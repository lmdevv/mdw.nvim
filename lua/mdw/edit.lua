local config = require("mdw.config")
local workspace = require("mdw.workspace")

local M = {}

local function next_bullet(line)
  local indent, rest = (line or ""):match("^(%s*)(.*)$")
  indent = indent or ""
  rest = rest or ""
  local updated
  if rest:match("^%- %[ %] ") then
    updated = rest:gsub("^%- %[ %] ", "- [x] ", 1)
  elseif rest:match("^%- %[[xX]%] ") then
    updated = rest:gsub("^%- %[[xX]%] ", "", 1):gsub("^%s+", "")
  elseif rest:match("^%- ") then
    updated = rest:gsub("^%- ", "- [ ] ", 1)
  else
    updated = "- " .. rest
  end
  return indent .. updated
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

function M.cycle_lines(bufnr, first, last)
  bufnr = bufnr or 0
  local start_line = math.min(first, last)
  local end_line = math.max(first, last)
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  for index, line in ipairs(lines) do
    local lnum = start_line + index - 1
    if not inside_fence(vim.api.nvim_buf_get_lines(bufnr, 0, lnum, false), lnum) then
      lines[index] = next_bullet(line)
    end
  end
  vim.api.nvim_buf_set_lines(bufnr, start_line - 1, end_line, false, lines)
end

local function prefix_len(line)
  local indent, rest = (line or ""):match("^(%s*)(.*)$")
  indent = indent or ""
  rest = rest or ""
  local marker = 0
  if rest:match("^%- %[[xX]%] ") or rest:match("^%- %[ %] ") then
    marker = 6
  elseif rest:match("^%- ") then
    marker = 2
  end
  return #indent + marker
end

function M.cycle_insert()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local before = prefix_len(vim.api.nvim_get_current_line())
  M.cycle_lines(0, row, row)
  local after_line = vim.api.nvim_get_current_line()
  local adjusted = col
  if col >= before then
    adjusted = col + (prefix_len(after_line) - before)
  end
  if adjusted < 0 then
    adjusted = 0
  end
  if adjusted > #after_line then
    adjusted = #after_line
  end
  pcall(vim.api.nvim_win_set_cursor, 0, { row, adjusted })
end

function M.cycle()
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\022" then
    M.cycle_lines(0, vim.fn.line("v"), vim.fn.line("."))
    return
  end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  M.cycle_lines(0, row, row)
end

local function clipboard_command()
  local configured = config.get().edit.clipboard
  if type(configured) == "table" then
    return configured
  end
  if vim.fn.executable("wl-paste") == 1 then
    return { "wl-paste", "--no-newline", "--type", "image/png" }
  end
  if vim.fn.executable("xclip") == 1 then
    return { "xclip", "-selection", "clipboard", "-t", "image/png", "-o" }
  end
  return nil
end

local function next_path(directory, stem)
  local candidate = directory .. "/" .. stem .. ".png"
  if not vim.uv.fs_stat(candidate) then
    return candidate, stem .. ".png"
  end
  local index = 2
  while true do
    local name = stem .. "-" .. index .. ".png"
    candidate = directory .. "/" .. name
    if not vim.uv.fs_stat(candidate) then
      return candidate, name
    end
    index = index + 1
  end
end

function M.paste_image()
  local command = clipboard_command()
  if not command then
    return nil, "no clipboard image command is available"
  end
  local result = vim.system(command, { text = false }):wait()
  if result.code ~= 0 or type(result.stdout) ~= "string" or result.stdout == "" then
    return nil, vim.trim(result.stderr or "") ~= "" and vim.trim(result.stderr) or "clipboard has no image"
  end
  local note = vim.api.nvim_buf_get_name(0)
  if not workspace.is_note_name(note) then
    return nil, "open a note before pasting an image"
  end
  local folder = config.get().edit.attachments or "assets"
  local directory = vim.fs.dirname(note) .. "/" .. folder
  vim.fn.mkdir(directory, "p")
  local path, name = next_path(directory, "image")
  local handle = io.open(path, "wb")
  if not handle then
    return nil, "could not write " .. path
  end
  handle:write(result.stdout)
  handle:close()
  local link = "![](" .. folder .. "/" .. name .. ")"
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  if line == "" then
    vim.api.nvim_set_current_line(link)
  else
    vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, col, { link })
  end
  return path
end

function M.map(bufnr)
  local lhs = config.get().edit.cycle
  if type(lhs) ~= "string" or lhs == "" then
    return
  end
  if not workspace.is_note_name(vim.api.nvim_buf_get_name(bufnr)) then
    return
  end
  local opts = { buffer = bufnr, silent = true, desc = "Cycle Markdown task" }
  vim.keymap.set({ "n", "v" }, lhs, M.cycle, opts)
  vim.keymap.set("i", lhs, M.cycle_insert, opts)
end

return M
