{
  config,
  lib,
  options,
  pkgs,
  ...
}: {
  options = {
    exec.allowed-users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "flux" ];
      description = ''
        Users allowed to execute flux-imp.
        WARNING: don't put normal users here!
      '';
    };

    exec.allowed-shells = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ "/run/wrappers/bin/flux-shell" ];
      description = ''
        Allowed job shells.
        WARNING: don't put any old shell here!
      '';
    };

    exec.pam-support = lib.mkEnableOption "pam-support";
  };
}
