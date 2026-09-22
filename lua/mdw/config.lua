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
  }
  state.ready = true
  return state.config
end

return M
