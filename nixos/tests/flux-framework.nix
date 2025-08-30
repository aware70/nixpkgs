{ lib, pkgs, ... }:
let
  fluxconfig = {
    services.flux-broker = {
      enable = true;
    };
    environment.systemPackages = [ mpitest ];
    networking.firewall.enable = false;
    networking.firewall.allowedTCPPorts = [
      8050
    ];
    virtualisation.vlans = [ 1 ];
    systemd.tmpfiles.settings = {
      "flux-test-config" = {
        "/etc/munge/munge.key"."f" = {
          user = "munge";
          group = "munge";
          mode = "0400";
          argument = "mungeverryweakkeybuteasytointegratoinatest";
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
      ${lib.getDev pkgs.mpi}/bin/mpicc ${mpitestC} -o $out/bin/mpitest
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
      };

      node1 = computeNode;
      node2 = computeNode;
      node3 = computeNode;
    };

  testScript = ''
    with subtest("correct_ranks"):
        control.wait_for_unit("default.target")
        control.succeed("flux getattr rank | grep 0")
        for r, node in enumerate([node1, node2, node3]):
          node.wait_for_unit("default.target")
          node.succeed(f"flux getattr rank | grep {r+1}")

    with subtest("can_restart_flux_broker"):
        for r, node in enumerate([node1, node2, node3]):
            node.succeed("systemctl restart flux-broker.service")
            node.wait_for_unit("flux-broker")
            node.succeed(f"flux getattr rank | grep {r+1}")

    ## Test that the cluster works and can distribute jobs;

    #with subtest("run_distributed_command"):
    #    # Run `hostname` on 3 nodes of the partition (so on all the 3 nodes).
    #    # The output must contain the 3 different names
    #    submit.succeed("srun -N 3 hostname | sort | uniq | wc -l | xargs test 3 -eq")

    #    with subtest("check_slurm_dbd"):
    #        # find the srun job from above in the database
    #        control.succeed("sleep 5")
    #        control.succeed("sacct | grep hostname")

    #with subtest("run_PMIx_mpitest"):
    #    submit.succeed("srun -N 3 --mpi=pmix mpitest | grep size=3")
  '';
}
