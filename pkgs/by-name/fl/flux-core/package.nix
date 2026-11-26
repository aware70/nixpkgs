{
  lib,
  stdenv,
  fetchFromGitHub,
  autoreconfHook,
  pkg-config,
  bash,
  coreutils,
  getopt,
  flux-security,
  hwloc,
  jansson,
  jq,
  libarchive,
  libuuid,
  lua5_4,
  lz4,
  ncurses,
  python3,
  sqlite,
  systemdLibs,
  zeromq,
}:

let
  luaEnv = lua5_4.withPackages (ps: [ ps.luaposix ]);
  pythonEnv = python3.withPackages (
    ps: with ps; [
      cffi
      jsonschema
      ply
      pyyaml
      setuptools
    ]
  );
in
stdenv.mkDerivation (finalAttrs: {
  pname = "flux-core";
  version = "0.91.0";

  src = fetchFromGitHub {
    owner = "flux-framework";
    repo = "flux-core";
    tag = "v${finalAttrs.version}";
    hash = "sha256-hrLKaXJxxuIra3b7d7/sNBpHCeCfVNF7bedT/H5HLXE=";
  };

  patches = [
    # Commands, the ssh connector and tests assume FHS paths for PATH.
    ./add-nixos-system-paths.patch
  ];

  postPatch = ''
    doPatch() {
      substituteInPlace "$@" \
        --replace-quiet '/bin/false' '${coreutils}/bin/false' \
        --replace-quiet '/bin/true' '${coreutils}/bin/true' \
        --replace-quiet '/bin/ls' '${coreutils}/bin/ls' \
        --replace-quiet '/bin/cat' '${coreutils}/bin/cat' \
        --replace-quiet '/bin/sleep' '${coreutils}/bin/sleep' \
        --replace-quiet '/bin/echo' '${coreutils}/bin/echo' \
        --replace-quiet '/bin/bash' '${bash}/bin/bash' \
        --replace-quiet '/usr/bin/getopt' '${getopt}/bin/getopt'
    }

    find . \( -name '*.sh' -o -name '*.py' -o -name '*.c' \) -print0 \
      | while IFS= read -r -d "" f; do doPatch "$f"; done
    doPatch etc/*.in

    # Site prolog, epilog and housekeeping scripts are managed by the NixOS
    # module in /etc rather than in the read-only store sysconfdir.
    substituteInPlace etc/flux-run-system-scripts.in \
      --replace-fail 'flux_sysconfdir="@X_SYSCONFDIR@/flux/system"' 'flux_sysconfdir="/etc/flux/system"'

    # flux-run-{prolog,epilog,housekeeping} run under the IMP with an empty
    # PATH, so call systemctl by its NixOS path.
    substituteInPlace src/bindings/python/flux/perilog.py \
      --replace-fail 'systemctl="systemctl"' 'systemctl="/run/current-system/sw/bin/systemctl"'

    patchShebangs config etc src/cmd
  '';

  # configure.ac reads the version from git otherwise
  env.FLUX_VERSION = finalAttrs.version;

  nativeBuildInputs = [
    autoreconfHook
    luaEnv
    pkg-config
    pythonEnv
  ];

  buildInputs = [
    bash
    flux-security
    jq
    libarchive
    luaEnv
    lz4
    ncurses
    pythonEnv
    sqlite
    systemdLibs
    zeromq
  ];

  propagatedBuildInputs = [
    hwloc
    jansson
    libuuid
  ];

  configureFlags = [
    "--with-flux-security"
    "--with-systemdsystemunitdir=${placeholder "out"}/lib/systemd/system"
    "--sysconfdir=${placeholder "out"}/etc"
    # Only referenced at runtime (system instance socket, perilog env files)
    "--runstatedir=/run"
  ];

  enableParallelBuilding = true;

  # Many tests depend on the network or on a running system instance.
  doCheck = false;

  passthru = {
    inherit luaEnv pythonEnv;
    luaVersion = lua5_4.luaversion;
    pythonVersion = python3.pythonVersion;
  };

  meta = {
    description = "Core services of the Flux hierarchical resource manager";
    homepage = "https://flux-framework.org";
    changelog = "https://github.com/flux-framework/flux-core/blob/${finalAttrs.src.tag}/NEWS.md";
    license = lib.licenses.lgpl3Only;
    maintainers = with lib.maintainers; [ aware70 ];
    platforms = lib.platforms.linux;
    mainProgram = "flux";
  };
})
