{
  config,
  lib,
  options,
  pkgs,
  ...
}: {
  options = {
    systemd.enable = lib.mkOption {
      type = lib.types.bool;
      internal = true;
    };

    exec = {
      imp = lib.mkOption {
        type = lib.types.path;
        internal = true;
      };

      job-shell = lib.mkOption {
        type = lib.types.path;
        internal = true;
      };

      service = lib.mkOption {
        type = lib.types.str;
        internal = true;
      };

      sdexec-properties = lib.mkOption {
        type = lib.types.attrs;
        default = {
          MemoryMax = "95%";
        };
        description = ''
        '';
      };
    };

    bootstrap = {
      curve_cert = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
        '';
      };
      default_port = lib.mkOption {
        type = lib.types.port;
        default = 8050;
        description = ''
        '';
      };
      default_bind = lib.mkOption {
        type = lib.types.str;
        default = "tcp://eth1:%p";
        description = ''
        '';
      };
      default_connect = lib.mkOption {
        type = lib.types.str;
        default = "tcp://%h:%p";
        description = ''
        '';
      };
      hosts = lib.mkOption {
        type = lib.types.listOf lib.types.attrs;
        description = ''
        '';
      };
    };

    resource = {
      path = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Path to a Flux RFC 20 (R version 1) file defining resources
          available to the cluster.
        '';
      };

      config = lib.mkOption {
        type = lib.types.listOf lib.types.attrs;
        default = [];
        description = ''
          List of resource config entries used as an alternative to
          the RFC 20 file in `resource.path`.
        '';
      };

      scheduling = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Path to a JSON file containing a graph definition in
          JSON Graph Format that will amend the `scheduling` key
          in the configured RFC 20 resource definition.
        '';
      };

      exclude = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = ''
          Exclude nodes matching this string from job assignment.
        '';
      };

      norestrict = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Disable restricting of the loaded HWLOC topology XML to
          the current cpu affinity mask of the Flux broker.
        '';
      };

      noverify = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Disable restricting of the loaded HWLOC topology XML to the
          current cpu affinity mask of the Flux broker.
        '';
      };

      rediscover = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          If true, force rediscovery of resources using HWLOC, rather
          then using the R and HWLOC XML from the enclosing instance.
        '';
      };

      journal-max = lib.mkOption {
        type = lib.types.int;
        default = 100000;
        description = ''
          An integer containing the maximum number of resource eventlog
          events held in the resource module for the resource.journal RPC.
        '';
      };
    };

    access = {
      allow-guest-user = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Allow guest users in the system flux instance.
        '';
      };

      allow-root-owner = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Treat root as an owner of the system flux instance.
        '';
      };
    };

    tbon = {
      tcp_user_timeout = lib.mkOption {
        type = lib.types.str;
        default = "2m";
        description = ''
        '';
      };
    };

    kvs = {
      checkpoint-period = lib.mkOption {
        default = "30m";
        description = ''
        '';
      };
      gc-threshold = lib.mkOption {
        default = 100000;
        description = ''
        '';
      };
    };

    ingest = {
      validator.plugins = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "jobspec" "feasibility" ];
        description = ''
        '';
      };
    };

    job-manager = {
      inactive-age-limit = lib.mkOption {
        type = lib.types.str;
        default = "7d";
        description = ''
          Age limit for inactive jobs within the instance.
        '';
      };
    };

    policy = {
      jobspec.defaults.system.duration = lib.mkOption {
        type = lib.types.str;
        default = "1m";
        description = ''
        '';
      };

      limits = {
        duration = lib.mkOption {
          type = lib.types.str;
          default = "2h";
          description = ''
            Maximum duration of jobs within the instance.
          '';
        };

        job-size = {
          max.nnodes = lib.mkOption {
            type = lib.types.int;
            default = 8;
            description = ''
              Maximum node count a job can request.
            '';
          };
          max.ncores = lib.mkOption {
            type = lib.types.int;
            default = 32;
            description = ''
              Maximum core count a job can request.
            '';
          };
        };
      };
    };

    sched-fluxion-qmanager.queue-policy = lib.mkOption {
      type = lib.types.str;
      default = "easy";
      description = ''
        TODO
      '';
    };

    sched-fluxion-resource = {
      match-policy = lib.mkOption {
        type = lib.types.str;
        default = "lonodex";
        description = ''
          TODO
        '';
      };
      match-format = lib.mkOption {
        type = lib.types.str;
        default = "rv1_nosched";
        description = ''
          TODO
        '';
      };
    };
  };
}
