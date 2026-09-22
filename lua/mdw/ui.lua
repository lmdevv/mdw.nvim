local pick = require("mdw.pick")

local M = {}

function M.confirm(prompt)
  return vim.fn.confirm(prompt, "&Yes\n&No", 2) == 1
end

function M.choose(title, items)
  if #items == 0 then
    return
  end
  local ok, mini = pcall(require, "mini.pick")
  if ok and type(mini.start) == "function" and package.loaded["mini.pick"] ~= nil then
    mini.start({
      source = {
        items = items,
        name = title,
        choose = function(item)
          if item and item.choose then
            pick.call_target(item.choose)
          end
        end,
      },
    })
    return
  end
  vim.ui.select(items, {
    prompt = title,
    format_item = function(item)
      return item.text or ""
    end,
  }, function(choice)
    if choice and choice.choose then
      choice.choose()
    end
  end)
end

return M
