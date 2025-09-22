{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let

  cfg = config.services.flux-broker;
  opt = options.services.flux-broker;

  usedConfig = let
    toml = pkgs.formats.toml {};
    flux-config = {
      systemd = {
        enable = true;
      };

      exec = {
        imp = "/run/wrappers/bin/flux-imp";
        service = "sdexec";
        sdexec-properties = cfg.instanceConfig.exec.sdexec-properties;
      };

      access = {
        allow-guest-user = true;
        allow-root-owner = true;
      };

      bootstrap = cfg.instanceConfig.bootstrap;

      tbon = {
        tcp_user_timeout = "2m";
      };

      resource = cfg.instanceConfig.resource;

      kvs = {
        checkpoint-period = "30m";
        gc-threshold = 100000;
      };

      ingest = {
        validator = {
          plugins = [ "jobspec" "feasibility" ];
        };
      };

      job-manager = {
        inactive-age-limit = "7d";
      };

      police.jobspec.defaults.system.duration = "1m";
      policy.limits = {
        duration = "2h";
        job-size.max.nnodes = 8;
        job-size.max.ncores = 32;
      };

      sched-fluxion-qmanager.queue-policy = "easy";
      sched-fluxion-resource.match-policy = "lonodex";
      sched-fluxion-resource.match-format = "rv1_nosched";
    };
  in toml.generate "system.toml" flux-config;

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

      instanceConfig = {
        exec = {
          sdexec-properties = lib.mkOption {
            type = lib.types.attrs;
            description = ''
              sdexec specific properties for the flux instance.
            '';
            default = {
              MemoryMax = "95%";
            };
          };
        };

        bootstrap = {
          curve_cert = lib.mkOption {
            type = lib.types.path;
            description = ''
              Path to the flux CURVE certificate file for cluster authentication.
            '';
            default = "/etc/flux/system/curve.cert";
          };

          default_port = lib.mkOption {
            type = lib.types.port;
            description = ''
              Default port for flux communications.
            '';
            default = 8050;
          };

          default_bind = lib.mkOption {
            type = lib.types.str;
            description = ''
              Default device to use for incoming flux communications.
            '';
            default = "tcp://eth1:%p";
          };

          default_connect = lib.mkOption {
            type = lib.types.str;
            description = ''
              Default outgoing connection for flux communications.
            '';
            default = "tcp://%h:%p";
          };

          hosts = lib.mkOption {
            type = lib.types.listOf lib.types.attrs;
            description = ''
              Describe ranks of this flux cluster.
            '';
            defaultText = ''
              { host = config.networking.hostName; }
            '';
          };
        };

        resource = {
          norestrict = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Set true if flux broker is constrained to system cores by
              systemd or other site policy. This allows jobs to run on assigned cores.
            '';
          };
          exclude = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = ''
              Avoid scheduling jobs on certain nodes.
            '';
          };

          config = lib.mkOption {
            type = lib.types.listOf lib.types.attrs;
            defaultText = lib.options.literalExpression ''[
              {
                hosts = "host[1-2]";
                cores = "0-15";
              }
            ]'';
            description = ''
              Array of resource descriptions.
            '';
          };
        };
      };

      # TODO: support with flux-pam
      #pamSupport = lib.mkOption {
      #  type = lib.types.bool;
      #  default = false;
      #  description = ''
      #    Enable flux support for PAM (Pluggable Authentication Modules).
      #  '';
      #};

      maxTimeToLive = lib.mkOption {
        type = lib.types.int;
        default = 1209600; # 2 weeks
        description = ''
          Time for flux-broker job requests to remain valid.
          The default 1209600 is 2 weeks.
        '';
      };
    };
  };

  ###### implementation

  config = lib.mkIf cfg.enable {

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

    systemd.tmpfiles.settings = {
      "flux-security-config" = {
        "/etc/flux/security/conf.d/config.toml".f = {
            user = "root";
            group = "root";
            mode = "0644";
            argument = ''
              [sign]
              max-ttl = ${builtins.toString cfg.maxTimeToLive}
              default-type = "munge"
              allowed-types = [ "munge" ]
            '';
         };

         "/etc/flux/imp/conf.d/system.toml".f = {
           user = "root";
           group = "root";
           mode = "0644";
           argument = ''
             [exec]
             allowed-users = [ "flux" ]
             allowed-shells = [ "${cfg.package}/libexec/flux/flux-shell" ]
             # TODO: support with flux-pam
             pam-support = false
           '';
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
          --config-path=${usedConfig} \
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
