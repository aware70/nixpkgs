{
  lib,
  stdenv,
  fetchFromGitHub,
  autoreconfHook,
  pkg-config,
  flux-core,
  jansson,
  sqlite,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "flux-accounting";
  version = "0.63.0";

  src = fetchFromGitHub {
    owner = "flux-framework";
    repo = "flux-accounting";
    tag = "v${finalAttrs.version}";
    hash = "sha256-DWpKzxEGfCtIn/IwhjXze63I7EO0YM3/nmg/iX4h2JA=";
  };

  postPatch = ''
    substituteInPlace configure.ac \
      --replace-fail 'git describe --always' 'echo ${finalAttrs.version}'
    patchShebangs .
  '';

  nativeBuildInputs = [
    autoreconfHook
    pkg-config
    flux-core.pythonEnv
  ];

  buildInputs = [
    flux-core
    flux-core.pythonEnv
    jansson
    sqlite
  ];

  configureFlags = [ "--localstatedir=/var" ];

  enableParallelBuilding = true;

  meta = {
    description = "Bank and fair-share accounting for the Flux resource manager";
    homepage = "https://github.com/flux-framework/flux-accounting";
    changelog = "https://github.com/flux-framework/flux-accounting/blob/${finalAttrs.src.tag}/NEWS.md";
    license = lib.licenses.lgpl3Only;
    maintainers = with lib.maintainers; [ aware70 ];
    platforms = lib.platforms.linux;
  };
})
