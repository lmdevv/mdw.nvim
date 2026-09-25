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
  truthy(vim.api.nvim_get_commands({ builtin = false }).Mdw ~= nil, "command is registered")
  truthy(mdw.typed_mdw("mdw"), "plain :mdw is recognized")
  truthy(mdw.typed_mdw("1,2mdw"), "a line range is recognized")
  truthy(mdw.typed_mdw("'<,'>mdw"), "a visual range is recognized")
  eq(mdw.typed_mdw("echo mdw"), false, "mdw inside another command is left alone")
  local saved_notify = vim.notify
  local shown = {}
  vim.notify = function(msg)
    shown[#shown + 1] = msg
  end
  local typed = pcall(function()
    vim.fn.feedkeys(":mdw\r", "tx")
  end)
  vim.notify = saved_notify
  truthy(typed, ":mdw runs")
  truthy(table.concat(shown, "\n"):find(":mdw health", 1, true) ~= nil, ":mdw prints the lowercase usage")
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
  eq(started.source.name, "mdw notes", "mini.pick source name")
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
    default_match = function(stritems, inds, query, opts)
      if not (opts and opts.sync) then
        return nil -- mini.pick matches asynchronously while a picker is active.
      end
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
  same(captured.source.match(stritems, { 1, 2 }, {}), { 1, 2 }, "empty query keeps notes and other files")
  same(
    captured.source.match(stritems, { 1, 2 }, { "r", "e", "a", "d", "m", "e" }),
    { 2 },
    "ordinary file name matches remain visible"
  )
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

add("snacks and telescope file search use note metadata", function()
  local dir = tmp()
  write(dir, "x.md", "---\naliases:\n  - yearly\ntags: [parent/child]\n---\n# Secret\n")
  write(dir, "readme.txt", "hello\n")
  local snacks_seen = nil
  local snacks_pick = function(source, opts)
    snacks_seen = opts
    return source
  end
  package.loaded["snacks"] = { picker = { pick = snacks_pick } }
  local telescope_seen = nil
  local find_files = function(opts)
    telescope_seen = opts
  end
  package.loaded["telescope.builtin"] = { find_files = find_files, fd = find_files }
  package.loaded["telescope.config"] = {
    values = {
      file_sorter = function()
        return {
          scoring_function = function(_, prompt, line)
            if prompt == "" or (line and tostring(line):find(prompt, 1, true)) then
              return 5
            end
            return -1
          end,
        }
      end,
    },
  }
  package.loaded["mini.pick"] = nil
  local mdw = require("mdw")
  vim.cmd.cd(dir)
  mdw.setup({ workspace = { root = dir }, search = { enrich_files = true } })
  require("snacks").picker.pick("files", {})
  local yearly = snacks_seen.finder(nil, { filter = { search = "yearly", pattern = "" } })
  eq(#yearly, 1, "snacks file search finds an alias")
  eq(yearly[1].text, "x.md", "snacks alias match is the note file")
  local parent = snacks_seen.finder(nil, { filter = { search = "#parent", pattern = "" } })
  eq(#parent, 0, "snacks #parent does not match parent/child")
  local child = snacks_seen.finder(nil, { filter = { search = "#parent/child", pattern = "" } })
  eq(child[1].text, "x.md", "snacks matches the whole tag")
  snacks_seen = nil
  require("snacks").picker.pick("files", { cwd = "/tmp" })
  eq(snacks_seen.finder, nil, "snacks file search outside the workspace stays ordinary")

  require("telescope.builtin").find_files({})
  local score = telescope_seen.sorter.scoring_function({}, "yearly", "x.md", { path = dir .. "/x.md" })
  truthy(score < 0, "telescope keeps an alias match")
  eq(
    telescope_seen.sorter.scoring_function({}, "#parent", "x.md", { path = dir .. "/x.md" }),
    -1,
    "telescope #parent does not match parent/child"
  )
  telescope_seen = nil
  require("telescope.builtin").find_files({ cwd = "/tmp" })
  eq(telescope_seen.sorter, nil, "telescope file search outside the workspace stays ordinary")

  mdw.setup({ workspace = { root = dir }, search = { enrich_files = false } })
  eq(require("snacks").picker.pick, snacks_pick, "disabling enrichment restores snacks")
  eq(require("telescope.builtin").find_files, find_files, "disabling enrichment restores telescope")
  package.loaded["snacks"] = nil
  package.loaded["telescope.builtin"] = nil
  package.loaded["telescope.config"] = nil
  package.loaded["mini.pick"] = nil
  vim.cmd.cd(saved_cwd)
end)

add("snacks and telescope show ranked note search", function()
  local dir = tmp()
  write(dir, "plan.md", "---\ntitle: Budget\ntags: work\n---\n# Budget\n")
  write(dir, "other.md", "# Other\n")
  local mdw = require("mdw")
  local ui = require("mdw.ui")
  local pick = require("mdw.pick")
  vim.cmd.cd(dir)
  local previous_select = vim.ui.select
  local loaded = {}
  for _, name in ipairs({
    "snacks",
    "telescope",
    "telescope.pickers",
    "telescope.finders",
    "telescope.actions",
    "telescope.actions.state",
    "telescope.sorters",
    "telescope.config",
    "mini.pick",
  }) do
    loaded[name] = package.loaded[name]
  end

  local snacks_opts = nil
  package.loaded["mini.pick"] = nil
  package.loaded["telescope"] = nil
  package.loaded["snacks"] = {
    picker = {
      pick = function(opts)
        snacks_opts = opts
      end,
    },
  }
  mdw.setup({ workspace = { root = dir }, search = { picker = "auto" } })
  eq(pick.backend(), "snacks", "auto uses snacks when mini.pick is absent")
  vim.cmd("Mdw search")
  eq(snacks_opts.title, "mdw notes", "snacks picker title")
  eq(snacks_opts.live, true, "note search is a live snacks finder")
  local empty = snacks_opts.finder(nil, { filter = { search = "" } })
  eq(#empty, 2, "an empty snacks query lists every note")
  local budget = snacks_opts.finder(nil, { filter = { search = "budget" } })
  eq(#budget, 1, "snacks query keeps mdw ranking")
  eq(budget[1].mdw.relpath, "plan.md", "snacks result is the matching note")
  local closed = false
  snacks_opts.confirm({
    close = function()
      closed = true
    end,
  }, budget[1])
  eq(closed, true, "snacks confirm closes the picker")
  eq(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t"), "plan.md", "snacks confirm opens the note")

  package.loaded["mini.pick"] = {
    start = function()
      error("mini.pick should stay closed when snacks is selected")
    end,
  }
  snacks_opts = nil
  mdw.setup({ workspace = { root = dir }, search = { picker = "snacks" } })
  vim.cmd("Mdw search")
  truthy(snacks_opts ~= nil, "explicit snacks wins over mini.pick")
  snacks_opts = nil
  ui.choose("mdw links", {
    { text = "first link", choose = function() end },
  })
  eq(snacks_opts.live, nil, "the link chooser is a static snacks list")
  eq(snacks_opts.items[1].text, "first link", "the link chooser shows the candidate")

  local spec = nil
  package.loaded["telescope"] = {}
  package.loaded["telescope.pickers"] = {
    new = function(_, opts)
      spec = opts
      return {
        find = function()
          opts.attach_mappings(0)
        end,
      }
    end,
  }
  package.loaded["telescope.finders"] = {
    new_dynamic = function(opts)
      return opts
    end,
    new_table = function(opts)
      return opts
    end,
  }
  package.loaded["telescope.actions"] = {
    select_default = {
      replace = function(_, fn)
        spec.select = fn
      end,
    },
    close = function() end,
  }
  package.loaded["telescope.actions.state"] = {
    get_selected_entry = function()
      return spec.finder.fn("other")[1] and { value = spec.finder.fn("other")[1] } or nil
    end,
  }
  package.loaded["telescope.sorters"] = {
    Sorter = {
      new = function(_, opts)
        return opts
      end,
    },
  }
  package.loaded["telescope.config"] = {
    values = {
      generic_sorter = function()
        return { name = "generic" }
      end,
    },
  }
  mdw.setup({ workspace = { root = dir }, search = { picker = "telescope" } })
  vim.cmd("Mdw search")
  eq(spec.prompt_title, "mdw notes", "telescope picker title")
  eq(#spec.finder.fn(""), 2, "an empty telescope query lists every note")
  eq(spec.finder.fn("budget")[1].relpath, "plan.md", "telescope query keeps mdw ranking")
  eq(spec.sorter.scoring_function(), 1, "telescope keeps mdw order")
  spec.select()
  eq(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t"), "other.md", "telescope confirm opens the note")

  local selected = nil
  vim.ui.select = function(items, _, on_choice)
    selected = items
    on_choice(nil)
  end
  mdw.setup({ workspace = { root = dir }, search = { picker = "select" } })
  vim.cmd("Mdw search")
  eq(#selected, 2, "select shows the note list even when other pickers exist")
  eq(pcall(mdw.setup, { search = { picker = "fzf" } }), false, "an unknown picker name is rejected")

  vim.ui.select = previous_select
  for name, value in pairs(loaded) do
    package.loaded[name] = value
  end
  vim.cmd.cd(saved_cwd)
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

add("sidebar all view stacks outline, backlinks, and outgoing links", function()
  local dir = tmp()
  local source = write(dir, "source.md", "# Source\n\nSee [[dest]].\n")
  local dest = write(dir, "dest.md", "# Dest\n\nBack to [[source]].\n")
  local mdw = require("mdw")
  mdw.setup({ workspace = { root = dir } })
  mdw.rebuild()
  vim.cmd.edit(vim.fn.fnameescape(source))
  local sidebar = require("mdw.sidebar")
  sidebar.open()

  local function sidebar_windows()
    local panes = {}
    local legend = nil
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "mdw-sidebar" then
        local pane = { win = win, buf = buf, pos = vim.api.nvim_win_get_position(win) }
        if vim.b[buf].mdw_legend then
          legend = pane
        else
          panes[#panes + 1] = pane
        end
      end
    end
    table.sort(panes, function(a, b)
      return a.pos[1] < b.pos[1]
    end)
    return panes, legend
  end

  local panes, legend = sidebar_windows()
  eq(#panes, 3, "sidebar opens with all three views")
  truthy(legend, "sidebar has a key legend")
  same(vim.api.nvim_buf_get_lines(legend.buf, 0, -1, false), {
    "a All  o Outline  b Backlinks",
    "l Links  Enter Open  q Close",
  }, "legend shows the sidebar keys")
  eq(vim.api.nvim_win_get_height(legend.win), 2, "legend stays compact")
  eq(vim.wo[legend.win].statusline, " ", "legend hides its internal buffer name")
  truthy(legend.pos[1] > panes[3].pos[1], "legend is below the three views")
  for index, view in ipairs({ "Outline", "Backlinks", "Links" }) do
    local pane = panes[index]
    eq(pane.pos[2], panes[1].pos[2], "all views share the sidebar column")
    if index > 1 then
      truthy(pane.pos[1] > panes[index - 1].pos[1], "all views are stacked vertically")
    end
    local lines = vim.api.nvim_buf_get_lines(pane.buf, 0, -1, false)
    eq(lines[1], view, "pane title omits the file name")
    eq(vim.wo[pane.win].statusline, " ", "pane hides its internal buffer name")
    truthy(vim.b[pane.buf].mdw_items[3] ~= nil, view .. " pane has a jump target")
  end

  vim.api.nvim_set_current_win(panes[3].win)
  vim.api.nvim_win_set_cursor(panes[3].win, { 3, 0 })
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "xt", false)
  eq(vim.api.nvim_buf_get_name(0), dest, "Enter in outgoing opens the linked note")
  for _, pane in ipairs(panes) do
    eq(vim.b[pane.buf].mdw_source, dest, "all panes follow the current note")
  end
  vim.cmd.edit(vim.fn.fnameescape(source))

  vim.api.nvim_set_current_win(panes[2].win)
  vim.cmd("normal o")
  local single, single_legend = sidebar_windows()
  eq(#single, 1, "o returns to the single outline view")
  truthy(single_legend, "legend remains in the single view")
  eq(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1], "Outline", "outline is shown")
  vim.cmd("normal a")
  eq(#sidebar_windows(), 3, "a restores all three views")
  vim.cmd("normal b")
  eq(#sidebar_windows(), 1, "b shows only backlinks")
  vim.cmd("normal q")
  eq(sidebar.is_open(), false, "q closes the sidebar")
  sidebar.open()
  eq(#sidebar_windows(), 3, "reopening starts in the all view")
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

add("daily search and obsidian templates", function()
  local dir = tmp()
  local mdw = require("mdw")
  local create = require("mdw.create")
  local daily = require("mdw.daily")
  local path, template, backend = create.parse_args('made note.md template="Trip plan" backend=obsidian')
  eq(path, "made note.md", "path keeps spaces")
  eq(template, "Trip plan", "quoted template is an argument")
  eq(backend, "obsidian", "backend is an argument")
  local leading, leading_template = create.parse_args("template=Trip made note.md")
  eq(leading, "made note.md", "a leading template leaves the path")
  eq(leading_template, "Trip", "a leading template is captured")

  local stamp = os.time({ year = 2020, month = 1, day = 2, hour = 15, min = 4, sec = 5 })
  local rendered, warnings = create.render("{{date:YYYY-MM-DD}} {{time:HH:mm}} {{date:dddd}} {{place}}", {
    title = "T",
    _stamp = stamp,
  })
  eq(rendered, "2020-01-02 15:04 {{date:dddd}} {{place}}", "known date tokens are filled")
  eq(#warnings, 2, "unknown fields are reported")

  write(dir, ".obsidian/daily-notes.json", '{ "folder": "Journal", "format": "YYYY-MM-DD", "template": "Trip" }\n')
  write(dir, ".obsidian/templates.json", '{ "folder": "Templates" }\n')
  write(dir, "Templates/Trip.md", "Hello {{title}} {{date:YYYY-MM-DD}}\n")
  write(dir, "Journal/2020-01-02.md", "---\ntitle: Budget\n---\n")
  write(dir, "Journal/2020-01-03.md", "# Other\n")
  write(dir, "Journal/scratch.md", "# Budget\n")
  write(dir, "Journal/nested/2020-01-05.md", "# Budget\n")
  write(dir, "2020-01-04.md", "# Budget\n")
  mdw.setup({ workspace = { root = dir } })
  eq(require("mdw.config").get().create.backend, "local", "a vault does not switch the backend")
  eq(require("mdw.config").get().obsidian.import_daily, true, "daily placement is read by default")
  eq(daily.spec(dir).folder, "Journal", "daily folder comes from the vault")
  local shown
  local pick = require("mdw.pick")
  local saved_show = pick.show
  pick.show = function(title, items)
    shown = { title = title, items = items }
  end
  local results, search_err = daily.search("Budget", { root = dir })
  pick.show = saved_show
  eq(search_err, nil, "daily search accepts the vault folder")
  same(rels(results), { "Journal/2020-01-02.md" }, "daily search keeps dated notes in the daily folder")
  eq(shown.title, "mdw daily notes", "daily search uses the note picker")
  mdw.setup({
    workspace = { root = dir },
    obsidian = { import_daily = false },
  })
  eq(daily.spec(dir).folder, "", "import_daily false ignores the vault folder")
  mdw.setup({
    workspace = { root = dir },
    daily = { folder = "Mine" },
  })
  eq(daily.spec(dir).folder, "Mine", "an explicit daily folder wins")

  mdw.setup({ workspace = { root = dir } })
  local ui = require("mdw.ui")
  local saved_choose = ui.choose
  local chose = 0
  ui.choose = function()
    chose = chose + 1
  end
  local created
  create.start({
    root = dir,
    relpath = "from one.md",
    title = "Paris",
    when = stamp,
    confirm = false,
  }, function(written)
    created = written
  end)
  ui.choose = saved_choose
  eq(chose, 0, "one template skips the picker")
  local one = assert(io.open(created, "rb")):read("*a")
  eq(one, "Hello Paris 2020-01-02\n", "a vault template is rendered locally")

  write(dir, "Templates/Stay.md", "Stay {{title}}\n")
  mdw.setup({
    workspace = { root = dir },
    create = { templates = { Trip = "CONFIG {{title}}\n" } },
  })
  ui.choose = function(_, items)
    for _, item in ipairs(items) do
      if item.text == "Trip" then
        item.choose()
        return
      end
    end
    fail("picker did not offer Trip")
  end
  local picked
  create.start({ root = dir, relpath = "from picker.md", title = "Paris", confirm = false }, function(written)
    picked = written
  end)
  local picked_body = assert(io.open(picked, "rb")):read("*a")
  eq(picked_body, "CONFIG Paris\n", "a configured template replaces the file")
  ui.choose = function(_, items)
    eq(items[#items].text, "(blank)", "the picker offers a blank note")
    items[#items].choose()
  end
  local blank
  create.start({ root = dir, relpath = "from blank.md", confirm = false }, function(written)
    blank = written
  end)
  eq(assert(io.open(blank, "rb")):read("*a"), "", "blank skips the template")
  ui.choose = saved_choose

  local log = dir .. "/obsidian.log"
  local script = dir .. "/obsidian"
  local handle = assert(io.open(script, "wb"))
  handle:write(string.format([=[
#!/bin/sh
printf '%%s\n' "$@" >> %q
for arg in "$@"; do
  if [ "$arg" = "templates" ]; then
    printf '%%s\n' Beta Alpha
    exit 0
  fi
done
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
    obsidian = { command = script },
  })
  os.remove(log)
  local local_names = require("mdw.templates").names(dir, "local")
  same(local_names, { "Stay", "Trip" }, "local templates come from the vault folder")
  eq(vim.uv.fs_stat(log), nil, "the local backend does not ask the CLI for templates")
  mdw.setup({
    workspace = { root = dir },
    create = { backend = "obsidian" },
    obsidian = { command = script },
  })
  ui.choose = function(_, items)
    same({ items[1].text, items[2].text }, { "Alpha", "Beta" }, "CLI template names are sorted")
    items[1].choose()
  end
  local cli
  create.start({ root = dir, relpath = "from cli choice.md", confirm = false }, function(written)
    cli = written
  end)
  ui.choose = saved_choose
  truthy(cli ~= nil, "the obsidian backend creates from the chosen template")
  local recorded = assert(io.open(log, "rb")):read("*a")
  truthy(recorded:find("templates\n", 1, true) ~= nil, "template names come from the CLI")
  truthy(recorded:find("template=Alpha", 1, true) ~= nil, "the chosen template is passed to create")
  eq(assert(io.open(cli, "rb")):read("*a"), "from cli\n", "the CLI writes the obsidian note")
  mdw.setup({
    workspace = { root = dir },
    obsidian = { command = script },
  })
  local adhoc
  create.start({
    root = dir,
    relpath = "adhoc.md",
    template = "Travel",
    backend = "obsidian",
    confirm = false,
  }, function(written)
    adhoc = written
  end)
  eq(require("mdw.config").get().create.backend, "local", "one command does not change the backend")
  truthy(adhoc ~= nil, "backend=obsidian creates through the CLI")
  mdw.setup({
    workspace = { root = dir },
    create = { backend = "obsidian" },
    obsidian = { command = dir .. "/missing-obsidian" },
  })
  local missing
  create.start({ root = dir, relpath = "missing cli.md", confirm = false }, function(_, err)
    missing = err
  end)
  truthy(missing ~= nil and missing:find("not found", 1, true) ~= nil, "a missing CLI is reported")
end)

add("lists, images, and formatting", function()
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
  eq(vim.fn.maparg("<C-8>", "n"), "", "list keys are unset until configured")
  local lists = require("mdw.lists")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "- alpha" })
  lists.continue({ row = 1, col = 7, insert = true })
  same(vim.api.nvim_buf_get_lines(0, 0, 2, false), { "- alpha", "- " }, "enter continues a bullet")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "- [x] done" })
  lists.continue({ row = 1, col = 10, insert = true })
  eq(vim.api.nvim_buf_get_lines(0, 1, 2, false)[1], "- [ ] ", "a continued checkbox is unchecked")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "1. one", "2. two" })
  lists.continue({ row = 1, col = 6, insert = true })
  same(vim.api.nvim_buf_get_lines(0, 0, 3, false), { "1. one", "2. ", "3. two" }, "enter renumbers the following item")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "- parent", "  - child" })
  lists.continue({ row = 2, col = 10, insert = true })
  eq(vim.api.nvim_buf_get_lines(0, 2, 3, false)[1], "  - ", "a continued nested item stays nested")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "- parent", "  - " })
  vim.api.nvim_win_set_cursor(0, { 2, 4 })
  lists.continue({ row = 2, col = 4, insert = true })
  eq(vim.api.nvim_buf_get_lines(0, 1, 2, false)[1], "- ", "an empty nested item unnests")
  lists.continue({ row = 2, col = 2, insert = true })
  eq(vim.api.nvim_buf_get_lines(0, 1, 2, false)[1], "", "an empty top-level item becomes a blank line")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "- hello" })
  lists.continue({ row = 1, col = 5, insert = true })
  same(vim.api.nvim_buf_get_lines(0, 0, 2, false), { "- hel", "- lo" }, "enter splits the item at the cursor")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "1. a", "2. b", "- c", "* d", "+ e", "plain" })
  lists.nest(2, 2)
  same(vim.api.nvim_buf_get_lines(0, 0, 2, false), { "1. a", "  1. b" }, "nesting an ordered item starts a child at 1")
  lists.unnest(2, 2)
  same(vim.api.nvim_buf_get_lines(0, 0, 2, false), { "1. a", "2. b" }, "unnesting rejoins the numbered list")
  lists.unnest(1, 1)
  eq(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1], "1. a", "a top-level item does not lose its marker")
  lists.nest(3, 5)
  same(vim.api.nvim_buf_get_lines(0, 2, 5, false), { "  - c", "  * d", "  + e" }, "nest keeps the bullet marker")
  vim.api.nvim_win_set_cursor(0, { 6, 0 })
  lists.check(6, 3)
  same(vim.api.nvim_buf_get_lines(0, 2, 6, false), {
    "  - [ ] c",
    "  * [ ] d",
    "  + [ ] e",
    "plain",
  }, "check adds a box on list items and leaves prose")
  lists.check(3, 5)
  same(vim.api.nvim_buf_get_lines(0, 2, 5, false), {
    "  - [x] c",
    "  * [x] d",
    "  + [x] e",
  }, "check marks an empty box")
  lists.check(4, 4)
  eq(vim.api.nvim_buf_get_lines(0, 3, 4, false)[1], "  * [ ] d", "check clears a marked box")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "```", "- [ ] hidden", "```" })
  lists.check(2, 2)
  lists.nest(2, 2)
  eq(vim.api.nvim_buf_get_lines(0, 1, 2, false)[1], "- [ ] hidden", "fenced list text stays unchanged")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "- a", "- [X] b" })
  vim.api.nvim_win_set_cursor(0, { 1, 2 })
  vim.cmd("1,2Mdw list check")
  same(vim.api.nvim_buf_get_lines(0, 0, 2, false), { "- [ ] a", "- [ ] b" }, "the list command toggles a range")
  eq(vim.api.nvim_win_get_cursor(0)[2], 6, "the cursor stays on the item text")

  local edit = require("mdw.edit")
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
