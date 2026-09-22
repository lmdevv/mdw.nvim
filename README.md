# mdw.nvim

Markdown workspace search for Neovim. This tree implements workspace indexing and metadata search. The broader product is described in [PRD.md](PRD.md).

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
| `:Mdw` | Show usage |
| `:Mdw health` | Check version, workspace, index, and integrations |
| `:Mdw search [query]` | Search notes in the current workspace |
| `:Mdw index` | Rebuild the workspace index |

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

Modified buffers are read from editor text, so unsaved edits are searchable. Other files are read from disk. `:Mdw index` rebuilds the workspace. Opening an unmodified buffer picks up an external edit to that file.

## Search

`:Mdw search` opens `mini.pick` when it is installed and `vim.ui.select` otherwise.

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

## Try it

```sh
nix run .#demo
```

That starts Neovim with this plugin and `mini.pick` in a fresh copy of the fixture vault. Leader is space. `<leader>sn` searches notes, `<leader>sf` searches files, and `<leader>sh` opens health.

## Tests

```sh
make test
```

## License

MIT. See [LICENSE](LICENSE).
