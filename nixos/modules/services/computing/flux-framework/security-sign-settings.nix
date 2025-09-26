{
  config,
  lib,
  options,
  pkgs,
  ...
}: {
  options = {
    sign.max-ttl = lib.mkOption {
      type = lib.types.int;
      default = 1209600; # two weeks
      description = ''
        TODO
      '';
    };

    sign.default-type = lib.mkOption {
      type = lib.types.str;
      default = "munge";
      description = ''
        TODO
      '';
    };

    sign.allowed-types = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "munge" ];
      description = ''
        TODO
      '';
    };
  };
}
