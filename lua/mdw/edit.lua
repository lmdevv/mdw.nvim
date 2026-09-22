local config = require("mdw.config")
local workspace = require("mdw.workspace")

local M = {}

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

return M
