local config = require("mdw.config")

local M = {}

local started = false

function M.active()
  return started
end

function M.configure()
  if config.get().render.enabled ~= true then
    return false
  end
  if started then
    return true
  end
  local ok, plugin = pcall(require, "render-markdown")
  if not ok or type(plugin) ~= "table" or type(plugin.setup) ~= "function" then
    return false
  end
  plugin.setup(config.get().render.opts or {})
  started = true
  return true
end

function M.reset()
  started = false
end

return M
