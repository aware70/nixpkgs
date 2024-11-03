{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  curl,
  glfw3,
  qt6,
  libwebp,
  libuv,
  pkg-config,
  ninja,
}: stdenv.mkDerivation (finalAttrs: {

  pname = "maplibre-native-qt";
  version = "3.0.0";

  src = fetchFromGitHub {
    owner = "maplibre";
    repo = "maplibre-native-qt";
    rev = "refs/tags/v${finalAttrs.version}";
    sha256 = "sha256-h7PFoGJ5P+k5AEv+y0XReYnPdP/bD4nr/uW9jZ5DCy4=";
    fetchSubmodules = true;
  };

  meta = {
    homepage = "https://maplibre.org/maplibre-native-qt/docs/";
    description = "MapLibre Native bindings for Qt";
    license = with lib.licenses; [ bsd2 gpl2Only gpl3Only lgpl3Only mit ];
    platforms = [ "x86_64-linux" ];
    maintainers = with lib.maintainers; [ aware70 ];
  };

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    curl
    libuv
    libwebp
    glfw3
    qt6.qtbase
    qt6.qtlocation
  ];

})
