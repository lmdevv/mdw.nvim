{ self }:
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.plugins.mdw;
  plugin = import ./plugin.nix { inherit lib pkgs self; };
  toLua =
    value:
    if lib ? nixvim && lib.nixvim ? toLuaObject then
      lib.nixvim.toLuaObject value
    else
      throw "Import mdw.nixvimModules.default from a NixVim configuration.";
in
{
  options.plugins.mdw = {
    enable = lib.mkEnableOption "mdw.nvim";

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      example = {
        search.picker = "auto";
        format.format_on_save = false;
      };
      description = "Argument passed to require(\"mdw\").setup().";
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.rumdl ]";
      description = ''
        Packages added to Neovim's PATH. Use this for rumdl, git, or the
        Obsidian CLI. mdw does not download them on its own.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    extraPlugins = [ plugin ];
    extraPackages = cfg.extraPackages;
    extraConfigLua = ''
      require("mdw").setup(${toLua cfg.settings})
    '';
  };
}
