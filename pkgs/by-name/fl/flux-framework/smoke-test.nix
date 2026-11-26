# Start a two-broker instance in the build sandbox and run jobs through it.
# This exercises the joined package and its wrappers without a VM.
{
  runCommand,
  util-linux,
  writeShellScript,
  flux-framework,
}:

let
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
