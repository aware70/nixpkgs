# Start a two-broker instance in the build sandbox and run jobs through it.
# This exercises the joined package and its wrappers without a VM.
{
  lib,
  runCommand,
  util-linux,
  writeShellScript,
  writeText,
  mpi,
  flux-framework,
}:

let
  # Open MPI bootstraps through PMIx, so it needs the flux-pmix shell plugin.
  mpitest = runCommand "flux-smoke-test-mpi" { } ''
    mkdir -p $out/bin
    ${lib.getDev mpi}/bin/mpicc ${writeText "mpitest.c" ''
      #include <mpi.h>
      #include <stdio.h>
      int main (int argc, char **argv)
      {
          int rank, size;
          MPI_Init (&argc, &argv);
          MPI_Comm_rank (MPI_COMM_WORLD, &rank);
          MPI_Comm_size (MPI_COMM_WORLD, &size);
          MPI_Barrier (MPI_COMM_WORLD);
          if (rank == 0)
              printf ("size=%d\n", size);
          MPI_Finalize ();
          return 0;
      }
    ''} -o $out/bin/mpitest
  '';

  # flux-security only reads its configuration from /etc/flux/security, so
  # the test runs in a user and mount namespace with a private /etc.
  inner = writeShellScript "flux-smoke-test-inner" ''
    set -euo pipefail
    etc=$TMPDIR/etc
    mkdir -p $etc
    cp -r /etc/. $etc/
    mkdir -p $etc/flux/security/conf.d
    cat > $etc/flux/security/conf.d/sign.toml <<'TOML'
    [sign]
    max-ttl = 1209600
    default-type = "none"
    allowed-types = [ "none" ]
    TOML
    mount --bind $etc /etc

    flux start --test-size=2 ${writeShellScript "flux-smoke-test-instance" ''
      set -euxo pipefail
      flux version | grep -qE 'commands:[[:space:]]+${flux-framework.version}$'
      flux module list | grep -q sched-fluxion-qmanager
      flux module list | grep -q sched-fluxion-resource
      test "$(flux resource list -no '{nnodes}' -s free)" -eq 2
      test "$(flux run -N2 echo ok | wc -l)" -eq 2

      # rc1 points the job shell at the joined tree, here and in subinstances
      test "$(flux getattr conf.shell_pluginpath)" = ${flux-framework}/lib/flux/shell/plugins
      test "$(timeout 60 flux run -N1 flux start flux getattr conf.shell_pluginpath)" = ${flux-framework}/lib/flux/shell/plugins

      # The test brokers have different fake hostnames, so Open MPI needs
      # TCP over loopback rather than shared memory between the two ranks.
      timeout 60 flux run -N2 -n2 -o pmi=pmix \
        --env=OMPI_MCA_pml=ob1 --env=OMPI_MCA_btl=self,tcp --env=OMPI_MCA_btl_tcp_if_include=lo \
        ${mpitest}/bin/mpitest | grep -qx size=2

      # Run jobs before this: with mf_priority loaded, jobs from users
      # without an accounting bank are held.
      flux python -c 'import flux, fluxion'
      flux jobtap load ${flux-framework}/lib/flux/job-manager/plugins/mf_priority.so
      flux jobtap list | grep -q mf_priority
      flux account --help > /dev/null
    ''}
  '';
in
runCommand "flux-framework-smoke-test"
  {
    nativeBuildInputs = [
      flux-framework
      util-linux
    ];
  }
  ''
    export HOME=$TMPDIR
    unshare --map-root-user --mount ${inner}
    touch $out
  ''
