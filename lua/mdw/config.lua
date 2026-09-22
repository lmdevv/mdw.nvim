local M = {}

local EXTENSIONS = { "md", "markdown", "mdc", "mdx", "mkd" }

local defaults = {
  workspace = {
    root = nil,
  },
  search = {
    enrich_files = false,
  },
  notes = {
    extensions = EXTENSIONS,
  },
  navigation = {
    gd = true,
  },
  create = {
    backend = "local",
    templates = {},
    default_template = nil,
  },
  daily = {
    folder = nil,
    format = nil,
    template = nil,
  },
  obsidian = {
    enabled = false,
    command = "obsidian",
    import_daily = false,
  },
  format = {
    enabled = true,
    command = "rumdl",
    format_on_save = false,
    lint = true,
  },
  edit = {
    cycle = "<C-8>",
    attachments = "assets",
    clipboard = nil,
  },
  render = {
    enabled = false,
    opts = {},
  },
  lsp = {
    enabled = false,
    command = "markdown-oxide",
    rename = false,
  },
}

local state = {
  ready = false,
  config = vim.deepcopy(defaults),
}

local function copy_extensions(list)
  local out = {}
  for i, ext in ipairs(list) do
    if type(ext) ~= "string" or ext == "" then
      error("mdw: notes.extensions[" .. i .. "] must be a non-empty string")
    end
    out[i] = ext:lower():gsub("^%.", "")
  end
  return out
end

function M.defaults()
  return vim.deepcopy(defaults)
end

function M.ready()
  return state.ready
end

function M.get()
  return state.config
end

function M.apply(opts)
  if opts ~= nil and type(opts) ~= "table" then
    error("mdw: setup options must be a table")
  end
  opts = opts or {}
  local workspace = opts.workspace or {}
  local search = opts.search or {}
  local notes = opts.notes or {}

  if workspace.root ~= nil and type(workspace.root) ~= "string" then
    error("mdw: workspace.root must be a string")
  end
  if search.enrich_files ~= nil and type(search.enrich_files) ~= "boolean" then
    error("mdw: search.enrich_files must be a boolean")
  end

  local extensions = notes.extensions and copy_extensions(notes.extensions) or vim.deepcopy(EXTENSIONS)
  local navigation = opts.navigation or {}
  local create = opts.create or {}
  local daily = opts.daily or {}
  local obsidian = opts.obsidian or {}
  if navigation.gd ~= nil and type(navigation.gd) ~= "boolean" then
    error("mdw: navigation.gd must be a boolean")
  end
  if create.backend ~= nil and create.backend ~= "local" and create.backend ~= "obsidian" then
    error("mdw: create.backend must be local or obsidian")
  end
  if create.templates ~= nil and type(create.templates) ~= "table" then
    error("mdw: create.templates must be a table")
  end
  if create.default_template ~= nil and type(create.default_template) ~= "string" then
    error("mdw: create.default_template must be a string")
  end
  if daily.folder ~= nil and type(daily.folder) ~= "string" then
    error("mdw: daily.folder must be a string")
  end
  if daily.format ~= nil and type(daily.format) ~= "string" then
    error("mdw: daily.format must be a string")
  end
  if daily.template ~= nil and type(daily.template) ~= "string" then
    error("mdw: daily.template must be a string")
  end
  if obsidian.enabled ~= nil and type(obsidian.enabled) ~= "boolean" then
    error("mdw: obsidian.enabled must be a boolean")
  end
  if obsidian.command ~= nil and type(obsidian.command) ~= "string" then
    error("mdw: obsidian.command must be a string")
  end
  if obsidian.import_daily ~= nil and type(obsidian.import_daily) ~= "boolean" then
    error("mdw: obsidian.import_daily must be a boolean")
  end
  local format = opts.format or {}
  local edit = opts.edit or {}
  local render = opts.render or {}
  local lsp = opts.lsp or {}
  if format.enabled ~= nil and type(format.enabled) ~= "boolean" then
    error("mdw: format.enabled must be a boolean")
  end
  if format.command ~= nil and type(format.command) ~= "string" then
    error("mdw: format.command must be a string")
  end
  if format.format_on_save ~= nil and type(format.format_on_save) ~= "boolean" then
    error("mdw: format.format_on_save must be a boolean")
  end
  if format.lint ~= nil and type(format.lint) ~= "boolean" then
    error("mdw: format.lint must be a boolean")
  end
  if edit.cycle ~= nil and edit.cycle ~= false and type(edit.cycle) ~= "string" then
    error("mdw: edit.cycle must be a string or false")
  end
  if edit.attachments ~= nil and type(edit.attachments) ~= "string" then
    error("mdw: edit.attachments must be a string")
  end
  if edit.clipboard ~= nil and type(edit.clipboard) ~= "table" then
    error("mdw: edit.clipboard must be a command list")
  end
  if render.enabled ~= nil and type(render.enabled) ~= "boolean" then
    error("mdw: render.enabled must be a boolean")
  end
  if render.opts ~= nil and type(render.opts) ~= "table" then
    error("mdw: render.opts must be a table")
  end
  if lsp.enabled ~= nil and type(lsp.enabled) ~= "boolean" then
    error("mdw: lsp.enabled must be a boolean")
  end
  if lsp.command ~= nil and type(lsp.command) ~= "string" then
    error("mdw: lsp.command must be a string")
  end
  if lsp.rename ~= nil and type(lsp.rename) ~= "boolean" then
    error("mdw: lsp.rename must be a boolean")
  end
  local templates = {}
  for name, body in pairs(create.templates or {}) do
    if type(name) ~= "string" or type(body) ~= "string" then
      error("mdw: create.templates entries must be strings")
    end
    templates[name] = body
  end
  state.config = {
    workspace = {
      root = workspace.root,
    },
    search = {
      enrich_files = search.enrich_files == true,
    },
    notes = {
      extensions = extensions,
    },
    navigation = {
      gd = navigation.gd ~= false,
    },
    create = {
      backend = create.backend or "local",
      templates = templates,
      default_template = create.default_template,
    },
    daily = {
      folder = daily.folder,
      format = daily.format,
      template = daily.template,
    },
    obsidian = {
      enabled = obsidian.enabled == true,
      command = obsidian.command or "obsidian",
      import_daily = obsidian.import_daily == true,
    },
    format = {
      enabled = format.enabled ~= false,
      command = format.command or "rumdl",
      format_on_save = format.format_on_save == true,
      lint = format.lint ~= false,
    },
    edit = {
      cycle = edit.cycle == nil and "<C-8>" or edit.cycle,
      attachments = edit.attachments or "assets",
      clipboard = edit.clipboard,
    },
    render = {
      enabled = render.enabled == true,
      opts = render.opts or {},
    },
    lsp = {
      enabled = lsp.enabled == true,
      command = lsp.command or "markdown-oxide",
      rename = lsp.rename == true,
    },
  }
  state.ready = true
  return state.config
end

return M
