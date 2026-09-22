{
  description = "Markdown workspace tools for Neovim";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      perSystem = lib.genAttrs systems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = false;
          };
          demo = import ./nix/demo.nix { inherit pkgs self; };
        in
        {
          packages = demo.packages;
          apps = {
            default = {
              type = "app";
              program = demo.program;
            };
            demo = {
              type = "app";
              program = demo.program;
            };
          };
          devShells.default = pkgs.mkShell {
            packages = [
              pkgs.neovim
              pkgs.git
            ]
            ++ lib.optional (pkgs ? rumdl) pkgs.rumdl
            ++ lib.optional (pkgs ? stylua) pkgs.stylua;
          };
        }
      );
    in
    {
      packages = lib.mapAttrs (_: value: value.packages) perSystem;
      apps = lib.mapAttrs (_: value: value.apps) perSystem;
      devShells = lib.mapAttrs (_: value: value.devShells) perSystem;
      nixvimModules.default = import ./nix/nixvim.nix { inherit self; };
    };
}
