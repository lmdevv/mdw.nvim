# mdw.nvim

Markdown workspace search for Neovim. This tree implements workspace indexing and metadata search.

The plugin requires Neovim 0.11 or newer. Original code is MIT.

## Setup

```lua
require("mdw").setup({
  workspace = {
    -- Pin a root. Omit to use the git toplevel of the current file.
    root = nil,
  },
  search = {
    -- Also match note metadata from mini.pick's file picker.
    enrich_files = false,
  },
})
```

`setup()` can be called again. It replaces the options and does not duplicate commands or autocmds. mdw does not create leader mappings.

Install `mini.pick` before enabling `search.enrich_files` if you want that picker wrapped during setup.

## Commands

| Command | Action |
| --- | --- |
| `:mdw` | Show usage |
| `:mdw health` | Check version, workspace, index, and integrations |
| `:mdw search [query]` | Search notes in the current workspace |
| `:mdw index` | Rebuild the workspace index |

`:checkhealth mdw` reports the same health information.

## Workspace

Search and indexing use the git toplevel of the file in the current window. A file outside git uses that file's directory. `workspace.root` pins one directory and skips discovery; a relative path is resolved from the current working directory.

Changing to a buffer from another repository changes the workspace. Dot-directories and `node_modules` are skipped. Notes are `.md`, `.markdown`, `.mdc`, `.mdx`, and `.mkd`.

## What the index reads

Indexing does not write files. A malformed note is skipped and reported; other notes are still indexed.

- Title: frontmatter string `title`, otherwise the first ATX heading, otherwise the filename stem.
- Aliases: frontmatter `aliases` or `alias`. A link label is not an alias.
- Tags: frontmatter `tags` or `tag`, plus inline `#tags` outside fenced code, inline code, and link destinations.

The same scan is used for every supported extension. A `#` inside JSX can become a tag. Supported frontmatter is a YAML subset: scalars, flow lists, and block lists. Unknown keys are ignored when their lines fit that subset. Multiline scalars and unclosed frontmatter skip the file.

Modified buffers are read from editor text, so unsaved edits are searchable. Other files are read from disk. `:mdw index` rebuilds the workspace. Opening an unmodified buffer picks up an external edit to that file.

## Search

`:mdw search` uses `search.picker`. `auto` (the default) uses `mini.pick`, then Snacks, then Telescope, and `vim.ui.select` when none of those is installed. Set `search.picker` to `mini`, `snacks`, `telescope`, or `select` to choose one. The note list keeps mdw's own ranking; the picker does not re-filter it.

A query is text plus optional `#tag` filters. Every filter must match the whole tag, ignoring case, so `#parent` does not match `parent/child`. Every text token must match a substring of the path, filename, title, aliases, or tags. Text is case-insensitive until the query contains an uppercase letter.

Results are one row per note. Columns are separated by tabs, in this order: path, title, aliases, tags. A title that is only the filename is left out, and aliases or tags are left out when the note has none. Ranking, strongest first:

1. Exact title or alias
2. Prefix of a title or alias
3. Other substring of a title or alias
4. Filename
5. Path
6. Tag only

An empty query lists every note in the workspace. Content search is separate and is not part of this command.

With `search.enrich_files = true`, `MiniPick.builtin.files()` matches the same metadata while its directory is inside the workspace. Call `setup()` with `enrich_files = false` to restore the previous file picker.

## Navigation

`gd` follows the Markdown link or wikilink under the cursor. One match opens that note, at the heading or block when the link names one. Several matches open a chooser. A missing note is created only after confirmation. A missing heading opens the existing note and says the location is missing. Off a link, `gd` falls through to an attached LSP.

`:mdw sidebar` shows the outline for the note you came from. `o`, `b`, and `l` switch among outline, backlinks, and outgoing links. Enter jumps to the entry. `:mdw backlinks`, `:mdw outgoing`, and `:mdw outline` put the same results in the quickfix list. `:mdw trouble backlinks` uses Trouble when it is installed.

`:mdw rename new/path.md` shows the references it would rewrite, then updates them and moves the file. It stops when the destination exists or a buffer has unsaved changes.

## Notes and daily notes

`:mdw new path/note.md` confirms the path and creates it from `create.default_template`. `:mdw daily` opens today's `YYYY-MM-DD` note, or creates it when that file is missing. A second call opens the same file and does not apply the template again. `:mdw daily prev` and `:mdw daily next` move among daily notes that already exist.

`:mdw tags work home`, `:mdw aliases yearly plan`, and `:mdw property title Budget` change one frontmatter field and leave the rest of the file alone.

Set `create.backend` to `obsidian` to create through the official CLI. The command is `obsidian vault=<workspace> create path=<file>`, passed as arguments. `:mdw obsidian` opens the current note in the app.

## Editing

`:mdw format` sends the buffer to `rumdl` and replaces it only when that command succeeds. The buffer is left unchanged if `rumdl` fails or the text changed while it was running. Formatting on save is off until `format.format_on_save` is true. `:mdw lint` publishes `rumdl` diagnostics. Set `format.lint` to false when another tool already owns those diagnostics.

`:mdw list continue` opens the next item. On an empty item it unnests one level, and a top-level empty item becomes a blank line. A checkbox continues unchecked. A numbered list renumbers the items that follow. `:mdw list nest` and `:mdw list unnest` change the indent of the current item or the selected items and keep the marker (`-`, `*`, `+`, or the number). `:mdw list check` toggles a checkbox, or adds an empty one on a list item that does not have one. Lines inside a fenced code block stay as they are. The plugin does not bind keys for these. Off a list item, a mapped `>>` or `<<` still indents the line, and a mapped `o` or Enter still inserts a normal line.

```lua
require("mdw").setup({
  lists = {
    maps = {
      continue = "<CR>", -- insert mode
      open = "o", -- normal mode
      nest = ">>",
      unnest = "<<",
      check = "<leader>x",
    },
  },
})
```

`:mdw image` saves a clipboard PNG under `assets/` next to the note and inserts a Markdown image. An existing file is not overwritten.

`render.enabled` turns on `render-markdown.nvim` once, when that plugin is installed. `lsp.enabled` attaches `markdown-oxide`. Set `lsp.rename` to keep rename on the language server so `:mdw rename` does not also rewrite links.

A browser preview is not part of this release.

## Try it

```sh
nix run .#demo
```

That starts Neovim with this plugin and `mini.pick` in a fresh copy of the fixture vault. Leader is space. `<leader>sn` searches notes, `<leader>sf` searches files, `<leader>sh` opens health, `<leader>ss` toggles the sidebar, and `<leader>sd` opens today's daily note. `gd` follows a link. In a note, `<CR>` in insert mode and `o` in normal mode continue a list, `>>` and `<<` nest and unnest, and `<leader>x` toggles a checkbox. Those keys are demo mappings, not plugin defaults.

## Tests

```sh
make test
```

## License

MIT. See [LICENSE](LICENSE).
