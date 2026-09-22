{
  pkgs,
  self,
}:
let
  lib = pkgs.lib;
  plugin = import ./plugin.nix { inherit lib pkgs self; };

  tools = [
    pkgs.git
  ]
  ++ lib.optional (pkgs ? rumdl) pkgs.rumdl
  ++ lib.optional (pkgs ? markdown-oxide) pkgs.markdown-oxide
  ++ lib.optional (pkgs ? imagemagick) pkgs.imagemagick;

  nvim = pkgs.wrapNeovimUnstable pkgs.neovim-unwrapped {
    extraName = "-mdw-test";
    plugins = [
      plugin
      pkgs.vimPlugins.mini-pick
      pkgs.vimPlugins.mini-starter
      pkgs.vimPlugins.mini-statusline
      pkgs.vimPlugins.mini-icons
      pkgs.vimPlugins.mini-clue
      pkgs.vimPlugins.image-nvim
      pkgs.vimPlugins.catppuccin-nvim
      pkgs.vimPlugins.render-markdown-nvim
      (pkgs.vimPlugins.nvim-treesitter.withPlugins (parsers: [
        parsers.markdown
        parsers.markdown_inline
        parsers.yaml
      ]))
    ];
    luaRcContent = builtins.readFile ./test-init.lua;
    wrapperArgs = [
      "--prefix"
      "PATH"
      ":"
      (lib.makeBinPath tools)
    ];
  };

  note = name: text: pkgs.writeText name text;

  notes = {
    "vault/Welcome.md" = ''
      ---
      title: Start here
      ---

      # Start here

      ![](assets/welcome.png)

      Press space. The next key appears beside it. These keys exist only in this demo.

      | Keys | What happens |
      | --- | --- |
      | space s n | Search notes |
      | space s f | Search files, including title, alias, and tag |
      | space s h | Health |
      | space s s | Sidebar |
      | space s d | Today's daily note |
      | g d | Follow the link under the cursor |
      | Enter in insert, o | Continue a list item |
      | >> and << | Nest or unnest |
      | space x | Toggle a checkbox |

      In the sidebar, o is the outline, b is backlinks, l is outgoing, Enter jumps, and q closes.

      The picture above is drawn by image.nvim when the terminal supports Kitty graphics (kitty, ghostty, or wezterm).

      Put the cursor on [[Search]] and press gd.
    '';
    "vault/Search.md" = ''
      ---
      title: Search the vault
      ---

      # Search

      Press space s n, or run `:mdw search`.

      1. Search `Budget`. One row is [[money]], whose title is Budget. The file name does not contain Budget.
      2. Search `yearly`. That is an alias of the same note.
      3. Search `#work`. Budget matches. `#parent` does not match the tag `parent/child` on [[Outline]].
      4. Search `#parent/child`. Outline matches.
      5. Press space s f and search `yearly`. File search uses the same metadata.
      6. Change a word in this note, run `:mdw index`, and search again. The index reads the unsaved buffer.

      Next, press gd on [[Links]].
    '';
    "vault/money.md" = ''
      ---
      title: Budget
      aliases:
        - yearly plan
      tags: [work]
      ---

      # Budget

      This note is found by its title, by the alias "yearly plan", and by the tag work.

      Back to [[Search]].
    '';
    "vault/Links.md" = ''
      ---
      title: Follow links
      ---

      # Links

      Put the cursor on a link and press gd. `:mdw follow` is the same command.

      - [[money]] opens one note.
      - [[yearly plan]] opens that same note by alias.
      - [[Task]] matches two notes and asks you to choose.
      - [[Brand New]] is missing. Confirm to create it, or cancel.
      - [[Outline#Sidebar]] opens at that heading.
      - [[Outline#Gone]] opens the note and says the heading is missing.
      - [[Outline#^mark]] opens at the marked paragraph.
      - [[money|Not an alias]] follows the target. The label is not an alias.

      Next, press gd on [[Outline]].
    '';
    "vault/tasks/one/Task.md" = ''
      ---
      title: Task in one
      ---

      # Task in one

      One of the two notes named Task. Back to [[Links]].
    '';
    "vault/tasks/two/Task.md" = ''
      ---
      title: Task in two
      ---

      # Task in two

      The other note named Task. Back to [[Links]].
    '';
    "vault/Outline.md" = ''
      ---
      title: Outline
      tags: [parent/child]
      ---

      # Sidebar

      Press space s s. This window is the outline.

      Press b for backlinks. [[Links]] points here. Press l for outgoing links. Enter jumps. q closes.

      `:mdw outline`, `:mdw backlinks`, and `:mdw outgoing` put the same lists in the quickfix.

      # Mark

      A marked paragraph. ^mark

      Next, press gd on [[Edit]].
    '';
    "vault/Edit.md" = ''
      ---
      title: Edit this note
      ---

      # Edit

      Run these on this note. Each one changes only the field you name.

      - `:mdw tags demo walk`
      - `:mdw aliases tour stop`
      - `:mdw property title Edited`

      Then `:mdw search #demo`.

      ## Lists

      - first item
      - [ ] a task

      From the end of "first item", press o, or Enter in insert mode. On the task, press space x. On a list line, press >> and then <<.

      The commands are `:mdw list continue`, `:mdw list nest`, `:mdw list unnest`, and `:mdw list check`.

      ## Format

      #NoSpace

      `:mdw lint` shows the rumdl warning. `:mdw format` fixes the buffer when rumdl succeeds.

      Next, press gd on [[Create]].
    '';
    "vault/Create.md" = ''
      ---
      title: Create notes
      ---

      # Create

      - `:mdw new tour/made` asks, then writes a note from the demo template.
      - `:mdw daily` opens today's note, or creates it.
      - `:mdw dailies` searches only daily notes. Press space s d for today.
      - `:mdw image` pastes a clipboard PNG into `assets/` and inserts a Markdown image.
      - `:mdw health` reports the picker, rumdl, and markdown-oxide. Press space s h.
      - `:mdw rename tour/moved.md` is last. Run it from [[money]]. It previews references, then updates them and moves the file.

      That is the tour.
    '';
  };

  howto = ''
    Press space to see the next key.
    Enter on the start screen opens Welcome.md.
    Follow gd from each note to the next one.
  '';

  logo = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/neovim/neovim.github.io/5801b2318a1b1fd880e54985cce8357affe855f0/static/logos/neovim-mark.png";
    sha256 = "07kd2g9ychmcvk0amabjhkc4x6k1npp1zxbrk44i8x13vnj22168";
  };

  fixture = pkgs.runCommand "mdw-fixture" { nativeBuildInputs = [ pkgs.git ]; } ''
    mkdir -p $out/opt/fixture
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (path: text: ''
        install -D ${note (builtins.baseNameOf path) text} "$out/opt/fixture/${path}"
      '') notes
    )}
    mkdir -p $out/opt/fixture/vault/assets
    cp ${logo} $out/opt/fixture/vault/assets/welcome.png
    cp ${pkgs.writeText "mdw-howto" howto} $out/opt/fixture/HOWTO.txt
    git -C $out/opt/fixture/vault init -q
  '';

  entry = pkgs.writeShellScriptBin "mdw-nvim" ''
    set -euo pipefail
    export PATH="${lib.makeBinPath ([ pkgs.coreutils pkgs.git ] ++ tools)}:$PATH"
    export TERM="''${TERM:-xterm-256color}"
    work=$(mktemp -d /tmp/mdw-work-XXXXXX)
    src=${fixture}/opt/fixture
    cp -a "$src/vault" "$work/vault"
    cp "$src/HOWTO.txt" "$work/HOWTO.txt"
    chmod -R u+w "$work"
    export GIT_CONFIG_GLOBAL="$work/gitconfig"
    git config --file "$GIT_CONFIG_GLOBAL" --add safe.directory '*'
    cd "$work/vault"
    exec ${nvim}/bin/nvim "$@"
  '';

  imageRoot = pkgs.buildEnv {
    name = "mdw-nvim-image-root";
    paths = [
      nvim
      entry
      fixture
      pkgs.git
      pkgs.bashInteractive
      pkgs.coreutils
      pkgs.ncurses
    ]
    ++ lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.glibcLocales;
    pathsToLink = [
      "/bin"
      "/lib"
      "/opt"
      "/share"
    ];
  };
in
{
  program = "${entry}/bin/mdw-nvim";
  packages = {
    inherit nvim fixture;
    plugin = plugin;
    default = entry;
    demo = entry;
  }
  // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
    container = pkgs.dockerTools.buildImage {
      name = "mdw-nvim-test";
      tag = plugin.version;
      copyToRoot = imageRoot;
      config = {
        Entrypoint = [ "/bin/mdw-nvim" ];
        WorkingDir = "/tmp";
        Env = [
          "TERM=xterm-256color"
          "HOME=/tmp"
          "LANG=C.UTF-8"
          "LOCALE_ARCHIVE=${pkgs.glibcLocales}/lib/locale/locale-archive"
        ];
      };
    };
  };
}
