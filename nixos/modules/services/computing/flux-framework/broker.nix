{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let

  cfg = config.services.flux-broker;
  systemCfg = cfg.system;
  securityCfg = cfg.security;
  opt = options.services.flux-broker;
  toml = pkgs.formats.toml {};
  systemToml = toml.generate "flux-system.toml"
    (lib.attrsets.filterAttrsRecursive (name: value: value != null) cfg.system.settings);
  signToml = toml.generate "flux-security-sign.toml" 
    (lib.attrsets.filterAttrsRecursive (name: value: value != null) cfg.security.sign.settings);
  impToml = toml.generate "flux-security-imp.toml"
    (lib.attrsets.filterAttrsRecursive (name: value: value != null) cfg.security.imp.settings);

  systemOptions = {
    systemd.enable = lib.mkOption {
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

  securitySignOptions = {
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

  securityImpOptions = {
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

in
{
  meta.maintainers = [ lib.maintainers.aware70 ];

  options = {
    services.flux-broker = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to enable the flux-broker daemon.
          Note that the standard authentication method is "munge".
          The "munge" service needs to be provided with a password file in order for
          flux-broker to work properly (see `services.munge.password`).
        '';
      };

      package = lib.mkPackageOption pkgs "flux-framework" {
        example = "flux-framework";
      } // {
        default = pkgs.flux-framework;
      };

      system.settings = lib.mkOption {
        type = lib.types.submodule { options = systemOptions; };
        default = {};
        description = ''
          Flux system configuration.
          Documented at: https://flux-framework.readthedocs.io/projects/flux-core/en/stable/man5/flux-config.html
        '';
      };

      security.sign.settings = lib.mkOption {
        type = lib.types.submodule { options = securitySignOptions; };
        default = {};
        description = ''
          Flux security signing configuration. This attribute set is converted into a TOML file.
          Documented at: https://flux-framework.readthedocs.io/projects/flux-security/en/latest/man5/flux-config-security-sign.html
        '';
      };

      security.imp.settings = lib.mkOption {
        type = lib.types.submodule { options = securityImpOptions; };
        default = {};
        description = ''
          Flux security IMP configuration. This attribute set is converted into a TOML file.
          Documented at: https://flux-framework.readthedocs.io/projects/flux-security/en/latest/man5/flux-config-security-imp.html
        '';
      };
    };
  };

  ###### implementation

  config = lib.mkIf cfg.enable {

    services.flux-broker.system.settings = {
      systemd.enable = lib.mkForce true;
      exec = {
        imp = lib.mkForce "/run/wrappers/bin/flux-imp";
        job-shell = lib.mkForce "/run/wrappers/bin/flux-shell";
        service = lib.mkForce "sdexec";
      };
    };

    services.flux-broker.security.imp.settings = {
      exec.allowed-users = lib.mkForce [ "flux" ];
      exec.allowed-shells = lib.mkForce [ "/run/wrappers/bin/flux-shell/" ];
    };

    environment.systemPackages = [ cfg.package ];

    services.munge.enable = lib.mkDefault true;

    users.users.flux = {
      name = "flux";
      group = "flux";
      uid = config.ids.uids.flux;
    };

    users.groups.flux.gid = config.ids.uids.flux;

    # flux-imp must be setuid
    security.wrappers.flux-imp = {
      setuid = true;
      owner = "root";
      group = "root";
      source = "${cfg.package}/libexec/flux/flux-imp";
    };

    security.wrappers.flux-shell = {
      setuid = false;
      owner = "flux";
      group = "flux";
      source = "${cfg.package}/libexec/flux/flux-shell";
    };

    systemd.tmpfiles.settings = {
      "flux-security-config" = {
        "/etc/flux/security/conf.d/sign.toml".C = {
            user = "root";
            group = "root";
            mode = "0644";
            argument = "${signToml}";
         };

         "/etc/flux/imp/conf.d/imp.toml".C = {
           user = "root";
           group = "root";
           mode = "0644";
           argument = "${impToml}";
         };
      };
    };

    systemd.services.flux-broker = {
      path = with pkgs; [ cfg.package coreutils bash systemd ];
      wantedBy = [ "multi-user.target" ];
      wants = [
        "systemd-tmpfiles-clean.service"
        "munge.service"
      ];

      serviceConfig = {
        Type = "notify";
        NotifyAccess = "all";
        TimeoutStopSec = 90;
        KillMode = "mixed";
        ExecStart = ''
        ${pkgs.bash}/bin/bash -c '\
        XDG_RUNTIME_DIR=/run/user/$UID \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$UID/bus \
        ${cfg.package}/bin/flux broker \
          --config-path=${systemToml} \
          -Scron.directory=${cfg.package}/etc/flux/system/cron.d \
          -Srundir=/run/flux \
          -Sstatedir=''${STATE_DIRECTORY:-/var/lib/flux} \
          -Slocal-uri=local:///run/flux/local \
          -Slog-stderr-level=6 \
          -Slog-stderr-mode=local \
          -Sbroker.rc2_none \
          -Sbroker.quorum=1 \
          -Sbroker.quorum-timeout=none \
          -Sbroker.cleanup-timeout=45 \
          -Sbroker.exit-norestart=42 \
          -Sbroker.sd-notify=1 \
          -Scontent.dump=auto \
          -Scontent.restore=auto'
        '';
        SyslogIdentifier = "flux";
        ExecReload = "${cfg.package}/bin/flux config reload";
        Restart = "always";
        RestartSec = "30s";
        RestartPreventExitStatus = 42;
        SuccessExitStatus = 42;
        DynamicUser = true;
        User = "flux";
        Group = "flux";
        RuntimeDirectory = "flux";
        RuntimeDirectoryMode = "0755";
        StateDirectory = "flux";
        StateDirectoryMode = "0700";
        PermissionsStartOnly = true;
        ExecStartPre = [
          "${pkgs.systemd}/bin/loginctl enable-linger flux"
          "${pkgs.bash}/bin/bash -c 'systemctl start user@$(id -u flux).service'"
        ];
        Delegate="Yes";
      };
    };

    systemd.services.flux-prolog = {
      path =  [ cfg.package ];

      unitConfig = {
        Description = "Prolog for Flux job %I";
        CollectMode = "inactive-or-failed";
      };

      serviceConfig = {
        Type = "oneshot";
        EnvironmentFile= "-/run/flux-prolog@%I.env";
        ExecStart = "${cfg.package}/etc/flux/system/epilog";
        ExecStopPost = "-rm -f /run/flux-prolog@%I.env";
      };
    };

    systemd.services.flux-epilog = {
      path =  [ cfg.package ];

      unitConfig = {
        Description = "Epilog for Flux job %I";
        CollectMode = "inactive-or-failed";
      };

      serviceConfig = {
        Type = "oneshot";
        EnvironmentFile= "-/run/flux-epilog@%I.env";
        ExecStart = "${cfg.package}/etc/flux/system/epilog";
        ExecStopPost = "-rm -f /run/flux-epilog@%I.env";
      };
    };

    systemd.services.flux-housekeeping = {
      path =  [ cfg.package ];

      unitConfig = {
        Description = "Housekeeping for Flux job %I";
        CollectMode = "inactive-or-failed";
      };

      serviceConfig = {
        Type = "oneshot";
        EnvironmentFile= "-/run/flux-housekeeping@%I.env";
        ExecStart = "${cfg.package}/etc/flux/system/housekeeping";
        ExecStopPost = pkgs.writeShellScript "flux-housekeeping-stop-post.sh" ''
          if test "$SERVICE_RESULT" != "success"; then
            message="housekeeping@%I ''${SERVICE_RESULT:-failure}";
            if test "''${EXIT_CODE}''${EXIT_STATUS}"; then
              message="$message: $EXIT_CODE $EXIT_STATUS";
            fi;
            ${cfg.package}/bin/flux resource drain $(${cfg.package}/bin/flux getattr rank) $message;
          fi
        '';
      };
    };
  };
}
