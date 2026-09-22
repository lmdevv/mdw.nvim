{
  description = "Isolated Neovim for trying mdw.nvim";

  inputs.nixpkgs.url = "path:/nix/store/igrbwnqkyn9z88d3kvwhgfrwh6firl0w-source";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = false;
      };
      lib = pkgs.lib;

      mdw = pkgs.vimUtils.buildVimPlugin {
        pname = "mdw-nvim";
        version = "m0-m1";
        src = lib.cleanSource self;
        doCheck = false;
      };

      nvim = pkgs.wrapNeovimUnstable pkgs.neovim-unwrapped {
        extraName = "-mdw-test";
        plugins = [
          mdw
          pkgs.vimPlugins.mini-pick
        ];
        luaRcContent = builtins.readFile ./nix/test-init.lua;
        wrapperArgs = [
          "--prefix"
          "PATH"
          ":"
          (lib.makeBinPath [ pkgs.git ])
        ];
      };

      note = name: text: pkgs.writeText name text;

      notes = {
        "vault/exact.md" = ''
          ---
          title: Budget
          aliases:
            - yearly plan
          tags: [work]
          ---

          # Budget
        '';
        "vault/prefix.md" = ''
          ---
          title: Budget plan
          ---
        '';
        "vault/middle.md" = ''
          ---
          title: Annual budget
          ---
        '';
        "vault/budget-notes.md" = ''
          ---
          title: Misc file
          ---
        '';
        "vault/dir/budget/other.md" = ''
          ---
          title: Path note
          ---
        '';
        "vault/misc.md" = ''
          ---
          title: Tagged
          tags: [budget]
          ---
        '';
        "vault/a/note.md" = ''
          ---
          title: Same
          tags: [work]
          ---
        '';
        "vault/b/note.md" = ''
          ---
          title: Same
          tags: [work, home]
          ---
        '';
        "vault/nested.md" = ''
          ---
          title: Nested
          tags: [parent/child]
          ---
        '';
        "vault/lower.md" = ''
          # budget
        '';
        "vault/label.md" = ''
          See [[Other|UniqueLabel]] and [[Note#Section]].
        '';
        "vault/live.md" = ''
          ---
          aliases:
            - disk
          ---
        '';
        "vault/bad.md" = ''
          ---
          title: "nope
        '';
        "vault/keep.mdc" = ''
          # Keep mdc
        '';
        "vault/keep.markdown" = ''
          # Keep markdown
        '';
        "vault/keep.mdx" = ''
          # Keep mdx
        '';
        "vault/keep.mkd" = ''
          # Keep mkd
        '';
        "vault/skip.txt" = ''
          # Skip text
        '';
        "vault/.hidden/skip.md" = ''
          # Hidden skip
        '';
        "vault/node_modules/pkg/skip.md" = ''
          # Package skip
        '';
        "vault/other.md" = ''
          # Other
        '';
        "vault/my notes/plan.md" = ''
          # Plan

          #work
        '';
        "elsewhere/loose.md" = ''
          # Loose
        '';
        "other-repo/bee.md" = ''
          # Bee
        '';
      };

      fixture =
        pkgs.runCommand "mdw-fixture"
          {
            nativeBuildInputs = [ pkgs.git ];
          }
          ''
            mkdir -p $out/opt/fixture
            ${lib.concatStringsSep "\n" (
              lib.mapAttrsToList (path: text: ''
                install -D ${note (builtins.baseNameOf path) text} "$out/opt/fixture/${path}"
              '') notes
            )}
            cp ${pkgs.writeText "mdw-howto" howto} $out/opt/fixture/HOWTO.txt
            git -C $out/opt/fixture/vault init -q
            git -C $out/opt/fixture/other-repo init -q
          '';

      howto = ''
        This Neovim does not load your user config.
        The vault is a fresh copy under the current directory's parent.
        Open this file with :e ../HOWTO.txt

        Leader is space.
        <leader>sn  note search
        <leader>sf  ordinary mini.pick files
        <leader>sh  mdw health

        :Mdw search [query]
        :Mdw index
        :Mdw health
      '';

      entry = pkgs.writeShellScriptBin "mdw-nvim" ''
        set -euo pipefail
        export TERM="''${TERM:-xterm-256color}"
        work=$(mktemp -d /tmp/mdw-work-XXXXXX)
        src=${fixture}/opt/fixture
        cp -a "$src/vault" "$work/vault"
        cp -a "$src/elsewhere" "$work/elsewhere"
        cp -a "$src/other-repo" "$work/other-repo"
        cp "$src/HOWTO.txt" "$work/HOWTO.txt"
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
          pkgs.glibcLocales
        ];
        pathsToLink = [
          "/bin"
          "/lib"
          "/opt"
          "/share"
        ];
      };
    in
    {
      packages.${system} = {
        inherit nvim fixture;
        default = entry;
        demo = entry;
        container = pkgs.dockerTools.buildImage {
          name = "mdw-nvim-test";
          tag = "m0-m1";
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

      apps.${system} = {
        default = {
          type = "app";
          program = "${entry}/bin/mdw-nvim";
        };
        demo = {
          type = "app";
          program = "${entry}/bin/mdw-nvim";
        };
      };
    };
}
