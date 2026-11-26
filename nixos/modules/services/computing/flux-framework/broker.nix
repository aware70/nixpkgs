{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  cfg = config.services.flux;
  acctCfg = config.services.flux-accounting;
  opt = options.services.flux;
  toml = pkgs.formats.toml { };
  systemToml = toml.generate "flux-system.toml" (
    lib.attrsets.filterAttrsRecursive (name: value: value != null) cfg.system.settings
  );
  signToml = toml.generate "flux-security-sign.toml" (
    lib.attrsets.filterAttrsRecursive (name: value: value != null) cfg.security.sign.settings
  );
  impToml = toml.generate "flux-security-imp.toml" (
    lib.attrsets.filterAttrsRecursive (name: value: value != null) cfg.security.imp.settings
  );

  perilogKinds = [
    "prolog"
    "epilog"
    "housekeeping"
  ];

  mkPerilogOptions = kind: when: {
    enable = lib.mkEnableOption ''
      the Flux job ${kind}. When enabled, the job manager runs it as root
      through `flux-imp run ${kind}` and a `flux-${kind}@` systemd unit,
      ${when}
    '';

    scripts = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      example = lib.literalExpression ''
        {
          "10-check-mounts" = pkgs.writeShellScript "check-mounts" "mountpoint -q /scratch";
        }
      '';
      description = ''
        Executable scripts to install in {file}`/etc/flux/system/${kind}.d`.
        They run in lexical order of their names.
      '';
    };
  };

  mkSystemScriptUnit = kind: description: {
    path = [
      cfg.package
      pkgs.coreutils
    ];
    unitConfig = {
      Description = "${description} for Flux job %I";
      CollectMode = "inactive-or-failed";
    };
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = "-/run/flux-${kind}@%I.env";
      ExecStart = "${cfg.package}/libexec/flux/flux-run-system-scripts ${kind}";
      ExecStopPost = "-${pkgs.coreutils}/bin/rm -f /run/flux-${kind}@%I.env";
    };
  };

  # Drain the node if housekeeping fails, as the upstream unit does.
  housekeepingStopPost = pkgs.writeShellScript "flux-housekeeping-stop-post" ''
    if test "$SERVICE_RESULT" != "success"; then
      message="housekeeping@$1 ''${SERVICE_RESULT:-failure}"
      if test "''${EXIT_CODE}''${EXIT_STATUS}"; then
        message="$message: $EXIT_CODE $EXIT_STATUS"
      fi
      ${cfg.package}/bin/flux resource drain "$(${cfg.package}/bin/flux getattr rank)" "$message"
    fi
  '';
in
{
  meta.maintainers = [ lib.maintainers.aware70 ];

  options = {
    services.flux = {
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

      package = lib.mkPackageOption pkgs "flux-framework" { };

      system.settings = lib.mkOption {
        type = lib.types.submodule (import ./system-settings.nix);
        default = { };
        description = ''
          Flux system configuration.
          Documented at: https://flux-framework.readthedocs.io/projects/flux-core/en/stable/man5/flux-config.html
        '';
      };

      security.sign.settings = lib.mkOption {
        type = lib.types.submodule (import ./security-sign-settings.nix);
        default = { };
        description = ''
          Flux security signing configuration. This attribute set is converted into a TOML file.
          Documented at: https://flux-framework.readthedocs.io/projects/flux-security/en/latest/man5/flux-config-security-sign.html
        '';
      };

      security.imp.settings = lib.mkOption {
        type = lib.types.submodule (import ./security-imp-settings.nix);
        default = { };
        description = ''
          Flux security IMP configuration. This attribute set is converted into a TOML file.
          Documented at: https://flux-framework.readthedocs.io/projects/flux-security/en/latest/man5/flux-config-security-imp.html
        '';
      };
    };

    services.flux-accounting = {
      enable = lib.mkEnableOption "flux-accounting";
    };

    services.flux.prolog = mkPerilogOptions "prolog" "before each job starts, on rank 0";
    services.flux.epilog = mkPerilogOptions "epilog" "after each job finishes, on rank 0";
    services.flux.housekeeping = mkPerilogOptions "housekeeping" "on each node after a job releases it";
  };

  ###### implementation

  config = lib.mkIf cfg.enable {

    services.flux.system.settings = lib.mkMerge [
      {
        systemd.enable = lib.mkForce true;
        exec = {
          imp = lib.mkForce "/run/wrappers/bin/flux-imp";
          job-shell = lib.mkForce "/run/wrappers/bin/flux-shell";
          service = lib.mkForce "sdexec";
        };
      }
      (lib.mkIf acctCfg.enable {
        # Multi-factor priority plugin from flux-accounting. Jobs from users
        # without a bank association are rejected.
        job-manager.plugins = [
          { load = "${cfg.package}/lib/flux/job-manager/plugins/mf_priority.so"; }
        ];
      })
      (lib.mkIf (cfg.prolog.enable || cfg.epilog.enable) {
        job-manager.plugins = [ { load = "${cfg.package}/lib/flux/job-manager/plugins/perilog.so"; } ];
      })
      # An empty table enables each one with its default `flux-imp run <kind>` command.
      (lib.mkIf cfg.prolog.enable { job-manager.prolog = { }; })
      (lib.mkIf cfg.epilog.enable { job-manager.epilog = { }; })
      (lib.mkIf cfg.housekeeping.enable { job-manager.housekeeping = { }; })
    ];

    services.flux.security.imp.settings = {
      exec.allowed-users = lib.mkForce [ "flux" ];
      exec.allowed-shells = lib.mkForce [ "/run/wrappers/bin/flux-shell" ];
      run = lib.listToAttrs (
        map (kind: {
          name = kind;
          value = {
            allowed-users = [ "flux" ];
            # Starts the flux-<kind>@JOBID unit and waits for it
            path = "${cfg.package}/libexec/flux/cmd/flux-run-${kind}";
          };
        }) (lib.filter (kind: cfg.${kind}.enable) perilogKinds)
      );
    };

    environment.etc = lib.mkMerge (
      map (
        kind:
        lib.mapAttrs' (
          name: script: lib.nameValuePair "flux/system/${kind}.d/${name}" { source = script; }
        ) cfg.${kind}.scripts
      ) perilogKinds
    );

    environment.systemPackages = [ cfg.package ];

    services.munge.enable = lib.mkDefault true;

    users.users.flux = {
      name = "flux";
      group = "flux";
      uid = config.ids.uids.flux;
      isSystemUser = true;
    };

    users.groups.flux.gid = config.ids.gids.flux;

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

    # Security relevant configuration must exist in a directory controlled by root:
    # https://flux-framework.readthedocs.io/projects/flux-security/en/latest/man5/flux-config-security.html
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

    systemd.services.flux = {
      # systemd sets SHELL from the flux user's login shell (nologin), and
      # Flux runs rc scripts and subcommands through $SHELL.
      environment.SHELL = "${pkgs.bash}/bin/bash";
      path = with pkgs; [
        cfg.package
        coreutils
        bash
        systemd
      ];
      wantedBy = [ "multi-user.target" ];
      wants = [
        "systemd-tmpfiles-clean.service"
        "munge.service"
      ];

      serviceConfig = {
        Type = "notify";
        NotifyAccess = "main";
        TimeoutStopSec = 90;
        KillMode = "mixed";
        ExecStart = pkgs.writeShellScript "start-flux-broker.sh" ''
          export XDG_RUNTIME_DIR=/run/user/$UID
          export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$UID/bus
          exec ${cfg.package}/bin/flux broker \
            --config-path=${systemToml} \
            -Scron.directory=${cfg.package}/etc/flux/system/cron.d \
            -Srundir=/run/flux \
            -Sstatedir=''${STATE_DIRECTORY:-/var/lib/flux} \
            -Slocal-uri=local:///run/flux/local \
            -Slog-stderr-level=6 \
            -Slog-forward-level=-1 \
            -Slog-stderr-mode=local \
            -Sbroker.rc2_none \
            -Sbroker.quorum=1 \
            -Sbroker.quorum-warn=none \
            -Sbroker.cleanup-timeout=45 \
            -Sbroker.shutdown-timeout=5m \
            -Sbroker.exit-norestart=42 \
            -Sbroker.sd-notify=1 \
            -Sbroker.sd-stop-timeout=90 \
            -Sbroker.module-nopanic=1 \
            -Scontent.dump=auto \
            -Scontent.restore=auto
        '';
        SyslogIdentifier = "flux";
        ExecReload = "${cfg.package}/bin/flux config reload --follower-noop";
        Restart = "always";
        RestartSec = "30s";
        RestartPreventExitStatus = 42;
        SuccessExitStatus = 42;
        User = "flux";
        Group = "flux";
        RuntimeDirectory = "flux";
        RuntimeDirectoryMode = "0755";
        StateDirectory = "flux";
        StateDirectoryMode = "0700";
        PermissionsStartOnly = true;
        ExecStartPre = [
          "${pkgs.systemd}/bin/loginctl enable-linger flux"
          "${pkgs.systemd}/bin/systemctl start user@${builtins.toString config.ids.uids.flux}.service"
        ];
        Delegate = "Yes";
      };
    };

    systemd.services.flux-accounting = lib.mkIf acctCfg.enable {
      # systemd sets SHELL from the flux user's login shell (nologin), and
      # Flux runs rc scripts and subcommands through $SHELL.
      environment.SHELL = "${pkgs.bash}/bin/bash";
      path = with pkgs; [
        cfg.package
        coreutils
        bash
        systemd
      ];
      bindsTo = [ "flux.service" ];
      after = [ "flux.service" ];
      wantedBy = [ "flux.service" ];

      serviceConfig = {
        TimeoutStopSec = 90;
        KillMode = "mixed";
        ExecStartPre = [
          "${pkgs.bash}/bin/bash -c 'test -f /var/lib/flux/FluxAccounting.db || ${cfg.package}/bin/flux account create-db'"
        ];
        ExecStart = "${cfg.package}/bin/flux account-service";
        SyslogIdentifier = "flux-accounting";
        StateDirectory = "flux";
        StateDirectoryMode = "0700";
        Restart = "always";
        RestartSec = "10s";
        User = "flux";
        Group = "flux";
      };
    };

    # Templated units started by the sdexec-based job prolog, epilog and
    # housekeeping, mirroring the units shipped with flux-core.
    systemd.services."flux-prolog@" = mkSystemScriptUnit "prolog" "Prolog";
    systemd.services."flux-epilog@" = mkSystemScriptUnit "epilog" "Epilog";
    systemd.services."flux-housekeeping@" =
      lib.recursiveUpdate (mkSystemScriptUnit "housekeeping" "Housekeeping")
        {
          serviceConfig.ExecStopPost = [
            "-${pkgs.coreutils}/bin/rm -f /run/flux-housekeeping@%I.env"
            "${housekeepingStopPost} %I"
          ];
        };
  };
}
