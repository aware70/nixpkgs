{
  fetchFromGitHub,
  stdenv,
  lib,
  cmake,
  autoreconfHook,
  pkg-config,
  lua,
  bash,
  getopt,
  coreutils,
  python3,
  python3Packages,
  hwloc,
  openmpi,
  jansson,
  makeWrapper,
  substitute,
  mpiCheckPhaseHook,
  ncurses,
  lz4,
  libarchive,
  libuuid,
  munge,
  git,
  libsodium,
  perl,
  jq,
  sqlite,
  systemd,
  zeromq,
  checkValgrind ? false, valgrind
} : let
  sched-version = "0.38.0";
  security-version = "0.11.0";
  core-version = "0.66.0";

  patchCoreUtils = lib.escapeShellArgs [
    "./t/valgrind/workload.d/job-list"
    "./t/valgrind/workload.d/job-info"
    "./t/valgrind/workload.d/job-wait"
    "./etc/rc1"
    "./etc/rc1.d/02-cron"
    "./etc/rc3"
  ];

  flux-python = python3.withPackages (ps: with ps; [
    sphinx
    packaging
    distutils
    setuptools
    cffi
    pyyaml
    ply
  ]);

  flux-security = stdenv.mkDerivation {
    pname = "flux-security";
    version = security-version;
    src = fetchFromGitHub {
      owner = "flux-framework";
      repo = "flux-security";
      rev  = "refs/tags/v${security-version}";
      sha256 = "sha256-F/7E/tVLzkQgVtafonfCQHQGOcHH9QOccjnPK/SItI0=";
    };

    nativeBuildInputs = [
      autoreconfHook
      pkg-config
      git
    ];

    buildInputs = [
      coreutils
      jansson
      libuuid
      libsodium
      flux-python
      munge
    ];

    checkInputs = [
      perl
    ];

    postPatch = ''
      substituteInPlace ./configure.ac \
        --replace-fail 'git describe --always' 'echo ${security-version}'

      substituteInPlace ./t/t0000-sharness.t \
        --replace-fail '/bin/true' 'true'

      patchShebangs .
    '';

# SEGFAULT when performing tests in sandbox
#    doCheck = true;
  };

  flux-core = stdenv.mkDerivation {
    pname = "flux-core";
    version = core-version;
    src = fetchFromGitHub {
      owner = "flux-framework";
      repo = "flux-core";
      rev  = "refs/tags/v${core-version}";
      sha256 = "sha256-bYMgdswiYI0e9O4urYw3/inq9LJ/Qh4jPfzI5E3ZCEM=";
    };

    FLUX_VERSION=core-version;
    FLUX_ENABLE_SYSTEM_TESTS=lib.boolToString false;
    FLUX_ENABLE_VALGRIND_TEST=lib.boolToString checkValgrind;

    nativeBuildInputs = [
      autoreconfHook
      pkg-config
    ];

    buildInputs = [
      (lua.withPackages (ps: [
        ps.luaposix
      ]))
      flux-security
      flux-python
      lz4
      hwloc
      jansson
      jq
      libarchive
      libuuid
      openmpi
      valgrind
      ncurses
      sqlite
      systemd
      zeromq
      coreutils
      bash
    ];

    patches = [
      ./add-nixos-system-paths.patch
      ./add-ibm-spectrum-check-in-mpi-test.patch
      ./fix-grep-test-with-ansi-escape.patch
#     ./patch-etc-files.patch
    ];

    postPatch = ''
      doPatch() {
        substituteInPlace $@ \
          --replace-quiet '/bin/false' '${coreutils}/bin/false' \
          --replace-quiet '/bin/true' '${coreutils}/bin/true' \
          --replace-quiet '/bin/ls' '${coreutils}/bin/ls' \
          --replace-quiet '/bin/cat' '${coreutils}/bin/cat' \
          --replace-quiet '/bin/sleep' '${coreutils}/bin/sleep' \
          --replace-quiet '/bin/echo' '${coreutils}/bin/echo' \
          --replace-quiet '/bin/bash' '${bash}/bin/bash' \
          --replace-quiet '/usr/bin/getopt' '${getopt}/bin/getopt' \
          --replace-quiet '@@flux@@' $out/bin/flux
      }

      for f in ${patchCoreUtils}; do
        doPatch $f
      done

      find . -name '*.t' -o -name '*.sh' -o -name '*.py' -o -name '*.c' | while IFS="" read -r FILE; do
        doPatch $FILE
      done

      # Must do this after substitutions
      patchShebangs ./t
      patchShebangs ./config
      patchShebangs ./etc
      patchShebangs ./doc/test/spellcheck
      patchShebangs ./src/cmd
      patchShebangs ./src/test/scaling
      patchShebangs ./src/test/*.sh
    '';

    configureFlags = [
      "--with-flux-security"
    ];

    doCheck = true;

    checkPhase = ''
      make check -j $NIX_BUILD_CORES
    '';

    nativeCheckInputs = [
      mpiCheckPhaseHook
    ];
  };

in flux-core

#in stdenv.mkDerivation {
#  pname = "flux-sched";
#  version = sched-version;
#
#  src = fetchFromGitHub {
#      owner = "flux-framework";
#      repo = "flux-sched";
#      rev  = "refs/tags/v${sched-version}";
#      sha256 = "sha256-ULu5jh2M1osumlxjbDJrKKEn3FvJLQdSwuK8ajLqGXc=";
#  };
#
#  nativeBuildInputs = [
#    cmake
#    pkg-config
#  ];
#
#  buildInputs = [
#    flux-core
#  ];
#}
