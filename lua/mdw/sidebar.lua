local relations = require("mdw.relations")
local workspace = require("mdw.workspace")

local M = {}

local state = {
  buf = nil,
  win = nil,
  source_buf = nil,
  source_path = nil,
  view = "outline",
}

local function valid_win()
  return state.win and vim.api.nvim_win_is_valid(state.win)
end

local function source_window()
  if state.source_buf and vim.api.nvim_buf_is_valid(state.source_buf) then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == state.source_buf and win ~= state.win then
        return win
      end
    end
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if win ~= state.win then
      return win
    end
  end
  return nil
end

local function render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  vim.b[state.buf].mdw_source = state.source_path
  local root, relpath = nil, nil
  if state.source_path and state.source_path ~= "" then
    root = workspace.resolve(state.buf)
    relpath = workspace.relpath(root, state.source_path)
  end
  local items = {}
  if root and relpath then
    items = relations.entries(root, state.view, relpath)
  end
  local lines = {
    state.view .. "  " .. (relpath or ""),
    "",
  }
  local by_line = {}
  if #items == 0 then
    lines[#lines + 1] = "No " .. state.view
  end
  for _, item in ipairs(items) do
    lines[#lines + 1] = item.text
    by_line[#lines] = item
  end
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  vim.b[state.buf].mdw_items = by_line
  vim.b[state.buf].mdw_source = state.source_path
end

local function jump()
  local items = vim.b[state.buf].mdw_items or {}
  local row = vim.api.nvim_win_get_cursor(state.win)[1]
  local item = items[row]
  if not item or not item.path then
    return
  end
  local target = source_window()
  local function edit()
    vim.cmd.edit(vim.fn.fnameescape(item.path))
    pcall(vim.api.nvim_win_set_cursor, 0, { item.line or 1, math.max((item.col or 1) - 1, 0) })
  end
  if target then
    vim.api.nvim_win_call(target, edit)
    vim.api.nvim_set_current_win(target)
  else
    edit()
  end
end

local function set_view(view)
  state.view = view
  render()
end

function M.is_open()
  return valid_win()
end

function M.source_path()
  return state.source_path
end

function M.on_note(bufnr)
  if not valid_win() then
    return
  end
  if vim.bo[bufnr].filetype == "mdw-sidebar" then
    return
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  if not workspace.is_note_name(name) then
    return
  end
  state.source_buf = bufnr
  state.source_path = workspace.normalize(name)
  render()
end

function M.open()
  local current = vim.api.nvim_get_current_buf()
  if vim.bo[current].filetype ~= "mdw-sidebar" and workspace.is_note_name(vim.api.nvim_buf_get_name(current)) then
    state.source_buf = current
    state.source_path = workspace.normalize(vim.api.nvim_buf_get_name(current))
  end
  if valid_win() then
    vim.api.nvim_set_current_win(state.win)
    render()
    return
  end
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(state.buf, "mdw://sidebar")
    vim.bo[state.buf].filetype = "mdw-sidebar"
    vim.bo[state.buf].bufhidden = "hide"
    vim.bo[state.buf].swapfile = false
    local opts = { buffer = state.buf, nowait = true, silent = true }
    vim.keymap.set("n", "o", function()
      set_view("outline")
    end, opts)
    vim.keymap.set("n", "b", function()
      set_view("backlinks")
    end, opts)
    vim.keymap.set("n", "l", function()
      set_view("outgoing")
    end, opts)
    vim.keymap.set("n", "<CR>", jump, opts)
    vim.keymap.set("n", "q", function()
      M.close()
    end, opts)
  end
  vim.cmd("botright 40vsplit")
  state.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.win, state.buf)
  vim.wo[state.win].wrap = false
  vim.wo[state.win].number = false
  render()
end

function M.close()
  if valid_win() then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
end

function M.toggle()
  if valid_win() then
    local current = vim.api.nvim_get_current_win()
    if current == state.win then
      M.close()
    else
      vim.api.nvim_set_current_win(state.win)
      render()
    end
    return
  end
  M.open()
end

return M
