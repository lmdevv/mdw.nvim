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
    rumdl = false,
    format_on_save = false,
    lint = false,
    render = false,
    render_ready = false,
    lsp = false,
    lsp_ready = false,
    lsp_rename = false,
  }
  if not report.setup then
    return report
  end
  report.enrich = config.get().search.enrich_files
  report.obsidian = config.get().obsidian.enabled
  report.obsidian_command = require("mdw.obsidian").available()
  report.rumdl = require("mdw.format").available()
  report.format_on_save = config.get().format.format_on_save
  report.lint = config.get().format.lint
  report.render = config.get().render.enabled
  report.render_ready = require("mdw.render").active()
  report.lsp = config.get().lsp.enabled
  report.lsp_ready = require("mdw.lsp").available()
  report.lsp_rename = config.get().lsp.rename
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
  if report.rumdl then
    vim.health.ok("rumdl is available")
  else
    vim.health.info("rumdl was not found; :Mdw format and :Mdw lint are unavailable")
  end
  if report.format_on_save then
    vim.health.info("format on save is on")
  end
  if report.render and report.render_ready then
    vim.health.ok("render-markdown is enabled")
  elseif report.render then
    vim.health.warn("render.enabled is set, but render-markdown is not installed")
  else
    vim.health.info("in-buffer rendering is off")
  end
  if report.lsp and report.lsp_ready then
    vim.health.ok("markdown-oxide is available")
  elseif report.lsp then
    vim.health.warn("lsp.enabled is set, but markdown-oxide was not found")
  else
    vim.health.info("markdown-oxide is off")
  end
  if report.lsp_rename then
    vim.health.info("rename is owned by the language server")
  end
  for _, err in ipairs(report.errors) do
    vim.health.warn(err.path .. ": " .. err.message)
  end
  return report
end

return M
