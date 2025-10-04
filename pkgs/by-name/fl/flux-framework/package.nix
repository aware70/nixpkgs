{
  pkgs,
  fetchFromGitHub,
  stdenv,
  lib,
  cmake,
  aspellWithDicts,
  autoreconfHook,
  boost,
  pkg-config,
  lua,
  libedit,
  bash,
  getopt,
  coreutils,
  gnugrep,
  python3,
  python3Packages,
  hwloc,
  openmpi,
  jansson,
  makeWrapper,
  substitute,
  mpiCheckPhaseHook,
  ncurses,
  nettools,
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
  yaml-cpp,
  zeromq,
  checkValgrind ? false, valgrind
} : let

  patchCoreUtils = lib.escapeShellArgs [
    "./t/valgrind/workload.d/job-list"
    "./t/valgrind/workload.d/job-info"
    "./t/valgrind/workload.d/job-wait"
  ];

  flux-python = python3.withPackages (ps: with ps; [
    sphinx
    packaging
    distutils
    setuptools
    cffi
    pyyaml
    ply
    jsonschema
  ]);

  flux-security = stdenv.mkDerivation (finalAttrs: {
    pname = "flux-security";
    version = "0.14.0";
    src = fetchFromGitHub {
      owner = "flux-framework";
      repo = "flux-security";
      rev  = "refs/tags/v${finalAttrs.version}";
      sha256 = "sha256-f1LTmjq9PnoCDcc6O8XHFzRoLTtqb8vbvLzTuPgeJao=";
    };

    configureFlags = [
      "--sysconfdir=/etc"
    ];

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
      (aspellWithDicts (dicts: [
        dicts.en
      ]))
    ];

    postPatch = ''
      substituteInPlace ./configure.ac \
        --replace-fail 'git describe --always' 'echo ${finalAttrs.version}'

      # Must defer installation of 'etc' to global location
      substituteInPlace ./Makefile.am \
        --replace-fail 'SUBDIRS = src doc etc t' 'SUBDIRS = src doc t'

      substituteInPlace ./t/t0000-sharness.t \
        --replace-fail '/bin/true' 'true'

      patchShebangs .
    '';

    # FIXME: SKIP_TESTS from sharness doesn't appear to work
    #checkInputs = [
    #  perl
    #  gnugrep
    #];
    doCheck = false;
    # env.SKIP_TESTS="t1000.3";
    # checkPhase = ''
    #   make check
    # '';
  });

  flux-core = stdenv.mkDerivation (finalAttrs: {
    pname = "flux-core";
    version = "0.78.0";
    src = fetchFromGitHub {
      owner = "flux-framework";
      repo = "flux-core";
      rev  = "refs/tags/v${finalAttrs.version}";
      sha256 = "sha256-rQIebCq5c+4YNh5iwmoG7YEaV5lQZCXdxKizHdo8jns=";
    };

    env.FLUX_VERSION = finalAttrs.version;
    env.FLUX_ENABLE_SYSTEM_TESTS = lib.boolToString false;
    env.FLUX_ENABLE_VALGRIND_TEST = lib.boolToString checkValgrind;

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
      jq
      libarchive
      openmpi
      valgrind
      ncurses
      sqlite
      systemd
      zeromq
      coreutils
      bash
    ];

    propagatedBuildInputs = [
      hwloc
      jansson
      libuuid
    ];

    patches = [
      ./add-nixos-system-paths.patch
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

      find . -name '*.sh' -o -name '*.py' -o -name '*.c' | while IFS="" read -r FILE; do
        doPatch $FILE
      done

      doPatch ./etc/*.in

      # Must do this after substitutions
      patchShebangs ./config
      patchShebangs ./etc
      patchShebangs ./doc/test/spellcheck
      patchShebangs ./src/cmd
      patchShebangs ./src/test/scaling
      patchShebangs ./src/test/*.sh
    '';

    configureFlags = [
      "--with-flux-security"
      "--with-systemdsystemunitdir=$(out)/etc/systemd/system"
      "--sysconfdir=${placeholder "out"}/etc"
    ];

    installFlags = [
      "sysconfdir=${placeholder "out"}/etc"
    ];

    # TODO: Many tests dependent on global env or network
    #env.SKIP_TESTS = lib.escapeShellArgs [
    #  "test_channel.4"
    #  "test_channel.t.4"
    #];
    #doCheck = true;
    #checkPhase = "make check";
    #nativeCheckInputs = [
    #  mpiCheckPhaseHook
    #];
  });

  flux-sched = stdenv.mkDerivation (finalAttrs: {
    pname = "flux-sched";
    version = "0.47.0";
    src = fetchFromGitHub {
      owner = "flux-framework";
      repo = "flux-sched";
      rev  = "refs/tags/v${finalAttrs.version}";
      sha256 = "sha256-wvZaVxE1DBbI3K1318gB3Nasd9y7aPiOiuKd3c7ZGCU=";
    };

    nativeBuildInputs = [
      cmake
      pkg-config
    ];

    env.FLUX_SCHED_VERSION = finalAttrs.version;

    postPatch = ''
      patchShebangs ./etc/rc1.d/*
      patchShebangs ./etc/rc3.d/*
      patchShebangs ./t/rc/rc1-job
      patchShebangs ./t/rc/rc3-job

      substituteInPlace ./resource/utilities/test/resource-bench.sh \
        --replace-fail '/usr/bin/env' '${coreutils}/bin/env'

      find . -name '*.t' -o -name '*.sh' -o -name '*.py' -o -name '*.c' -o -name '*.lua' | while IFS="" read -r FILE; do
        patchShebangs $FILE
        substituteInPlace $FILE \
          --replace-quiet '/bin/true' '${coreutils}/bin/true' \
          --replace-quiet '/bin/false' '${coreutils}/bin/false'
      done
    '';

    buildInputs = [
      flux-core
      flux-python
      yaml-cpp
      libedit
      boost
      valgrind
      (lua.withPackages (ps: [
        ps.luaposix
      ]))
      nettools
    ];

    # Tests have circular dependency on configured flux-security
    doCheck = false;
    #checkPhase = "make check";
    #checkInputs = [
    #  jq
    #];
  });

  flux-accounting = stdenv.mkDerivation (finalAttrs: {
    pname = "flux-accounting";
    version = "0.51.0";
    src = fetchFromGitHub {
      owner = "flux-framework";
      repo = "flux-accounting";
      rev  = "refs/tags/v${finalAttrs.version}";
      sha256 = "sha256-/MqvdW2GI68IYq+4yQDk/XK1HqDE5oRMFGrGFJDGK1E=";
    };

    nativeBuildInputs = [
      pkg-config
      autoreconfHook
    ];

    configureFlags = [
      "--localstatedir=/var"
    ];

    buildInputs = [
      flux-core
      flux-python
      sqlite
      jansson
    ];

    postPatch = ''
      substituteInPlace ./configure.ac \
        --replace-fail 'git describe --always' 'echo ${finalAttrs.version}'
    '';
  });
in
  pkgs.symlinkJoin {
    name = "flux-framework";
    paths = [
      flux-sched
      flux-core
      flux-security
      flux-accounting
    ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/flux" \
        --set FLUX_LUA_PATH_PREPEND "$out/share/lua/5.2/?.lua" \
        --set FLUX_LUA_CPATH_PREPEND "$out/lib/lua/5.2/?.lua" \
        --set FLUX_EXEC_PATH "$out/libexec/flux/cmd" \
        --set FLUX_PYTHONPATH_PREPEND "$out/lib/flux/python3.13" \
        --set FLUX_CONNECTOR_PATH "$out/lib/flux/connectors" \
        --set FLUX_RC_EXTRA "$out/etc/flux" \
        --set FLUX_MODULE_PATH "$out/lib/flux/modules" \
        --set FLUX_MODPROBE_PATH_APPEND="$out/etc/flux/modprobe:$out/libexec/flux/modprobe"

      wrapProgram "$out/bin/flux-python" \
        --set FLUX_LUA_PATH_PREPEND "$out/share/lua/5.2/?.lua" \
        --set FLUX_LUA_CPATH_PREPEND "$out/lib/lua/5.2/?.lua" \
        --set FLUX_EXEC_PATH "$out/libexec/flux/cmd" \
        --set FLUX_PYTHONPATH_PREPEND "$out/lib/flux/python3.13" \
        --set FLUX_CONNECTOR_PATH "$out/lib/flux/connectors" \
        --set FLUX_RC_EXTRA "$out/etc/flux" \
        --set FLUX_MODULE_PATH "$out/lib/flux/modules" \
        --set FLUX_MODPROBE_PATH_APPEND="$out/etc/flux/modprobe:$out/libexec/flux/modprobe"
    '';
  }
