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
  toml = pkgs.formats.toml {};
  systemToml = toml.generate "flux-system.toml"
    (lib.attrsets.filterAttrsRecursive (name: value: value != null) cfg.system.settings);
  signToml = toml.generate "flux-security-sign.toml" 
    (lib.attrsets.filterAttrsRecursive (name: value: value != null) cfg.security.sign.settings);
  impToml = toml.generate "flux-security-imp.toml"
    (lib.attrsets.filterAttrsRecursive (name: value: value != null) cfg.security.imp.settings);
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
        type = lib.types.submodule (import ./system-settings.nix);
        default = {};
        description = ''
          Flux system configuration.
          Documented at: https://flux-framework.readthedocs.io/projects/flux-core/en/stable/man5/flux-config.html
        '';
      };

      security.sign.settings = lib.mkOption {
        type = lib.types.submodule (import ./security-sign-settings.nix);
        default = {};
        description = ''
          Flux security signing configuration. This attribute set is converted into a TOML file.
          Documented at: https://flux-framework.readthedocs.io/projects/flux-security/en/latest/man5/flux-config-security-sign.html
        '';
      };

      security.imp.settings = lib.mkOption {
        type = lib.types.submodule (import ./security-imp-settings.nix);
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
