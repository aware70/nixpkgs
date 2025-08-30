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

  instanceConfig = pkgs.writeTextDir "flux.toml" ''
    [systemd]
    enable = true

    [exec]
    imp = "${cfg.package}/libexec/flux-imp"
    service = "sdexec"

    [exec.sdexec-properties]
    MemoryMax = "95%"

    [access]
    allow-guest-user = true
    allow-root-owner = true

    [bootstrap]
    curve_cert = "/etc/flux/system/curve.cert"
    default_port = 8050
    default_bind = "tcp://eth1:%p"
    default_connect = "tcp://%h:%p"

    hosts = [
      { host = "control" },
      { host = "node[1-3]" },
    ]

    [tbon]
    tcp_user_timeout = "2m"

    [resource]
    #norestrict = true
    #exclude = "test[1-2]"

#    [[resource.config]]
#    hosts = "test[1-15]"
#    cores = "0-7"
#    gpus = "0"
#
#    [[resource.config]]
#    hosts = "test16"
#    cores = "0-63"
#    gpus = "0-1"
#    properties = ["fatnode"]

    [kvs]
    checkpoint-period = "30m"
    gc-threshold = 100000

    [ingest.validator]
    plugins = [ "jobspec", "feasibility" ]

    [job-manager]
    inactive-age-limit = "7d"

    [policy.jobspec.defaults.system]
    duration = "1m"

    [policy.limits]
    duration = "2h"
    job-size.max.nnodes = 8
    job-size.max.ncores = 32

    [sched-fluxion-qmanager]
    queue-policy = "easy"
    [sched-fluxion-resource]
    match-policy = "lonodex"
    match-format = "rv1_nosched"
  '';
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

      pamSupport = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Enable flux support for PAM (Pluggable Authentication Modules).
        '';
      };

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

    systemd.tmpfiles.settings = {
      "flux-security-config" = {
        "/etc/flux/security/conf.d/config.toml".f = {
            user = "root";
            group = "root";
            mode = "0500";
            argument = ''
              [sign]
              max-ttl = ${lib.toString cfg.maxTimeToLive}
              default-type = "munge"
              allowed-types = [ "munge" ]
            '';
         };

         "/etc/flux/imp/conf.d/system.toml".f = {
           user = "root";
           group = "root";
           mode = "0500";
           argument = ''
             [exec]
             allowed-users = [ "flux" ]
             allowed-shells = [ "${cfg.package}/bin/flux-shell" ]
             # pam-support = ${lib.boolToString cfg.pamSupport}
             pam-support = false
           '';
         };
      };
    };

    systemd.services.flux-broker = {
      path = with pkgs; [ cfg.package coreutils bash systemd ];
      wantedBy = [ "multi-user.target" ];
      wants = [
        "network-online.target"
        "systemd-tmpfiles-clean.service"
      ];
      after = [
        "systemd-tmpfiles-clean.service"
        "munge.service"
        "network-online.target"
        "remote-fs.target"
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
          --config-path=${instanceConfig} \
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
