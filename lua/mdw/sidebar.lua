local relations = require("mdw.relations")
local workspace = require("mdw.workspace")

local M = {}
local highlights = vim.api.nvim_create_namespace("mdw_sidebar")

local view_titles = {
  outline = "Outline",
  backlinks = "Backlinks",
  outgoing = "Links",
}

local state = {
  bufs = {},
  panes = {},
  legend = nil,
  source_buf = nil,
  source_path = nil,
  view = "all",
}

local function is_sidebar_window(win)
  if state.legend and state.legend.win == win and vim.api.nvim_win_is_valid(win) then
    return true
  end
  for _, pane in ipairs(state.panes) do
    if pane.win == win and vim.api.nvim_win_is_valid(win) then
      return true
    end
  end
  return false
end

local function valid_win()
  for _, pane in ipairs(state.panes) do
    if vim.api.nvim_win_is_valid(pane.win) then
      return pane.win
    end
  end
  return nil
end

local function source_window()
  if state.source_buf and vim.api.nvim_buf_is_valid(state.source_buf) then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == state.source_buf and not is_sidebar_window(win) then
        return win
      end
    end
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if not is_sidebar_window(win) then
      return win
    end
  end
  return nil
end

local function render_pane(pane)
  local buf = pane.buf
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.b[buf].mdw_source = state.source_path
  local root, relpath = nil, nil
  if state.source_path and state.source_path ~= "" then
    root = workspace.resolve(buf)
    relpath = workspace.relpath(root, state.source_path)
  end
  local items = {}
  if root and relpath then
    items = relations.entries(root, pane.view, relpath)
  end
  local lines = { view_titles[pane.view], "" }
  local by_line = {}
  if #items == 0 then
    lines[#lines + 1] = "No " .. pane.view
  end
  for _, item in ipairs(items) do
    lines[#lines + 1] = item.text
    by_line[#lines] = item
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, highlights, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, highlights, "Title", 0, 0, -1)
  vim.api.nvim_buf_set_extmark(buf, highlights, 0, 0, {
    virt_text = { { tostring(#items), "Comment" } },
    virt_text_pos = "right_align",
  })
  if #items == 0 then
    vim.api.nvim_buf_add_highlight(buf, highlights, "Comment", 2, 0, -1)
  end
  vim.b[buf].mdw_items = by_line
  vim.b[buf].mdw_source = state.source_path
end

local function render()
  for _, pane in ipairs(state.panes) do
    render_pane(pane)
  end
  if state.legend then
    vim.b[state.legend.buf].mdw_source = state.source_path
  end
end

local function jump()
  local win = vim.api.nvim_get_current_win()
  if not is_sidebar_window(win) then
    return
  end
  local items = vim.b[vim.api.nvim_win_get_buf(win)].mdw_items or {}
  local row = vim.api.nvim_win_get_cursor(win)[1]
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
  if state.view == view then
    render()
    return
  end
  M.close()
  state.view = view
  M.open(true)
end

local function buffer_for(view)
  local buf = state.bufs[view]
  if buf and vim.api.nvim_buf_is_valid(buf) then
    return buf
  end
  buf = vim.api.nvim_create_buf(false, true)
  state.bufs[view] = buf
  vim.api.nvim_buf_set_name(buf, "mdw://sidebar/" .. view)
  vim.bo[buf].filetype = "mdw-sidebar"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  local opts = { buffer = buf, nowait = true, silent = true }
  for key, target in pairs({ o = "outline", b = "backlinks", l = "outgoing", a = "all" }) do
    vim.keymap.set("n", key, function()
      set_view(target)
    end, opts)
  end
  vim.keymap.set("n", "<CR>", jump, opts)
  vim.keymap.set("n", "q", function()
    M.close()
  end, opts)
  return buf
end

local function add_pane(view)
  local win = vim.api.nvim_get_current_win()
  local buf = buffer_for(view)
  vim.api.nvim_win_set_buf(win, buf)
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].statusline = " "
  state.panes[#state.panes + 1] = { win = win, buf = buf, view = view }
end

local function add_legend()
  vim.cmd("belowright split")
  local win = vim.api.nvim_get_current_win()
  local buf = buffer_for("legend")
  vim.api.nvim_win_set_buf(win, buf)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "a All  o Outline  b Backlinks",
    "l Links  Enter Open  q Close",
  })
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, highlights, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, highlights, "Comment", 0, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, highlights, "Comment", 1, 0, -1)
  vim.b[buf].mdw_legend = true
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].cursorline = false
  vim.wo[win].statusline = " "
  vim.wo[win].winfixheight = true
  vim.api.nvim_win_set_height(win, 2)
  state.legend = { win = win, buf = buf }
end

function M.is_open()
  return valid_win() ~= nil
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

function M.open(keep_source)
  local current = vim.api.nvim_get_current_buf()
  if not keep_source and vim.bo[current].filetype ~= "mdw-sidebar" and workspace.is_note_name(vim.api.nvim_buf_get_name(current)) then
    state.source_buf = current
    state.source_path = workspace.normalize(vim.api.nvim_buf_get_name(current))
  end
  if valid_win() then
    if not is_sidebar_window(vim.api.nvim_get_current_win()) then
      vim.api.nvim_set_current_win(valid_win())
    end
    render()
    return
  end
  vim.cmd("botright 40vsplit")
  if state.view == "all" then
    local height = vim.api.nvim_win_get_height(0)
    add_pane("outline")
    vim.cmd("belowright split")
    add_pane("backlinks")
    vim.cmd("belowright split")
    add_pane("outgoing")
    add_legend()
    local third = math.max(3, math.floor((height - 5) / 3))
    vim.api.nvim_win_set_height(state.panes[1].win, third)
    vim.api.nvim_win_set_height(state.panes[2].win, third)
    vim.api.nvim_set_current_win(state.panes[1].win)
  else
    add_pane(state.view)
    add_legend()
    vim.api.nvim_set_current_win(state.panes[1].win)
  end
  render()
end

function M.close()
  if state.legend and vim.api.nvim_win_is_valid(state.legend.win) then
    vim.api.nvim_win_close(state.legend.win, true)
  end
  state.legend = nil
  for index = #state.panes, 1, -1 do
    local win = state.panes[index].win
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  state.panes = {}
  state.view = "all"
end

function M.toggle()
  if valid_win() then
    local current = vim.api.nvim_get_current_win()
    if is_sidebar_window(current) then
      M.close()
    else
      vim.api.nvim_set_current_win(valid_win())
      render()
    end
    return
  end
  M.open()
end

return M
