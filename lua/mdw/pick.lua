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

function M.call_target(fn)
  local ok, mini = pcall(require, "mini.pick")
  if ok and type(mini.get_picker_state) == "function" then
    local picker_state = mini.get_picker_state()
    local target = picker_state and picker_state.windows and picker_state.windows.target
    if target and vim.api.nvim_win_is_valid(target) then
      vim.api.nvim_win_call(target, fn)
      return
    end
  end
  fn()
end

function M.choose(item)
  if type(item) ~= "table" or type(item.path) ~= "string" or item.path == "" then
    return
  end
  M.call_target(function()
    vim.cmd.edit(vim.fn.fnameescape(item.path))
  end)
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

local function narrow(items, prompt)
  prompt = vim.trim(plain_prompt(prompt or ""))
  if prompt == "" then
    return items
  end
  local notes = {}
  for _, item in ipairs(items) do
    if item.note then
      notes[#notes + 1] = item.note
    end
  end
  local hits = search.query_notes(notes, prompt)
  local by_rel = {}
  for _, item in ipairs(items) do
    by_rel[item.relpath] = item
  end
  local out = {}
  for _, hit in ipairs(hits) do
    local item = by_rel[hit.relpath]
    if item then
      out[#out + 1] = item
    end
  end
  return out
end

local function runtime_has(path)
  return #vim.api.nvim_get_runtime_file(path, false) > 0
end

function M.mini_available()
  local loaded = package.loaded["mini.pick"]
  if type(loaded) == "table" and type(loaded.start) == "function" then
    return true
  end
  return loaded == nil and runtime_has("lua/mini/pick.lua")
end

function M.snacks_available()
  local loaded = package.loaded["snacks"]
  if type(loaded) == "table" and type(loaded.picker) == "table" and type(loaded.picker.pick) == "function" then
    return true
  end
  return loaded == nil and runtime_has("lua/snacks/picker/init.lua")
end

function M.telescope_available()
  if package.loaded["telescope.pickers"] ~= nil or package.loaded["telescope"] ~= nil then
    return true
  end
  return runtime_has("lua/telescope/pickers.lua")
end

function M.backend()
  local choice = config.get().search.picker or "auto"
  if choice == "mini" and M.mini_available() then
    return "mini"
  end
  if choice == "snacks" and M.snacks_available() then
    return "snacks"
  end
  if choice == "telescope" and M.telescope_available() then
    return "telescope"
  end
  if choice == "select" then
    return "select"
  end
  if choice ~= "auto" then
    return "select"
  end
  if M.mini_available() then
    return "mini"
  end
  if M.snacks_available() then
    return "snacks"
  end
  if M.telescope_available() then
    return "telescope"
  end
  return "select"
end

local function deliver(on_choice, item)
  if not item then
    return
  end
  M.call_target(function()
    on_choice(item)
  end)
end

local function show_mini(title, items, on_choice, live)
  local mini = require("mini.pick")
  local source = {
    items = items,
    name = title,
    choose = function(item)
      deliver(on_choice, item)
    end,
  }
  if live then
    source.match = function(_, _, query)
      local prompt = vim.trim(plain_prompt(table.concat(query or {})))
      local narrowed = narrow(items, prompt)
      local positions = {}
      for index, item in ipairs(items) do
        positions[item.relpath] = index
      end
      local inds = {}
      for _, item in ipairs(narrowed) do
        local index = positions[item.relpath]
        if index then
          inds[#inds + 1] = index
        end
      end
      return inds
    end
  end
  return mini.start({ source = source })
end

local function show_snacks(title, items, on_choice, live)
  local snacks = require("snacks")
  local opts = {
    title = title,
    format = "text",
    confirm = function(picker, item)
      if picker and type(picker.close) == "function" then
        picker:close()
      end
      deliver(on_choice, item and (item.mdw or item))
    end,
  }
  if live then
    opts.live = true
    opts.pattern = function()
      return ""
    end
    opts.matcher = { fuzzy = false, sort_empty = false }
    opts.finder = function(_, ctx)
      local prompt = ctx and ctx.filter and ctx.filter.search or ""
      local found = {}
      for _, item in ipairs(narrow(items, prompt)) do
        found[#found + 1] = { text = item.text, file = item.path, path = item.path, mdw = item }
      end
      return found
    end
  else
    opts.items = {}
    for _, item in ipairs(items) do
      opts.items[#opts.items + 1] = {
        text = item.text or "",
        file = item.path,
        path = item.path,
        mdw = item,
      }
    end
  end
  return snacks.picker.pick(opts)
end

local function show_telescope(title, items, on_choice, live)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local finder
  local sorter
  if live then
    finder = finders.new_dynamic({
      fn = function(prompt)
        return narrow(items, prompt)
      end,
      entry_maker = function(item)
        return { value = item, display = item.text or "", ordinal = item.text or "" }
      end,
    })
    sorter = require("telescope.sorters").Sorter:new({
      discard = true,
      scoring_function = function()
        return 1
      end,
    })
  else
    finder = finders.new_table({
      results = items,
      entry_maker = function(item)
        return { value = item, display = item.text or "", ordinal = item.text or "" }
      end,
    })
    sorter = require("telescope.config").values.generic_sorter({})
  end
  return pickers.new({}, {
    prompt_title = title,
    finder = finder,
    sorter = sorter,
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if selection then
          deliver(on_choice, selection.value)
        end
      end)
      return true
    end,
  }):find()
end

local function show_select(title, items, on_choice)
  vim.ui.select(items, {
    prompt = title,
    format_item = function(item)
      return item.text or ""
    end,
  }, function(choice)
    deliver(on_choice, choice)
  end)
end

function M.show(title, items, on_choice, live)
  local backend = M.backend()
  local ok = false
  if backend == "mini" then
    ok = pcall(show_mini, title, items, on_choice, live)
  elseif backend == "snacks" then
    ok = pcall(show_snacks, title, items, on_choice, live)
  elseif backend == "telescope" then
    ok = pcall(show_telescope, title, items, on_choice, live)
  end
  if not ok then
    show_select(title, items, on_choice)
  end
end

function M.open(results)
  M.show("mdw notes", results, M.choose, true)
end

function M.search(query)
  local root = workspace.resolve(0)
  local results = search.query(root, query or "")
  M.open(results)
  return results
end

function M.available()
  return M.mini_available()
end

function M.enrich_enabled()
  return config.get().search.enrich_files == true
end

return M
