{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  pkg-config,
  boost,
  coreutils,
  flux-core,
  libedit,
  yaml-cpp,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "flux-sched";
  version = "0.57.0";

  src = fetchFromGitHub {
    owner = "flux-framework";
    repo = "flux-sched";
    tag = "v${finalAttrs.version}";
    hash = "sha256-IsoX/we8XQIFNekXNjqUPymI82WhHVTlAv8sKHwTGp0=";
  };

  postPatch = ''
    patchShebangs etc t/rc
    substituteInPlace resource/utilities/test/resource-bench.sh \
      --replace-fail '/usr/bin/env' '${coreutils}/bin/env'
  '';

  # CMakeLists.txt reads the version from git otherwise
  env.FLUX_SCHED_VERSION = finalAttrs.version;

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    flux-core.pythonEnv
  ];

  buildInputs = [
    boost
    flux-core
    flux-core.luaEnv
    flux-core.pythonEnv
    libedit
    yaml-cpp
  ];

  # The test suite needs a configured flux-security and a running instance.
  doCheck = false;

  meta = {
    description = "Fluxion graph-based scheduler for the Flux resource manager";
    homepage = "https://github.com/flux-framework/flux-sched";
    changelog = "https://github.com/flux-framework/flux-sched/blob/${finalAttrs.src.tag}/NEWS.md";
    license = lib.licenses.lgpl3Only;
    maintainers = with lib.maintainers; [ aware70 ];
    platforms = lib.platforms.linux;
  };
})
