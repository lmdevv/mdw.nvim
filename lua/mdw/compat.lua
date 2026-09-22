local M = {}

local MINIMUM = { 0, 11, 0 }

function M.supported(version)
  version = version or vim.version()
  return not vim.version.lt(version, MINIMUM)
end

function M.string(version)
  version = version or vim.version()
  return string.format("%d.%d.%d", version.major, version.minor, version.patch)
end

return M
