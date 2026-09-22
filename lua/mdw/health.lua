local compat = require("mdw.compat")
local config = require("mdw.config")
local index = require("mdw.index")
local pick = require("mdw.pick")
local workspace = require("mdw.workspace")

local M = {}

function M.collect()
  local report = {
    version = compat.string(),
    version_ok = compat.supported(),
    setup = config.ready(),
    root = nil,
    notes = 0,
    revision = 0,
    errors = {},
    mini_pick = pick.available(),
    enrich = false,
    enrich_wrapped = pick.wrapped(),
    obsidian = false,
    obsidian_command = nil,
  }
  if not report.setup then
    return report
  end
  report.enrich = config.get().search.enrich_files
  report.obsidian = config.get().obsidian.enabled
  report.obsidian_command = require("mdw.obsidian").available()
  local ok, root = pcall(workspace.resolve, 0)
  if ok and root then
    report.root = root
    local cache = index.ensure(root)
    report.revision = cache.revision
    report.notes = #index.list(root)
    report.errors = index.error_list(root)
  end
  return report
end

function M.check()
  local report = M.collect()
  vim.health.start("mdw")
  if report.version_ok then
    vim.health.ok("Neovim " .. report.version)
  else
    vim.health.error("Neovim " .. report.version .. " is older than 0.11")
  end
  if not report.setup then
    vim.health.warn("require('mdw').setup() has not been called")
    return report
  end
  if report.root then
    vim.health.ok("workspace " .. report.root)
  else
    vim.health.error("workspace root could not be resolved")
  end
  vim.health.info(string.format("%d notes, index revision %d", report.notes, report.revision))
  if report.mini_pick then
    vim.health.ok("mini.pick is available")
  else
    vim.health.info(":Mdw search uses vim.ui.select because mini.pick is not installed")
  end
  if report.enrich and report.enrich_wrapped then
    vim.health.ok("file-search enrichment is enabled")
  elseif report.enrich then
    vim.health.warn("search.enrich_files is set, but mini.pick could not be wrapped")
  else
    vim.health.info("file-search enrichment is off")
  end
  if report.obsidian and report.obsidian_command then
    vim.health.ok("obsidian CLI is available")
  elseif report.obsidian then
    vim.health.warn("obsidian integration is enabled, but the CLI was not found")
  else
    vim.health.info("obsidian CLI integration is off")
  end
  for _, err in ipairs(report.errors) do
    vim.health.warn(err.path .. ": " .. err.message)
  end
  return report
end

return M
