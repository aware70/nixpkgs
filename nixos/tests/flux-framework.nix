{ lib, pkgs, ... }:
let
  fluxconfig = {
    users.users.alice = {
      isNormalUser = true;
    };
    # A user with no flux-accounting bank, whose jobs must be rejected
    users.users.bob = {
      isNormalUser = true;
    };
    services.flux = {
      enable = true;
      housekeeping = {
        enable = true;
        scripts."10-marker" = markerScript "housekeeping";
      };
      system.settings = {
        bootstrap = {
          curve_cert = "/etc/flux/system/curve.cert";
          hosts = [
            { host = "control"; }
            { host = "node[1-3]"; }
          ];
        };

        resource.config = [
          {
            hosts = "control,node[1-3]";
            cores = "0-1";
          }
        ];

        access = {
          allow-guest-user = true;
          allow-root-owner = true;
        };
      };
    };
    environment.systemPackages = [ mpitest ];
    networking.firewall.enable = false;
    networking.firewall.allowedTCPPorts = [ 8050 ];
    virtualisation.vlans = [ 1 ];
    virtualisation.cores = 2;
    systemd.tmpfiles.settings = {
      "flux-test-config" = {
        "/etc/munge/munge.key"."f" = {
          user = "munge";
          group = "munge";
          mode = "0400";
          argument = "mungeverryweakkeybuteasytointegrationtest";
        };
        "/etc/flux/system/curve.cert"."f" = {
          user = "flux";
          group = "flux";
          mode = "0500";
          argument = ''
            metadata
                name = "testing-only"
            curve
                public-key = "6+o?T()#h1[t)#ILoc)!gao<PQdxdlDLP.Ceb^a^"
                secret-key = "9(vfLw4Yk15cG(!RE.*>{WdSe@pjO[B-xvRH3--!"
          '';
        };
      };
    };
  };

  # Records the job id, so the test can see which scripts ran for which job
  markerScript =
    kind:
    pkgs.writeShellScript "flux-test-${kind}" ''
      echo "$FLUX_JOB_ID" >> /run/flux-test-${kind}
    '';

  mpitest =
    let
      mpitestC = pkgs.writeText "mpitest.c" ''
        #include <stdio.h>
        #include <stdlib.h>
        #include <mpi.h>

        int
        main (int argc, char *argv[])
        {
          int rank, size, length;
          char name[512];

          MPI_Init (&argc, &argv);
          MPI_Comm_rank (MPI_COMM_WORLD, &rank);
          MPI_Comm_size (MPI_COMM_WORLD, &size);
          MPI_Get_processor_name (name, &length);

          if ( rank == 0 ) printf("size=%d\n", size);

          printf ("%s: hello world from process %d of %d\n", name, rank, size);

          MPI_Finalize ();

          return EXIT_SUCCESS;
        }
      '';
    in
    pkgs.runCommand "mpitest" { } ''
      mkdir -p $out/bin
      ${lib.getDev pkgs.mpich}/bin/mpicc ${mpitestC} -o $out/bin/mpitest
    '';
in
{
  name = "flux-framework";

  nodes =
    let
      computeNode = {
        imports = [ fluxconfig ];
      };
    in
    {
      control = {
        imports = [ fluxconfig ];
        services.flux-accounting.enable = true;
        services.flux.prolog = {
          enable = true;
          scripts."10-marker" = markerScript "prolog";
        };
        services.flux.epilog = {
          enable = true;
          scripts."10-marker" = markerScript "epilog";
        };
      };

      node1 = computeNode;
      node2 = computeNode;
      node3 = computeNode;
    };

  testScript = ''
    with subtest("services_up"):
        control.wait_for_unit("flux.service")
        control.wait_for_unit("flux-accounting.service")

    with subtest("correct_ranks"):
        control.wait_for_unit("default.target")
        control.succeed("flux getattr rank | grep 0")
        control.succeed("flux getattr tbon.level | grep 0")
        for r, node in enumerate([node1, node2, node3]):
          node.wait_for_unit("default.target")
          node.succeed(f"flux getattr rank | grep {r+1}")
          node.succeed("flux getattr tbon.level | grep 1")

    with subtest("can_restart_flux_broker"):
        for r, node in enumerate([node1, node2, node3]):
            node.succeed("systemctl restart flux")
            node.wait_for_unit("flux")
            node.succeed(f"flux getattr rank | grep {r+1}")
            node.succeed("flux getattr tbon.level | grep 1")

    # Test that the cluster works and can distribute jobs

    with subtest("run_distributed_command"):
        # Execute `hostname` on all nodes
        control.succeed("flux exec hostname | sort | uniq | wc -l | xargs test 4 -eq")

    # The flux user has no login shell, so use runuser rather than `su -`
    def as_flux(cmd):
        return control.succeed(f"runuser -u flux -- {cmd}")

    def as_alice(cmd):
        return control.succeed(f"su - alice -c '{cmd}'")

    with subtest("can_configure_accounting_db"):
        as_flux("flux account add-bank root 1")
        as_flux("flux account add-bank --parent-bank=root sub_bank_A 1")
        as_flux("flux account add-user --username=alice --bank=sub_bank_A")
        print(as_flux("flux account view-bank root --tree"))
        # Push the bank and user data to the mf_priority plugin
        as_flux("flux account-priority-update")
        control.succeed("flux jobtap list | grep mf_priority")

    with subtest("run_distributed_job"):
        # Run on all nodes as a normal user, charged to their bank
        as_alice("flux run -N4 --setattr=bank=sub_bank_A hostname")

    with subtest("jobs_run_as_submitting_user"):
        # Tasks are started through the setuid flux-imp on every node
        out = as_alice("flux run -N4 id -un")
        assert out.split() == ["alice"] * 4, f"unexpected users: {out!r}"

    with subtest("prolog_epilog_housekeeping_run"):
        jobid = as_alice("flux submit -N4 true").strip()
        as_alice(f"flux job wait-event -t 60 {jobid} clean")
        # The units see the job id in plain f58 form
        f58 = as_alice(f"flux job id --to=f58plain {jobid}").strip()
        try:
            for kind in ["prolog", "epilog"]:
                control.wait_until_succeeds(f"grep -qx {f58} /run/flux-test-{kind}", timeout=60)
            for node in [control, node1, node2, node3]:
                node.wait_until_succeeds(f"grep -qx {f58} /run/flux-test-housekeeping", timeout=60)
        except Exception:
            # Show how far the prolog/epilog/housekeeping chain got
            print(control.execute(f"flux job eventlog {jobid}")[1])
            print(control.execute("ls -l /etc/flux/system/*.d /run/flux-test-* /run/flux-*.env")[1])
            print(control.execute("cat /etc/flux/imp/conf.d/imp.toml")[1])
            print(control.execute(
                "journalctl --no-pager -o cat -u flux -u 'flux-prolog@*' -u 'flux-epilog@*'"
                " -u 'flux-housekeeping@*' | grep -iE 'prolog|epilog|housekeeping|imp' | tail -n 80"
            )[1])
            raise

    with subtest("check_flux_accounting"):
        # The jobs above should appear in the accounting database
        control.wait_until_succeeds(
            "runuser -u flux -- flux account-fetch-job-records"
            " && runuser -u flux -- flux account view-job-records --user alice | grep -q alice",
            timeout=60,
        )

    with subtest("accounting_rejects_user_without_bank"):
        control.fail("su - bob -c 'flux run true'")

    with subtest("accounting_enforces_max_active_jobs"):
        as_flux("flux account edit-user alice --max-active-jobs=1")
        as_flux("flux account-priority-update")
        first = as_alice("flux submit sleep 300").strip()
        control.fail("su - alice -c 'flux submit true'")
        as_alice(f"flux cancel {first}")
        as_alice(f"flux job wait-event -t 60 {first} clean")
        as_flux("flux account edit-user alice --max-active-jobs=1000")
        as_flux("flux account-priority-update")

    with subtest("run_mpi_job"):
        # MPICH talks to the PMI server in the Flux job shell
        out = as_alice("flux run -N4 -n4 mpitest")
        assert "size=4" in out, out

    with subtest("can_reload_config"):
        control.succeed("systemctl reload flux")
        control.succeed("flux getattr rank | grep 0")

    with subtest("broker_stops_cleanly"):
        # The broker should shut down well before the 90 s stop timeout
        node3.succeed("timeout 30 systemctl stop flux")
        node3.succeed("systemctl start flux")
        node3.wait_for_unit("flux")
        node3.wait_until_succeeds("flux getattr rank | grep 3", timeout=60)

    with subtest("control_restart_keeps_job_history"):
        jobid = as_alice("flux submit true").strip()
        as_alice(f"flux job wait-event -t 60 {jobid} clean")
        control.succeed("systemctl restart flux")
        control.wait_for_unit("flux")
        control.wait_until_succeeds(f"flux jobs -a -no {{id}} | grep -q {jobid}", timeout=120)
        # The compute nodes rejoin and can run jobs again
        control.wait_until_succeeds("su - alice -c 'flux run -N4 true'", timeout=120)

  '';
}
