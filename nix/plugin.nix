{
  lib,
  pkgs,
  self,
}:
pkgs.vimUtils.buildVimPlugin {
  pname = "mdw-nvim";
  version = self.shortRev or self.dirtyShortRev or "unknown";
  src = lib.cleanSourceWith {
    src = self;
    filter =
      path: type: baseNameOf path != ".scratch" && lib.cleanSourceFilter path type;
  };
  doCheck = false;
}
