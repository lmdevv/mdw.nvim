{
  lib,
  pkgs,
  self,
}:
pkgs.vimUtils.buildVimPlugin {
  pname = "mdw-nvim";
  version = "0.0.3";
  src = lib.cleanSourceWith {
    src = self;
    filter =
      path: type: baseNameOf path != ".scratch" && lib.cleanSourceFilter path type;
  };
  doCheck = false;
}
