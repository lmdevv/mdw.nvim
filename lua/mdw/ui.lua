local pick = require("mdw.pick")

local M = {}

function M.confirm(prompt)
  return vim.fn.confirm(prompt, "&Yes\n&No", 2) == 1
end

function M.choose(title, items)
  if #items == 0 then
    return
  end
  pick.show(title, items, function(item)
    if item and item.choose then
      item.choose()
    end
  end, false)
end

return M
