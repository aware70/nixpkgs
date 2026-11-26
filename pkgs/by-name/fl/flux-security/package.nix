{
  lib,
  stdenv,
  fetchFromGitHub,
  autoreconfHook,
  pkg-config,
  jansson,
  libuuid,
  libsodium,
  munge,
  python3,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "flux-security";
  version = "0.17.0";

  src = fetchFromGitHub {
    owner = "flux-framework";
    repo = "flux-security";
    tag = "v${finalAttrs.version}";
    hash = "sha256-hauQu0Fnht28SLa76JKdmiikDWdyN6XB8sUlSPyLyAc=";
  };

  postPatch = ''
    substituteInPlace configure.ac \
      --replace-fail 'git describe --always' 'echo ${finalAttrs.version}'

    # The security configuration must live in a root-owned directory managed
    # by the system (see the NixOS module), so do not install the default one.
    substituteInPlace Makefile.am \
      --replace-fail 'SUBDIRS = src doc etc t' 'SUBDIRS = src doc t'

    # flux-imp run gives commands an FHS PATH; add the NixOS system paths so
    # the prolog, epilog and housekeeping units can find their tools.
    substituteInPlace src/imp/run.c \
      --replace-fail '"/usr/sbin:/usr/bin:/sbin:/bin"' '"/run/wrappers/bin:/run/current-system/sw/bin:/usr/sbin:/usr/bin:/sbin:/bin"'

    patchShebangs .
  '';

  nativeBuildInputs = [
    autoreconfHook
    pkg-config
    python3
  ];

  buildInputs = [
    jansson
    libuuid
    libsodium
    munge
  ];

  configureFlags = [ "--sysconfdir=/etc" ];

  # The sharness tests need a configured system instance.
  doCheck = false;

  meta = {
    description = "Security code for the Flux resource manager, including the setuid IMP";
    homepage = "https://github.com/flux-framework/flux-security";
    changelog = "https://github.com/flux-framework/flux-security/blob/${finalAttrs.src.tag}/NEWS.md";
    license = lib.licenses.lgpl3Only;
    maintainers = with lib.maintainers; [ aware70 ];
    platforms = lib.platforms.linux;
  };
})
