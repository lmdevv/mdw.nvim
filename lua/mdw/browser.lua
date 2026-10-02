local config = require("mdw.config")
local workspace = require("mdw.workspace")

local M = {}
local MAX_BYTES = 1024 * 1024
local MAX_URL = 60000
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

local function base64url(data)
  local out = {}
  for i = 1, #data, 3 do
    local a, b, c = data:byte(i, i + 2)
    local value = a * 65536 + (b or 0) * 256 + (c or 0)
    local function digit(shift)
      local n = math.floor(value / 2 ^ shift) % 64 + 1
      return ALPHABET:sub(n, n)
    end
    out[#out + 1] = digit(18) .. digit(12) .. (b and digit(6) or "") .. (c and digit(0) or "")
  end
  return table.concat(out)
end

-- Version 1: UTF-8 JSON {md, title}, raw DEFLATE, unpadded base64url.
function M.url(bufnr)
  bufnr = bufnr or 0
  local path = vim.api.nvim_buf_get_name(bufnr)
  if vim.bo[bufnr].buftype ~= "" or not workspace.is_note_name(path) then
    return nil, "open a note first"
  end
  local file, err = io.open(path, "rb")
  if not file then
    return nil, "could not read the saved note; save it with :write first: " .. tostring(err)
  end
  local md = file:read(MAX_BYTES + 1) or ""
  file:close()
  if #md > MAX_BYTES then
    return nil, "note exceeds the browser preview limit of 1 MiB"
  end
  local ok, encoded = pcall(function()
    local title = vim.fs.basename(path):gsub("%.[^.]+$", "")
    -- Lua table iteration varies between processes; keep the wire order stable.
    local payload = '{"md":' .. vim.json.encode(md) .. ',"title":' .. vim.json.encode(title) .. "}"
    local compressed = require("mdw.vendor.deflate"):CompressDeflate(payload, { level = 5 })
    return base64url(compressed)
  end)
  if not ok then
    return nil, "could not encode the saved note: " .. tostring(encoded)
  end
  local url = config.get().preview.url:gsub("/+$", "") .. "/#v=1&doc=" .. encoded
  if #url > MAX_URL then
    return nil, "compressed note is too large for a browser link (limit: 60000 characters)"
  end
  return url
end

function M.open_current(bufnr)
  local url, err = M.url(bufnr)
  if not url then
    return nil, err
  end
  local ok, process, open_err = pcall(vim.ui.open, url)
  if not ok then
    return nil, tostring(process)
  end
  if not process then
    return nil, open_err or "could not open the browser"
  end
  return process
end

return M
