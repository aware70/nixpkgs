{
  config,
  lib,
  options,
  pkgs,
  ...
}:
{
  # Keys without a typed option below are passed through to the TOML file.
  freeformType = lib.types.attrsOf lib.types.anything;

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
