local resolve = require("mdw.resolve")
local workspace = require("mdw.workspace")

local M = {}

local state = {
  server = nil,
  port = nil,
  bufnr = nil,
  root = nil,
}

local function escape(text)
  return (text or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
end

local function decode(text)
  text = text:gsub("+", " ")
  return (text:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

local function note_text(root, relpath)
  local path = root .. "/" .. relpath
  local bufnr = vim.fn.bufnr(path)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  end
  local handle = io.open(path, "rb")
  if not handle then
    return nil
  end
  local text = handle:read("*a")
  handle:close()
  return text
end

local function render_text(root, relpath, text, seen, depth)
  if depth > 8 then
    return "<p>Embed depth limit</p>"
  end
  seen[relpath] = true
  local parts = {}
  local lines = vim.split(text or "", "\n", { plain = true })
  for _, line in ipairs(lines) do
    local embed = line:match("^%s*!%[%[(.-)%]%]")
    local wiki = line:match("^%s*%[%[(.-)%]%]")
    if embed then
      local target = embed:match("^([^|#]+)") or embed
      local result = resolve.resolve(root, relpath, { syntax = "wikilink", target = vim.trim(target) })
      if result.kind == "resolved" then
        local child = result.matches[1].relpath
        if seen[child] then
          parts[#parts + 1] = "<p>Embed cycle: " .. escape(child) .. "</p>"
        else
          local body = note_text(root, child) or ""
          parts[#parts + 1] = '<article data-embed="' .. escape(child) .. '">' .. render_text(root, child, body, seen, depth + 1) .. "</article>"
          seen[child] = nil
        end
      else
        parts[#parts + 1] = "<p>Missing embed " .. escape(target) .. "</p>"
      end
    elseif wiki then
      local target = wiki:match("^([^|#]+)") or wiki
      local label = wiki:match("|(.+)$") or target
      local result = resolve.resolve(root, relpath, { syntax = "wikilink", target = vim.trim(target) })
      local href = result.kind == "resolved" and ("/note?path=" .. result.matches[1].relpath) or "#"
      parts[#parts + 1] = '<p><a href="' .. escape(href) .. '">' .. escape(label) .. "</a></p>"
    else
      parts[#parts + 1] = "<p>" .. escape(line) .. "</p>"
    end
  end
  return table.concat(parts, "\n")
end

function M.html(root, relpath)
  local text = note_text(root, relpath) or ""
  local body = render_text(root, relpath, text, {}, 1)
  return "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>"
    .. escape(relpath)
    .. "</title></head><body><h1>"
    .. escape(relpath)
    .. "</h1>\n"
    .. body
    .. "\n</body></html>"
end

local function page_for(path)
  local root = state.root
  local relpath = nil
  local query = path:match("^/note%?path=(.*)$")
  if query then
    relpath = decode(query)
  elseif state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    local name = vim.api.nvim_buf_get_name(state.bufnr)
    relpath = workspace.relpath(root, name)
  end
  if not root or not relpath then
    return "<!DOCTYPE html><html><body><p>No note</p></body></html>"
  end
  return M.html(root, relpath)
end

local function respond(client, body)
  local payload = "HTTP/1.0 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: "
    .. tostring(#body)
    .. "\r\nConnection: close\r\n\r\n"
    .. body
  client:write(payload, function()
    client:shutdown()
    client:close()
  end)
end

function M.stop()
  if state.server then
    state.server:close()
  end
  state.server = nil
  state.port = nil
end

function M.port()
  return state.port
end

function M.start(bufnr)
  M.stop()
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(bufnr)
  if not workspace.is_note_name(name) then
    return nil, "open a note before starting the preview"
  end
  local server = vim.uv.new_tcp()
  if not server then
    return nil, "could not open a preview socket"
  end
  local ok = server:bind("127.0.0.1", 0)
  if not ok then
    server:close()
    return nil, "could not bind the preview server"
  end
  server:listen(16, function()
    local client = vim.uv.new_tcp()
    if not client or not server:accept(client) then
      return
    end
    local received = ""
    client:read_start(function(err, chunk)
      if err or not chunk then
        return
      end
      received = received .. chunk
      if not received:find("\r\n\r\n", 1, true) then
        return
      end
      local request = received:match("GET%s+([^%s]+)") or "/"
      vim.schedule(function()
        respond(client, page_for(request))
      end)
    end)
  end)
  local address = server:getsockname()
  state.server = server
  state.port = address and address.port or nil
  state.bufnr = bufnr
  state.root = workspace.resolve(bufnr)
  return state.port
end

function M.toggle()
  if state.server then
    M.stop()
    vim.notify("mdw preview stopped", vim.log.levels.INFO)
    return nil
  end
  local port, err = M.start()
  if not port then
    vim.notify("mdw: " .. (err or "could not start the preview"), vim.log.levels.ERROR)
    return nil, err
  end
  local url = "http://127.0.0.1:" .. port .. "/"
  vim.notify("mdw preview " .. url, vim.log.levels.INFO)
  return url
end

return M
