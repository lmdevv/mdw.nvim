local root = vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(arg[0])))
vim.o.runtimepath = root .. "," .. vim.env.VIMRUNTIME
vim.o.packpath = ""
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local failures = 0
local checks = 0

local function fail(message)
  failures = failures + 1
  io.stderr:write("FAIL " .. message .. "\n")
end

local function eq(actual, expected, message)
  checks = checks + 1
  if actual ~= expected then
    fail(message .. "\n  expected: " .. vim.inspect(expected) .. "\n  actual:   " .. vim.inspect(actual))
  end
end

local function truthy(value, message)
  checks = checks + 1
  if not value then
    fail(message .. "\n  value: " .. vim.inspect(value))
  end
end

local function same(actual, expected, message)
  checks = checks + 1
  if not vim.deep_equal(actual, expected) then
    fail(message .. "\n  expected: " .. vim.inspect(expected) .. "\n  actual:   " .. vim.inspect(actual))
  end
end

local saved_cwd = vim.fn.getcwd()
local temps = {}

local function tmp()
  local dir = string.format("/tmp/mdw-m1-%d", vim.uv.hrtime())
  vim.fn.mkdir(dir, "p")
  temps[#temps + 1] = dir
  return dir
end

local function write(dir, rel, text)
  local path = dir .. "/" .. rel
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local handle = assert(io.open(path, "wb"))
  handle:write(text)
  handle:close()
  return path
end

local function git_init(dir)
  local result = vim.system({ "git", "init", "-q" }, { cwd = dir }):wait()
  if result.code ~= 0 then
    error("git init failed: " .. (result.stderr or ""))
  end
end

local function rels(results)
  local out = {}
  for _, item in ipairs(results) do
    out[#out + 1] = item.relpath
  end
  return out
end

local function reasons(results)
  local out = {}
  for _, item in ipairs(results) do
    out[#out + 1] = item.relpath .. "=" .. item.reason
  end
  return out
end

local tests = {}
local function add(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

add("plugin file loads once", function()
  vim.g.loaded_mdw = nil
  vim.cmd("runtime plugin/mdw.lua")
  eq(vim.g.loaded_mdw, true, "plugin sets loaded flag")
  vim.cmd("runtime plugin/mdw.lua")
  eq(vim.g.loaded_mdw, true, "second runtime keeps the flag")
end)

add("setup is idempotent", function()
  local mdw = require("mdw")
  mdw.setup({})
  local first = #vim.api.nvim_get_autocmds({ group = "mdw" })
  mdw.setup({})
  local second = #vim.api.nvim_get_autocmds({ group = "mdw" })
  eq(first, second, "autocmd count stays stable")
  truthy(first > 0, "autocmds exist")
  truthy(vim.api.nvim_get_commands({ builtin = false }).Mdw ~= nil, "Mdw command exists")
end)

add("scanner reads metadata and ignores code, links, and labels", function()
  local scan = require("mdw.scan")
  local note = scan.parse([=[
---
title: "Budget: yearly"
aliases:
  - yearly plan
tags: [work, home]
---

# Ignored heading

See [[Other|UniqueLabel]] and [[Note#Section]].
[see](file.md#section) and #public
`#hidden` and #shown

```lua
#secret
```

<div>#jsxTag</div>
]=], "plan.md", "plan")
  eq(note.title, "Budget: yearly", "frontmatter title wins")
  eq(note.title_source, "frontmatter", "title source")
  same(note.aliases, { "yearly plan" }, "aliases")
  same(note.tags, { "work", "home", "public", "shown", "jsxTag" }, "tags skip code, wikilinks, and destinations")

  local heading = scan.parse("# Café notes\n\n#later\n", "cafe.md", "cafe")
  eq(heading.title, "Café notes", "first ATX heading")
  same(heading.tags, { "later" }, "tag after heading")

  local stem = scan.parse("no heading\n", "stem.md", "stem")
  eq(stem.title, "stem", "filename stem title")
  eq(stem.title_source, "filename", "filename title source")

  local numeric = scan.parse("---\ntitle: 12\n---\n# Real\n", "n.md", "n")
  eq(numeric.title, "Real", "non-string title falls through to heading")

  local bad = scan.parse("---\ntitle: \"nope\n", "bad.md", "bad")
  eq(bad, nil, "unclosed frontmatter is skipped")
end)

add("search ranking, tags, and dedupe", function()
  local search = require("mdw.search")
  local function note(fields)
    return fields
  end
  local notes = {
    note({
      path = "/w/exact.md",
      relpath = "exact.md",
      filename = "exact.md",
      title = "Budget",
      aliases = { "yearly" },
      tags = { "work" },
    }),
    note({
      path = "/w/prefix.md",
      relpath = "prefix.md",
      filename = "prefix.md",
      title = "Budget plan",
      aliases = {},
      tags = {},
    }),
    note({
      path = "/w/middle.md",
      relpath = "middle.md",
      filename = "middle.md",
      title = "Annual budget",
      aliases = {},
      tags = {},
    }),
    note({
      path = "/w/budget-notes.md",
      relpath = "budget-notes.md",
      filename = "budget-notes.md",
      title = "Other",
      aliases = {},
      tags = {},
    }),
    note({
      path = "/w/dir/budget/other.md",
      relpath = "dir/budget/other.md",
      filename = "other.md",
      title = "Else",
      aliases = {},
      tags = {},
    }),
    note({
      path = "/w/misc.md",
      relpath = "misc.md",
      filename = "misc.md",
      title = "Else",
      aliases = {},
      tags = { "budget" },
    }),
    note({
      path = "/w/a/note.md",
      relpath = "a/note.md",
      filename = "note.md",
      title = "Same",
      aliases = {},
      tags = { "work" },
    }),
    note({
      path = "/w/b/note.md",
      relpath = "b/note.md",
      filename = "note.md",
      title = "Same",
      aliases = {},
      tags = { "work", "home" },
    }),
    note({
      path = "/w/nested.md",
      relpath = "nested.md",
      filename = "nested.md",
      title = "Nested",
      aliases = {},
      tags = { "parent/child" },
    }),
    note({
      path = "/w/lower.md",
      relpath = "lower.md",
      filename = "lower.md",
      title = "budget",
      aliases = {},
      tags = {},
    }),
  }
  same(rels(search.query_notes(notes, "budget")), {
    "exact.md",
    "lower.md",
    "prefix.md",
    "middle.md",
    "budget-notes.md",
    "dir/budget/other.md",
    "misc.md",
  }, "rank order for budget")
  same(reasons(search.query_notes(notes, "budget")), {
    "exact.md=title",
    "lower.md=title",
    "prefix.md=title",
    "middle.md=title",
    "budget-notes.md=filename",
    "dir/budget/other.md=path",
    "misc.md=tag",
  }, "match reasons")
  same(rels(search.query_notes(notes, "yearly")), { "exact.md" }, "alias absent from filename")
  local yearly = search.query_notes(notes, "yearly")[1]
  eq(yearly.reason, "alias", "alias reason")
  eq(yearly.text, "exact.md\tBudget\tyearly\t#work", "row is path, title, aliases, tags")
  local both = search.query_notes(notes, "#work #home")[1]
  eq(both.text, "b/note.md\tSame\t#work #home", "row shows every tag")
  local filename_only = search.query_notes({
    {
      path = "/w/plain.md",
      relpath = "plain.md",
      filename = "plain.md",
      title = "plain",
      title_source = "filename",
      aliases = {},
      tags = {},
    },
  }, "")[1]
  eq(filename_only.text, "plain.md", "filename fallback title is omitted")
  eq(#search.query_notes(notes, "budget"), 7, "one result per note")
  same(rels(search.query_notes(notes, "#work #home")), { "b/note.md" }, "tag filters are AND")
  same(rels(search.query_notes(notes, "#parent")), {}, "#parent does not match parent/child")
  same(rels(search.query_notes(notes, "#parent/child")), { "nested.md" }, "exact nested tag")
  same(rels(search.query_notes(notes, "#WORK")), { "a/note.md", "b/note.md", "exact.md" }, "tag filters ignore case")
  same(rels(search.query_notes(notes, "Budget")), { "exact.md", "prefix.md" }, "smartcase keeps Budget and drops lowercase budget")
  same(rels(search.query_notes(notes, "Same")), { "a/note.md", "b/note.md" }, "duplicate filenames stay separate")
  same(rels(search.query_notes(notes, "annual report")), {}, "every text token must match")
end)

add("choose opens the note in the window behind the picker", function()
  local dir = tmp()
  local path = write(dir, "open.md", "# Open\n")
  local stay = write(dir, "stay.md", "# Stay\n")
  vim.cmd.edit(vim.fn.fnameescape(stay))
  local target = vim.api.nvim_get_current_win()
  vim.cmd.split()
  local picker = vim.api.nvim_get_current_win()
  local previous = package.loaded["mini.pick"]
  package.loaded["mini.pick"] = {
    get_picker_state = function()
      return { windows = { target = target } }
    end,
  }
  require("mdw.pick").choose({ path = path })
  package.loaded["mini.pick"] = previous
  eq(vim.api.nvim_win_get_buf(target), vim.fn.bufnr(path), "target window shows the chosen note")
  eq(vim.api.nvim_get_current_win(), picker, "the picker window stays current")
  vim.cmd.close()
end)

add("workspace discovery and index", function()
  local mdw = require("mdw")
  local workspace = require("mdw.workspace")
  local index = require("mdw.index")

  local loose_parent = tmp()
  local loose = loose_parent .. "/sub"
  vim.fn.mkdir(loose, "p")
  local loose_file = write(loose, "loose.md", "# Loose\n")
  write(loose_parent, "outside.md", "# Outside\n")
  mdw.setup({})
  vim.cmd.edit(vim.fn.fnameescape(loose_file))
  eq(workspace.resolve(0), workspace.normalize(loose), "file outside git uses its directory")
  mdw.rebuild()
  same(rels(mdw.search("")), { "loose.md" }, "parent note stays outside the directory workspace")

  local repo = tmp()
  git_init(repo)
  local nested = write(repo, "notes/a.md", "# Inside\n")
  write(repo, "other.md", "# Other\n")
  write(repo, ".hidden/skip.md", "# Skip\n")
  write(repo, "node_modules/pkg/skip.md", "# Skip\n")
  write(repo, "keep.mdc", "# Mdc\n")
  write(repo, "keep.markdown", "# Markdown\n")
  write(repo, "keep.mdx", "# Mdx\n")
  write(repo, "keep.mkd", "# Mkd\n")
  write(repo, "skip.txt", "# Text\n")
  write(repo, "bad.md", "---\ntitle: \"nope\n")
  write(repo, "alias.md", "---\naliases:\n  - yearly plan\n---\n\nBody\n")
  mdw.setup({})
  vim.cmd.edit(vim.fn.fnameescape(nested))
  eq(workspace.resolve(0), workspace.normalize(repo), "git toplevel of the current file")
  local found = mdw.search("")
  local found_rels = rels(found)
  same(found_rels, {
    "alias.md",
    "keep.markdown",
    "keep.mdc",
    "keep.mdx",
    "keep.mkd",
    "notes/a.md",
    "other.md",
  }, "extensions are indexed and hidden, modules, text, and malformed files are not")
  truthy(#index.error_list(repo) == 1, "malformed file is reported")
  eq(index.error_list(repo)[1].path, "bad.md", "malformed path")
  same(rels(mdw.search("yearly")), { "alias.md" }, "alias search in the git workspace")

  local repo_b = tmp()
  git_init(repo_b)
  local other = write(repo_b, "b.md", "# Bee\n")
  vim.cmd.edit(vim.fn.fnameescape(other))
  eq(workspace.resolve(0), workspace.normalize(repo_b), "switching buffers switches workspace")
  same(rels(mdw.search("")), { "b.md" }, "search follows the current file workspace")

  local pinned_parent = tmp()
  local pinned = pinned_parent .. "/notes"
  vim.fn.mkdir(pinned, "p")
  write(pinned, "only.md", "# Only\n")
  write(pinned_parent, "nope.md", "# Nope\n")
  vim.cmd.cd(pinned_parent)
  mdw.setup({ workspace = { root = "notes" } })
  eq(workspace.resolve(0), workspace.normalize(pinned), "relative workspace.root is pinned")
  same(rels(mdw.search("")), { "only.md" }, "pinned root ignores the sibling file")
  vim.cmd.cd(saved_cwd)
end)

add("open buffers win over older saved copies", function()
  local mdw = require("mdw")
  local index = require("mdw.index")
  local dir = tmp()
  local path = write(dir, "live.md", "---\naliases:\n  - disk\n---\n")
  mdw.setup({ workspace = { root = dir } })
  mdw.rebuild()
  same(rels(mdw.search("disk")), { "live.md" }, "disk alias is visible")
  vim.cmd.edit(vim.fn.fnameescape(path))
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "---", "aliases:", "  - unsavedalias", "---", "" })
  vim.bo.modified = true
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = vim.api.nvim_get_current_buf() })
  same(rels(mdw.search("unsavedalias")), { "live.md" }, "buffer text is indexed")
  same(rels(mdw.search("disk")), {}, "stale disk alias is not indexed")
  write(dir, "live.md", "---\naliases:\n  - external\n---\n")
  mdw.rebuild()
  same(rels(mdw.search("unsavedalias")), { "live.md" }, "rebuild keeps the dirty buffer")
  vim.bo.modified = false
  write(dir, "live.md", "---\naliases:\n  - external\n---\n")
  vim.api.nvim_exec_autocmds("BufEnter", { buffer = vim.api.nvim_get_current_buf() })
  same(rels(mdw.search("external")), { "live.md" }, "external edit is visible after refresh")
  eq(#index.error_list(dir), 0, "live note has no error")
end)

add("commands, health, choose, and picker fallback", function()
  local dir = tmp()
  local path = write(dir, "my notes/plan.md", "# Plan\n\n#work\n")
  local mdw = require("mdw")
  mdw.setup({ workspace = { root = dir } })
  local health = require("mdw.health").collect()
  eq(health.version_ok, true, "neovim version is supported")
  eq(health.setup, true, "setup was called")
  eq(health.root, require("mdw.workspace").normalize(dir), "health reports the root")
  eq(health.notes, 1, "health counts notes")
  eq(health.enrich, false, "enrichment defaults off")
  truthy(pcall(require("mdw.health").check), "health check runs")

  local chosen = nil
  package.loaded["mini.pick"] = nil
  vim.ui.select = function(items, _, on_choice)
    chosen = items
    on_choice(nil)
  end
  vim.cmd("Mdw search #work")
  eq(chosen[1].relpath, "my notes/plan.md", "search command reaches vim.ui.select")
  require("mdw.pick").choose(chosen[1])
  eq(require("mdw.workspace").normalize(vim.api.nvim_buf_get_name(0)), require("mdw.workspace").normalize(path), "choose opens the note")

  local started = nil
  package.loaded["mini.pick"] = {
    start = function(opts)
      started = opts
      return nil
    end,
    builtin = { files = function() end },
    registry = { files = function() end },
    default_match = function(_, inds)
      return inds
    end,
  }
  vim.cmd("Mdw search plan")
  eq(started.source.name, "Mdw notes", "mini.pick source name")
  eq(started.source.items[1].reason, "title", "mini.pick item keeps the match reason")
  local inds = started.source.match(nil, nil, {})
  same(inds, { 1 }, "empty picker query keeps the current order")
  package.loaded["mini.pick"] = nil

  vim.cmd("Mdw index")
  vim.cmd("Mdw")
  local unknown = pcall(vim.cmd, "Mdw nope")
  truthy(not unknown, "unknown subcommand fails")
end)

add("mini.pick enrichment wraps once and can be removed", function()
  local dir = tmp()
  write(dir, "x.md", "---\naliases:\n  - yearly\n---\n# Secret\n")
  write(dir, "readme.txt", "hello\n")
  local calls = 0
  local captured = nil
  local original_files
  original_files = function(_, opts)
    calls = calls + 1
    captured = opts
    return "original"
  end
  local original_registry = function()
    return "registry"
  end
  package.loaded["mini.pick"] = {
    builtin = { files = original_files },
    registry = { files = original_registry },
    default_match = function(stritems, inds, query)
      local prompt = table.concat(query)
      local out = {}
      for _, index in ipairs(inds) do
        if prompt == "" or stritems[index]:find(prompt, 1, true) then
          out[#out + 1] = index
        end
      end
      return out
    end,
  }
  local mdw = require("mdw")
  vim.cmd.cd(dir)
  mdw.setup({ workspace = { root = dir }, search = { enrich_files = true } })
  local wrapped = package.loaded["mini.pick"].builtin.files
  mdw.setup({ workspace = { root = dir }, search = { enrich_files = true } })
  eq(package.loaded["mini.pick"].builtin.files, wrapped, "second setup does not wrap again")
  eq(wrapped(), "original", "wrapped files calls the original picker")
  eq(calls, 1, "original files picker runs once")
  truthy(type(captured.source.match) == "function", "enrichment installs a match function")
  local stritems = { "x.md", "readme.txt" }
  local matched = captured.source.match(stritems, { 1, 2 }, { "y", "e", "a", "r", "l", "y" })
  same(matched, { 1 }, "alias match is added to file search")
  eq(package.loaded["mini.pick"].registry.files(), "original", "registry.files uses the enriched builtin")

  vim.cmd.cd("/tmp")
  package.loaded["mini.pick"].builtin.files()
  eq(captured, nil, "file search outside the workspace stays ordinary")

  mdw.setup({ workspace = { root = dir }, search = { enrich_files = false } })
  eq(package.loaded["mini.pick"].builtin.files, original_files, "disabling enrichment restores files")
  eq(package.loaded["mini.pick"].registry.files, original_registry, "disabling enrichment restores the registry")
  vim.cmd.cd(saved_cwd)
  package.loaded["mini.pick"] = nil
end)

local function finish()
  vim.cmd.cd(saved_cwd)
  for _, dir in ipairs(temps) do
    vim.fn.delete(dir, "rf")
  end
end

for _, case in ipairs(tests) do
  local before = failures
  local ok, err = pcall(case.fn)
  if not ok then
    fail(case.name .. " crashed: " .. tostring(err))
  elseif failures == before then
    io.stderr:write("ok " .. case.name .. "\n")
  end
end

finish()
io.stderr:flush()

if failures > 0 then
  io.stderr:write(string.format("%d failed, %d checks\n", failures, checks))
  vim.cmd("cquit 1")
else
  io.stderr:write(string.format("%d checks passed\n", checks))
  vim.cmd("cquit 0")
end
