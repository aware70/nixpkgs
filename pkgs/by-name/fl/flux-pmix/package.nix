{
  lib,
  stdenv,
  fetchFromGitHub,
  autoreconfHook,
  pkg-config,
  flux-core,
  hwloc,
  jansson,
  pmix,
  python3,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "flux-pmix";
  version = "0.9.0";

  src = fetchFromGitHub {
    owner = "flux-framework";
    repo = "flux-pmix";
    tag = "v${finalAttrs.version}";
    hash = "sha256-4noeiACSf2G5Qp0ucW8cu2e5BAX8zpELc+eJ/ssy+fw=";
  };

  postPatch = ''
    patchShebangs .
  '';

  # configure.ac reads the version from git otherwise
  env.FLUX_PMIX_VERSION = finalAttrs.version;

  nativeBuildInputs = [
    autoreconfHook
    pkg-config
    # Builds the flux-shell-pmix(7) man page
    (python3.withPackages (ps: [
      ps.docutils
      ps.sphinx
    ]))
  ];

  buildInputs = [
    flux-core
    hwloc
    jansson
    pmix
  ];

  configureFlags = [
    # The MPI tests are only built for `make check`, which needs a running
    # flux instance.
    "--without-mpi"
  ];

  enableParallelBuilding = true;

  # The sharness tests start flux instances and run MPI jobs.
  doCheck = false;

  meta = {
    description = "PMIx support for the Flux resource manager";
    longDescription = ''
      A flux-shell plugin that offers a PMIx server to the tasks of a job,
      so that MPI implementations which bootstrap with PMIx (Open MPI, and
      MPICH built with PMIx) can run under Flux, and a PMI client plugin
      so that Flux can be launched by a PMIx-based launcher.
    '';
    homepage = "https://github.com/flux-framework/flux-pmix";
    changelog = "https://github.com/flux-framework/flux-pmix/blob/${finalAttrs.src.tag}/NEWS.md";
    license = lib.licenses.lgpl3Only;
    maintainers = with lib.maintainers; [ aware70 ];
    platforms = lib.platforms.linux;
  };
})
