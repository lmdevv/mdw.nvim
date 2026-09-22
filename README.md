# mdw.nvim

Current release: [v0.0.2](https://github.com/lmdevv/mdw.nvim/releases/tag/v0.0.2).

Markdown workspace tools for Neovim 0.11 and newer. Search notes by path, title, alias, and tag. Follow links, keep a sidebar, rename a note and its references, create notes and daily notes, and edit lists. Formatting and diagnostics are optional.

mdw maps no keys. Behavior details live in `:help mdw.txt`.

## Requirements

Neovim 0.11 or newer. Setup still succeeds when an optional tool is missing.

| Tool | Used for |
| --- | --- |
| mini.pick, snacks.nvim, or telescope.nvim | `:mdw search`, `:mdw dailies`, and the link chooser. Otherwise `vim.ui.select` |
| rumdl | `:mdw format` and `:mdw lint` |
| wl-paste or xclip | `:mdw image` on Linux. Other systems set `edit.clipboard`, for example `{ "pngpaste" }` |
| render-markdown.nvim | In-buffer rendering when `render.enabled` is true |
| markdown-oxide | LSP when `lsp.enabled` is true |
| Obsidian CLI | Template list and note creation when `create.backend` is `"obsidian"`, and `:mdw obsidian` |
| Trouble | `:mdw trouble` |

`:checkhealth mdw` reports which of these are available.

## Installation

Call `setup()` after install. Until then the plugin adds no commands.

### lazy.nvim

```lua
{
  "lmdevv/mdw.nvim",
  version = "v0.0.2",
  config = function()
    require("mdw").setup()
  end,
}
```

### vim.pack

Neovim 0.12 and newer:

```lua
vim.pack.add({ { src = "https://github.com/lmdevv/mdw.nvim", version = "v0.0.2" } })
require("mdw").setup()
```

The command name is `:Mdw`. Typing `:mdw` is rewritten to `:Mdw`.

### NixVim

```nix
inputs.mdw.url = "github:lmdevv/mdw.nvim/v0.0.2";

programs.nixvim = {
  imports = [ inputs.mdw.nixvimModules.default ];

  plugins.mdw = {
    enable = true;
    settings = {
      search.picker = "auto";
    };
    extraPackages = [ pkgs.rumdl pkgs.git ];
  };
};
```

`settings` is passed to `require("mdw").setup()`. `extraPackages` is added to Neovim's `PATH`. A standalone NixVim configuration imports the same module through `nixvim.lib.evalNixvim`.

NixVim does not ship this plugin. Import `nixvimModules.default` from this flake. That module installs the plugin and calls `setup()`.

## Try it

With Nix, on x86_64-linux, aarch64-linux, or aarch64-darwin. From this repository:

```sh
nix run
```

From anywhere:

```sh
nix run github:lmdevv/mdw.nvim
```

This starts a separate Neovim in a writable copy of a walkthrough vault. It does not change your own configuration. The start screen has one action, Open the walkthrough. That note tells you the next command, then links to the next note with `gd`. Press space and the next key is listed. Inline images are drawn by snacks.image when the terminal supports Kitty graphics placeholders. The demo enables the Snacks picker, dashboard, and image module, plus mini.clue, a color scheme, rumdl, markdown-oxide, and render-markdown. Those are not turned on by installing mdw. Leader is space. These keys exist only in the demo:

| Key | Action |
| --- | --- |
| `<leader>ms` | Search notes |
| `<leader>sf` | Search files |
| `<leader>mh` | Health |
| `<leader>mb` | Sidebar |
| `<leader>md` | Today's daily note |
| `gd` | Follow the link under the cursor |
| `<CR>` in insert, `o` in normal | Continue a list item |
| `>>` / `<<` | Nest or unnest |
| `<leader>mt` | Toggle a checkbox |
| `<leader>q` | Quit |

## What it does

**Search.** `:mdw search` matches path, filename, title, aliases, and tags. `#parent` matches that tag exactly and does not match `parent/child`. An empty query lists every note. Note bodies stay in your picker's grep. With `search.enrich_files`, file search in mini.pick, Snacks, and Telescope also matches title, alias, and tag while the directory is inside the workspace.

**Links.** `gd` follows the Markdown link or wikilink under the cursor. One match opens the note, at the heading or block when the link names one. Several matches open a chooser. `:mdw sidebar` shows the outline, backlinks, and outgoing links. `:mdw backlinks`, `:mdw outgoing`, and `:mdw outline` fill the quickfix. `:mdw rename new/path.md` previews references, updates them, and moves the file.

**Notes.** `:mdw new path/note.md` asks, then creates the note. `:mdw daily` opens today's `YYYY-MM-DD` note, or creates it when that file is missing. `:mdw daily prev` and `:mdw daily next` move among daily notes that already exist. `:mdw dailies` opens the note picker with only those daily notes.

When `.obsidian/daily-notes.json` or `.obsidian/templates.json` is present, unset daily and template options are filled from those files. The CLI stays off until `create.backend` is `"obsidian"`, or one command passes `backend=obsidian`. One template is used on its own. Several templates open a picker, including a blank note. `template=Trip` skips the picker. `{{title}}`, `{{date}}`, `{{time}}`, and `{{date:YYYY-MM-DD}}` are filled in.

**Editing.** `:mdw list continue`, `nest`, `unnest`, and `check` edit the current list item. Bind them with `lists.maps` if you want keys. `:mdw format` and `:mdw lint` use rumdl. `:mdw image` saves a clipboard PNG under `assets/` and inserts a Markdown image.

## How it works

The workspace is the git toplevel of the file in the current window. A file outside git uses that file's directory. `workspace.root` pins one directory and skips discovery.

The index is Lua. It reads a frontmatter title, otherwise the first heading, otherwise the filename. Aliases come from `aliases` or `alias`. Tags come from `tags` or `tag`, plus inline `#tags` outside fenced code, inline code, and link destinations. A malformed note is skipped and reported. Unsaved buffer text wins over the file on disk. `:mdw index` rebuilds the workspace.

Dot-directories and `node_modules` are skipped. Notes are `.md`, `.markdown`, `.mdc`, `.mdx`, and `.mkd`.

`:help mdw.txt` has the ranking rules, the frontmatter subset, and the full command list.

## Configuration

`setup()` replaces the options. Calling it again does not duplicate commands or autocmds. This is the default:

```lua
require("mdw").setup({
  workspace = {
    root = nil, -- git toplevel of the current file
  },
  search = {
    picker = "auto", -- mini, snacks, telescope, or select
    enrich_files = false,
  },
  create = {
    backend = "local", -- "obsidian" uses the Obsidian CLI
    default_template = nil,
  },
  daily = {
    folder = nil, -- filled from .obsidian/daily-notes.json when unset
    format = nil,
    template = nil,
  },
  lists = {
    maps = {
      continue = nil, -- insert mode
      open = nil, -- normal mode
      nest = nil,
      unnest = nil,
      check = nil,
    },
  },
  format = {
    lint = true,
    format_on_save = false,
  },
})
```

Set `obsidian.import_daily` to false to ignore `.obsidian/daily-notes.json`. Set `navigation.gd` to false to leave `gd` to the LSP. Set `lsp.rename` to true to leave rename on markdown-oxide.

## Contributing

```sh
nix develop
make test
```

`nix develop` provides Neovim, git, and rumdl. Tests run headless. The `nix run` demo is for trying the plugin. Design notes are not part of the published tree.

## License

MIT. See [LICENSE](LICENSE).
