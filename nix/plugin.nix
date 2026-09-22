{
  lib,
  pkgs,
  self,
}:
pkgs.vimUtils.buildVimPlugin {
  pname = "mdw-nvim";
  version = "m0-m1";
  src = lib.cleanSourceWith {
    src = self;
    filter =
      path: type: baseNameOf path != ".scratch" && lib.cleanSourceFilter path type;
  };
  doCheck = false;
}
