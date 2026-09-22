local config = require("mdw.config")
local search = require("mdw.search")
local workspace = require("mdw.workspace")

local M = {}

local state = {
  active = false,
  original_files = nil,
  original_registry = nil,
}

function M.wrapped()
  return state.active
end

function M.choose(item)
  if type(item) ~= "table" or type(item.path) ~= "string" or item.path == "" then
    return
  end
  local function edit()
    vim.cmd.edit(vim.fn.fnameescape(item.path))
  end
  local ok, mini = pcall(require, "mini.pick")
  if ok and type(mini.get_picker_state) == "function" then
    local picker_state = mini.get_picker_state()
    local target = picker_state and picker_state.windows and picker_state.windows.target
    if target and vim.api.nvim_win_is_valid(target) then
      vim.api.nvim_win_call(target, edit)
      return
    end
  end
  edit()
end

local function plain_prompt(prompt)
  local query = prompt
  local first = query:sub(1, 1)
  if first == "'" or first == "^" or first == "*" then
    query = query:sub(2)
  end
  if query:sub(-1) == "$" then
    query = query:sub(1, -2)
  end
  return query
end

local function absolute_item(cwd, item)
  item = item:gsub("^%./", "")
  if item:sub(1, 1) == "/" then
    return workspace.normalize(item)
  end
  return workspace.normalize(cwd .. "/" .. item)
end

function M.enrich_match(stritems, inds, query, prior, root, cwd)
  local base
  if prior then
    base = prior(stritems, inds, query) or {}
  else
    local mini = require("mini.pick")
    base = mini.default_match(stritems, inds, query) or {}
  end
  if root == nil then
    return base
  end
  local prompt = plain_prompt(table.concat(query or {}))
  local hits = search.query(root, prompt)
  local wanted = {}
  for _, hit in ipairs(hits) do
    wanted[workspace.normalize(hit.path)] = hit
  end
  local by_index = {}
  for index, stritem in ipairs(stritems) do
    local path = absolute_item(cwd, stritem)
    local hit = wanted[path]
    if hit then
      by_index[index] = hit.rank
    end
  end
  local seen = {}
  local ranked = {}
  for index, rank in pairs(by_index) do
    ranked[#ranked + 1] = { index = index, rank = rank }
    seen[index] = true
  end
  table.sort(ranked, function(a, b)
    if a.rank ~= b.rank then
      return a.rank < b.rank
    end
    return a.index < b.index
  end)
  local out = {}
  for _, entry in ipairs(ranked) do
    out[#out + 1] = entry.index
  end
  for _, index in ipairs(base) do
    if not seen[index] then
      out[#out + 1] = index
    end
  end
  return out
end

local function inject(local_opts, opts)
  local root = workspace.resolve(0)
  local source = opts and opts.source or nil
  local cwd = source and source.cwd or vim.fn.getcwd()
  cwd = workspace.normalize(cwd)
  if not workspace.contains(root, cwd) then
    return local_opts, opts
  end
  local prior = source and source.match or nil
  local merged = vim.tbl_deep_extend("force", {}, opts or {})
  merged.source = merged.source or {}
  merged.source.match = function(stritems, inds, query)
    return M.enrich_match(stritems, inds, query, prior, root, cwd)
  end
  return local_opts, merged
end

function M.configure(enabled)
  if not enabled then
    if not state.active then
      return
    end
    local ok, mini = pcall(require, "mini.pick")
    if ok then
      if state.original_files then
        mini.builtin.files = state.original_files
      end
      if mini.registry and state.original_registry then
        mini.registry.files = state.original_registry
      end
    end
    state.active = false
    state.original_files = nil
    state.original_registry = nil
    return
  end
  if state.active then
    return
  end
  local ok, mini = pcall(require, "mini.pick")
  if not ok or type(mini.builtin) ~= "table" or type(mini.builtin.files) ~= "function" then
    return
  end
  state.original_files = mini.builtin.files
  state.original_registry = mini.registry and mini.registry.files or nil
  mini.builtin.files = function(local_opts, opts)
    local_opts, opts = inject(local_opts, opts)
    return state.original_files(local_opts, opts)
  end
  if mini.registry then
    mini.registry.files = function(local_opts)
      return mini.builtin.files(local_opts)
    end
  end
  state.active = true
end

function M.open(results)
  if package.loaded["mini.pick"] ~= nil or #vim.api.nvim_get_runtime_file("lua/mini/pick.lua", false) > 0 then
    local ok, mini = pcall(require, "mini.pick")
    if ok and type(mini.start) == "function" then
      return mini.start({
        source = {
          items = results,
          name = "Mdw notes",
          choose = M.choose,
          match = function(_, _, query)
            local prompt = vim.trim(plain_prompt(table.concat(query or {})))
            if prompt == "" then
              local inds = {}
              for index = 1, #results do
                inds[index] = index
              end
              return inds
            end
            local narrowed = search.query_notes(
              vim.tbl_map(function(item)
                return item.note
              end, results),
              plain_prompt(prompt)
            )
            local positions = {}
            for index, item in ipairs(results) do
              positions[item.relpath] = index
            end
            local inds = {}
            for _, hit in ipairs(narrowed) do
              local index = positions[hit.relpath]
              if index then
                inds[#inds + 1] = index
              end
            end
            return inds
          end,
        },
      })
    end
  end
  vim.ui.select(results, {
    prompt = "Mdw notes",
    format_item = function(item)
      return item.text
    end,
  }, function(choice)
    if choice then
      M.choose(choice)
    end
  end)
end

function M.search(query)
  local root = workspace.resolve(0)
  local results = search.query(root, query or "")
  M.open(results)
  return results
end

function M.available()
  if package.loaded["mini.pick"] ~= nil then
    return true
  end
  return #vim.api.nvim_get_runtime_file("lua/mini/pick.lua", false) > 0
end

function M.enrich_enabled()
  return config.get().search.enrich_files == true
end

return M
