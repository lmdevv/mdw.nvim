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

add("links resolve outside code and ignore labels", function()
  local scan = require("mdw.scan")
  local note = scan.parse([=[
# Top ^alpha

See [[Budget|Label]] and [[Note#Section]] and [[#Top]].
[rel](../exact.md#Forecast)
`[[hidden]]`

```md
[[fenced]]
```

https://example.com/a
]=], "links.md", "links")
  eq(note.headings[1].text, "Top", "heading text drops the block id")
  eq(note.headings[1].level, 1, "heading level")
  eq(note.blocks[1].id, "alpha", "block id")
  eq(note.blocks[1].line, note.headings[1].line, "block shares the heading line")
  local targets = {}
  for _, link in ipairs(note.links) do
    targets[#targets + 1] = link.syntax .. ":" .. link.target .. ":" .. tostring(link.heading) .. ":" .. tostring(link.block)
  end
  same(targets, {
    "wikilink:Budget:nil:nil",
    "wikilink:Note:Section:nil",
    "wikilink::Top:nil",
    "markdown:../exact.md:Forecast:nil",
    "url:https://example.com/a:nil:nil",
  }, "code and fences are not links")
  eq(note.links[1].label, "Label", "wikilink label is kept on the occurrence")

  local dir = tmp()
  write(dir, "exact.md", "---\naliases:\n  - yearly plan\n---\n# Forecast\n")
  write(dir, "a/note.md", "# A\n")
  write(dir, "b/note.md", "# B\n")
  write(dir, "label.md", "See [[Missing|UniqueLabel]] and [[yearly plan]] and [[note]] and [[exact#Gone]] and [[#Missing]].\n")
  write(dir, "UniqueLabel.md", "# Label file\n")
  local mdw = require("mdw")
  mdw.setup({ workspace = { root = dir } })
  mdw.rebuild()
  local resolve = require("mdw.resolve")
  local label = require("mdw.index").note(dir, "label.md")
  local function linked(target)
    for _, link in ipairs(label.links) do
      if link.target == target or (target == "" and link.heading == "Missing") then
        return resolve.resolve(dir, "label.md", link)
      end
    end
    error("missing link " .. target)
  end
  local yearly = linked("yearly plan")
  eq(yearly.kind, "resolved", "alias resolves")
  eq(yearly.matches[1].relpath, "exact.md", "alias finds the note")
  local ambiguous = linked("note")
  eq(ambiguous.kind, "ambiguous", "duplicate stems are ambiguous")
  eq(#ambiguous.matches, 2, "both note.md files are candidates")
  local missing = linked("Missing")
  eq(missing.kind, "missing-note", "unknown wikilink is missing")
  eq(missing.proposed, "Missing.md", "proposed path uses the target, not the label")
  local gone = linked("exact")
  eq(gone.kind, "missing-location", "missing heading is not a missing note")
  eq(gone.detail, "heading", "missing location names the heading")
  local same_file = linked("")
  eq(same_file.kind, "missing-location", "same-file heading can be missing")
end)

add("follow opens a unique note and creates only after confirmation", function()
  local dir = tmp()
  local exact = write(dir, "exact.md", "# Exact\n")
  local links = write(dir, "links.md", "See [[exact]] and [[Brand New]].\n")
  local mdw = require("mdw")
  mdw.setup({ workspace = { root = dir } })
  mdw.rebuild()
  vim.cmd.edit(vim.fn.fnameescape(links))
  local note = require("mdw.index").note(dir, "links.md")
  local exact_link, new_link
  for _, link in ipairs(note.links) do
    if link.target == "exact" then
      exact_link = link
    elseif link.target == "Brand New" then
      new_link = link
    end
  end
  vim.api.nvim_win_set_cursor(0, { exact_link.line, exact_link.start_col - 1 })
  truthy(require("mdw.nav").follow(), "follow handles the link")
  eq(require("mdw.workspace").normalize(vim.api.nvim_buf_get_name(0)), require("mdw.workspace").normalize(exact), "unique link opens the note")

  vim.cmd.edit(vim.fn.fnameescape(links))
  vim.api.nvim_win_set_cursor(0, { new_link.line, new_link.start_col - 1 })
  local saved = vim.fn.confirm
  vim.fn.confirm = function()
    return 2
  end
  truthy(require("mdw.nav").follow(), "declined create still handles the link")
  eq(vim.uv.fs_stat(dir .. "/Brand New.md"), nil, "cancel creates no file")
  vim.fn.confirm = function()
    return 1
  end
  require("mdw.nav").follow()
  truthy(vim.uv.fs_stat(dir .. "/Brand New.md") ~= nil, "confirmed create writes the note")
  eq(require("mdw.workspace").normalize(vim.api.nvim_buf_get_name(0)), require("mdw.workspace").normalize(dir .. "/Brand New.md"), "created note opens")
  vim.fn.confirm = saved
end)

add("backlinks, outgoing links, sidebar, and quickfix share one index", function()
  local dir = tmp()
  local source = write(dir, "source.md", "# Source\n\nSee [[dest]] and [[missing one]].\n")
  write(dir, "dest.md", "# Dest\n\nBack to [[source]].\n")
  local mdw = require("mdw")
  mdw.setup({ workspace = { root = dir } })
  mdw.rebuild()
  local relations = require("mdw.relations")
  local back = relations.backlinks(dir, "dest.md")
  eq(back[1].relpath, "source.md", "backlink names the source")
  eq(#back, 1, "one backlink")
  local outgoing = relations.outgoing(dir, require("mdw.index").note(dir, "source.md"))
  eq(#outgoing, 2, "outgoing keeps the unresolved link")
  truthy(outgoing[2].text:find("missing", 1, true) ~= nil, "unresolved outgoing link stays visible")
  local qf = relations.quickfix(dir, "backlinks", "dest.md")
  eq(#qf, 1, "quickfix uses the backlink result")
  eq(vim.fn.getqflist({ title = 0 }).title, "mdw backlinks", "quickfix title")

  vim.cmd.edit(vim.fn.fnameescape(source))
  local sidebar = require("mdw.sidebar")
  sidebar.open()
  eq(vim.bo.filetype, "mdw-sidebar", "sidebar filetype")
  eq(sidebar.source_path(), require("mdw.workspace").normalize(source), "sidebar keeps the source note")
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  truthy(table.concat(lines, "\n"):find("Source", 1, true) ~= nil, "outline shows the heading")
  eq(require("mdw.index").note(dir, "mdw://sidebar"), nil, "sidebar is not a note")
  sidebar.close()
end)

add("rename updates references and refuses dirty buffers", function()
  local dir = tmp()
  write(dir, "exact.md", "# Exact\n\nSelf [[exact|Keep]].\n")
  write(dir, "other.md", "Go [[exact#Exact]] and [Plan](exact.md).\n")
  write(dir, "taken.md", "# Taken\n")
  local mdw = require("mdw")
  mdw.setup({ workspace = { root = dir } })
  mdw.rebuild()
  local refactor = require("mdw.refactor")
  local blocked = refactor.plan(dir, "exact.md", "taken.md")
  eq(blocked, nil, "existing destination is refused")
  vim.cmd.edit(vim.fn.fnameescape(dir .. "/other.md"))
  vim.bo.modified = true
  local dirty = refactor.plan(dir, "exact.md", "moved.md")
  local applied, err = refactor.apply(dirty)
  eq(applied, nil, "dirty buffer blocks the rename")
  truthy(err:find("unsaved", 1, true) ~= nil, "dirty error names unsaved changes")
  truthy(vim.uv.fs_stat(dir .. "/exact.md") ~= nil, "source remains")
  vim.bo.modified = false
  local plan = refactor.plan(dir, "exact.md", "nested/moved.md")
  local ok = refactor.apply(plan)
  eq(ok, true, "rename applies")
  truthy(vim.uv.fs_stat(dir .. "/nested/moved.md") ~= nil, "note moved")
  eq(vim.uv.fs_stat(dir .. "/exact.md"), nil, "old path is gone")
  local other = assert(io.open(dir .. "/other.md", "rb")):read("*a")
  truthy(other:find("[[nested/moved#Exact]]", 1, true) ~= nil, "wikilink keeps the heading")
  truthy(other:find("[Plan](nested/moved.md)", 1, true) ~= nil, "markdown link keeps the label")
  local moved = assert(io.open(dir .. "/nested/moved.md", "rb")):read("*a")
  truthy(moved:find("[[nested/moved|Keep]]", 1, true) ~= nil, "self link keeps the label")
end)

add("frontmatter edits preserve unrelated lines", function()
  local meta = require("mdw.meta")
  local text = "---\n# comment\nkept: 1\ntags:\n  - a\n---\n\n# Hi\n"
  local updated = meta.apply(text, "tags", { "work", "home" })
  truthy(updated:find("# comment", 1, true) ~= nil, "comment stays")
  truthy(updated:find("kept: 1", 1, true) ~= nil, "unknown key stays")
  truthy(updated:find("  %- work", 1, false) ~= nil or updated:find("  - work", 1, true) ~= nil, "new tag is written")
  truthy(updated:find("  - a\n", 1, true) == nil, "old tag is replaced")
  truthy(updated:find("# Hi", 1, true) ~= nil, "body stays")
  local bad, err = meta.apply("---\ntitle: |\n  hello\n---\n", "title", "Next")
  eq(bad, nil, "multiline value is not rewritten")
  truthy(err:find("unsupported", 1, true) ~= nil, "unsupported syntax is reported")
  local added = meta.apply("# Plain\n", "title", "Plain")
  truthy(added:find("title: Plain", 1, true) ~= nil, "missing frontmatter is added")
  truthy(added:find("# Plain", 1, true) ~= nil, "body remains under new frontmatter")
end)

add("create, daily notes, and obsidian cli", function()
  local dir = tmp()
  local day = "KEEP {{title}} {{place}}\n"
  local mdw = require("mdw")
  mdw.setup({
    workspace = { root = dir },
    create = {
      templates = { day = day },
      backend = "local",
    },
    daily = { folder = "daily", template = "day" },
  })
  local saved = vim.fn.confirm
  vim.fn.confirm = function()
    return 2
  end
  local cancelled = require("mdw.create").create({ root = dir, relpath = "skip.md", template = "day" })
  eq(cancelled, nil, "declined create returns nothing")
  eq(vim.uv.fs_stat(dir .. "/skip.md"), nil, "declined create writes nothing")
  vim.fn.confirm = function()
    return 1
  end
  local created = require("mdw.create").create({ root = dir, relpath = "made note.md", template = "day", title = "Made" })
  truthy(created ~= nil, "confirmed create writes")
  local made = assert(io.open(created, "rb")):read("*a")
  truthy(made:find("KEEP Made", 1, true) ~= nil, "template title is filled")
  truthy(made:find("{{place}}", 1, true) ~= nil, "unknown template field is preserved")
  local again = require("mdw.create").create({ root = dir, relpath = "made note.md", confirm = false })
  eq(again, nil, "existing note is not overwritten")

  write(dir, "daily/2020-01-02.md", "OLD\n")
  local daily = require("mdw.daily")
  local reused = daily.open("2020-01-02", { root = dir, confirm = false })
  local old = assert(io.open(reused, "rb")):read("*a")
  eq(old, "OLD\n", "existing daily note is not rewritten")
  local fresh = daily.open("2020-01-03", { root = dir, confirm = false })
  local body = assert(io.open(fresh, "rb")):read("*a")
  truthy(body:find("KEEP 2020-01-03", 1, true) ~= nil, "new daily note uses the template")
  local previous = daily.open("prev", { root = dir, confirm = false })
  eq(vim.fs.basename(previous), "2020-01-02.md", "prev opens the earlier daily note")
  eq(vim.uv.fs_stat(dir .. "/daily/2020-01-01.md"), nil, "prev does not create a missing day")
  mdw.setup({
    workspace = { root = dir },
    daily = { format = "dddd" },
  })
  local spec = daily.spec(dir)
  eq(spec, nil, "unsupported daily format is reported")

  local script = dir .. "/obsidian"
  local log = dir .. "/obsidian.log"
  local handle = assert(io.open(script, "wb"))
  handle:write(string.format([=[
#!/bin/sh
printf '%%s\n' "$@" >> %q
vault=""
path=""
for arg in "$@"; do
  case "$arg" in
    vault=*) vault=${arg#vault=} ;;
    path=*) path=${arg#path=} ;;
  esac
done
if [ -n "$vault" ] && [ -n "$path" ]; then
  mkdir -p "$(dirname "$vault/$path")"
  printf 'from cli\n' > "$vault/$path"
fi
]=], log))
  handle:close()
  vim.uv.fs_chmod(script, 493)
  mdw.setup({
    workspace = { root = dir },
    create = { backend = "obsidian" },
    obsidian = { enabled = true, command = script },
  })
  local cli = require("mdw.create").create({
    root = dir,
    relpath = "from cli.md",
    template = "Travel",
    confirm = false,
    backend = "obsidian",
  })
  truthy(cli ~= nil, "obsidian backend creates the file")
  local recorded = assert(io.open(log, "rb")):read("*a")
  truthy(recorded:find("vault=" .. dir, 1, true) ~= nil, "vault is an argument")
  truthy(recorded:find("path=from cli.md", 1, true) ~= nil, "path is an argument")
  truthy(recorded:find("template=Travel", 1, true) ~= nil, "template name is an argument")
  truthy(recorded:find("create\n", 1, true) ~= nil, "create is a separate argument")
  local cli_body = assert(io.open(cli, "rb")):read("*a")
  eq(cli_body, "from cli\n", "local template body is not written for the cli backend")
  vim.fn.confirm = saved
end)

add("tasks, images, and formatting", function()
  local dir = tmp()
  local note = write(dir, "note.md", "task\n")
  local mdw = require("mdw")
  local script = dir .. "/rumdl"
  local handle = assert(io.open(script, "wb"))
  handle:write([[
#!/bin/sh
mode="${MDW_RUMDL_MODE:-format}"
if [ "$mode" = "fail" ]; then
  echo 'rumdl failed' >&2
  exit 1
fi
if [ "$mode" = "check" ]; then
  printf '%s\n' '[{"line":2,"column":3,"rule":"MD018","message":"space","severity":"warning"}]'
  exit 1
fi
printf '%s\n' '# Formatted'
]])
  handle:close()
  vim.uv.fs_chmod(script, 493)
  local clip = dir .. "/clip"
  handle = assert(io.open(clip, "wb"))
  handle:write("#!/bin/sh\nprintf 'png-bytes'\n")
  handle:close()
  vim.uv.fs_chmod(clip, 493)
  local clip_fail = dir .. "/clip-fail"
  handle = assert(io.open(clip_fail, "wb"))
  handle:write("#!/bin/sh\necho 'no image' >&2\nexit 1\n")
  handle:close()
  vim.uv.fs_chmod(clip_fail, 493)

  mdw.setup({
    workspace = { root = dir },
    format = { command = script, format_on_save = false },
    edit = { clipboard = { clip } },
  })
  vim.cmd.edit(vim.fn.fnameescape(note))
  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "  task",
    "  - task",
    "  - [ ] task",
    "  - [x] task",
    "```",
    "- [ ] hidden",
    "```",
  })
  local edit = require("mdw.edit")
  edit.cycle_lines(0, 1, 4)
  local cycled = vim.api.nvim_buf_get_lines(0, 0, 4, false)
  same(cycled, { "  - task", "  - [ ] task", "  - [x] task", "  task" }, "task cycle keeps the indent")
  edit.cycle_lines(0, 4, 1)
  cycled = vim.api.nvim_buf_get_lines(0, 0, 4, false)
  same(cycled, { "  - [ ] task", "  - [x] task", "  task", "  - task" }, "a reversed range cycles every selected line")
  edit.cycle_lines(0, 6, 6)
  eq(vim.api.nvim_buf_get_lines(0, 5, 6, false)[1], "- [ ] hidden", "fenced tasks stay unchanged")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "task" })
  vim.api.nvim_win_set_cursor(0, { 1, 3 })
  edit.cycle_insert()
  eq(vim.api.nvim_get_current_line(), "- task", "insert cycle adds a bullet")
  eq(vim.api.nvim_win_get_cursor(0)[2], 5, "insert cycle keeps the cursor on the text")

  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
  local pasted = edit.paste_image()
  truthy(pasted ~= nil, "clipboard image is saved")
  eq(vim.api.nvim_get_current_line(), "![](assets/image.png)", "image link is inserted")
  local first = assert(io.open(dir .. "/assets/image.png", "rb")):read("*a")
  eq(first, "png-bytes", "image bytes are stored")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
  edit.paste_image()
  truthy(vim.uv.fs_stat(dir .. "/assets/image-2.png") ~= nil, "a second paste uses a new name")
  eq(assert(io.open(dir .. "/assets/image.png", "rb")):read("*a"), "png-bytes", "the first image is kept")
  mdw.setup({
    workspace = { root = dir },
    format = { command = script },
    edit = { clipboard = { clip_fail } },
  })
  vim.bo.modified = false
  vim.cmd.edit(vim.fn.fnameescape(note))
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "keep" })
  local failed = edit.paste_image()
  eq(failed, nil, "a clipboard failure pastes nothing")
  eq(vim.api.nvim_get_current_line(), "keep", "a clipboard failure leaves the line")

  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "#Title" })
  local formatted = require("mdw.format").format()
  eq(formatted, true, "format succeeds")
  eq(vim.api.nvim_get_current_line(), "# Formatted", "format replaces the buffer")
  vim.env.MDW_RUMDL_MODE = "fail"
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "#Title" })
  local broken = require("mdw.format").format()
  eq(broken, nil, "format failure is reported")
  eq(vim.api.nvim_get_current_line(), "#Title", "format failure leaves the buffer")
  vim.env.MDW_RUMDL_MODE = nil
  local formatter = require("mdw.format")
  local saved_run = formatter.run
  formatter.run = function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "edited during format" })
    return { code = 0, stdout = "# Formatted\n", stderr = "" }
  end
  local stale = formatter.format()
  eq(stale, nil, "a newer edit is not overwritten")
  eq(vim.api.nvim_get_current_line(), "edited during format", "the newer text stays")
  formatter.run = function()
    return {
      code = 1,
      stdout = '[{"line":2,"column":3,"rule":"MD018","message":"space","severity":"warning"}]',
      stderr = "",
    }
  end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "# Title", "body" })
  eq(formatter.lint(), true, "lint accepts rumdl json")
  local diagnostics = vim.diagnostic.get(0, { namespace = vim.api.nvim_create_namespace("mdw-rumdl") })
  eq(diagnostics[1].lnum, 1, "diagnostic line")
  eq(diagnostics[1].col, 2, "diagnostic column")
  formatter.run = saved_run
  mdw.setup({
    workspace = { root = dir },
    format = { command = script, lint = false },
  })
  vim.bo.modified = false
  vim.cmd.edit(vim.fn.fnameescape(note))
  eq(require("mdw.format").lint(), true, "disabled lint still returns")
  eq(#vim.diagnostic.get(0, { namespace = vim.api.nvim_create_namespace("mdw-rumdl") }), 0, "disabled lint clears diagnostics")

  mdw.setup({ workspace = { root = dir }, lsp = { rename = true } })
  local renamed = require("mdw.refactor").rename(dir, "note.md", "other.md")
  eq(renamed, nil, "lsp-owned rename does not run")
  truthy(vim.uv.fs_stat(note) ~= nil, "lsp-owned rename leaves the file")

  mdw.setup({ workspace = { root = dir }, render = { enabled = true } })
  local health = require("mdw.health").collect()
  eq(health.render, true, "render option is reported")
  eq(health.render_ready, false, "missing render-markdown is not marked ready")
  truthy(pcall(require("mdw.health").check), "health still runs without render-markdown")
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
