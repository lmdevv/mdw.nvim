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
  }
  state.ready = true
  return state.config
end

return M
