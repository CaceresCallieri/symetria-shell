{
  rev,
  lib,
  stdenv,
  makeWrapper,
  makeFontsConf,
  fish,
  ddcutil,
  brightnessctl,
  app2unit,
  networkmanager,
  lm_sensors,
  swappy,
  wl-clipboard,
  libqalculate,
  bash,
  hyprland,
  material-symbols,
  rubik,
  nerd-fonts,
  qt6,
  quickshell,
  aubio,
  libcava,
  fftw,
  pipewire,
  xkeyboard-config,
  cmake,
  ninja,
  pkg-config,
  symmetria-cli,
  debug ? false,
  withCli ? false,
  extraRuntimeDeps ? [],
}: let
  version = "1.0.0";

  runtimeDeps =
    [
      fish
      ddcutil
      brightnessctl
      app2unit
      networkmanager
      lm_sensors
      swappy
      wl-clipboard
      libqalculate
      bash
      hyprland
    ]
    ++ extraRuntimeDeps
    ++ lib.optional withCli symmetria-cli;

  fontconfig = makeFontsConf {
    fontDirectories = [material-symbols rubik nerd-fonts.caskaydia-cove];
  };

  cmakeBuildType =
    if debug
    then "Debug"
    else "RelWithDebInfo";

  cmakeVersionFlags = [
    (lib.cmakeFeature "VERSION" version)
    (lib.cmakeFeature "GIT_REVISION" rev)
    (lib.cmakeFeature "DISTRIBUTOR" "nix-flake")
  ];

  extras = stdenv.mkDerivation {
    inherit cmakeBuildType;
    name = "symmetria-extras${lib.optionalString debug "-debug"}";
    src = lib.fileset.toSource {
      root = ./..;
      fileset = lib.fileset.union ./../CMakeLists.txt ./../extras;
    };

    nativeBuildInputs = [cmake ninja];

    cmakeFlags =
      [
        (lib.cmakeFeature "ENABLE_MODULES" "extras")
        (lib.cmakeFeature "INSTALL_LIBDIR" "${placeholder "out"}/lib")
      ]
      ++ cmakeVersionFlags;
  };

  plugin = stdenv.mkDerivation {
    inherit cmakeBuildType;
    name = "symmetria-qml-plugin${lib.optionalString debug "-debug"}";
    src = lib.fileset.toSource {
      root = ./..;
      fileset = lib.fileset.union ./../CMakeLists.txt ./../plugin;
    };

    nativeBuildInputs = [cmake ninja pkg-config];
    buildInputs = [qt6.qtbase qt6.qtdeclarative libqalculate pipewire aubio libcava fftw];

    dontWrapQtApps = true;
    cmakeFlags =
      [
        (lib.cmakeFeature "ENABLE_MODULES" "plugin")
        (lib.cmakeFeature "INSTALL_QMLDIR" qt6.qtbase.qtQmlPrefix)
      ]
      ++ cmakeVersionFlags;
  };
in
  stdenv.mkDerivation {
    inherit version cmakeBuildType;
    pname = "symmetria-shell${lib.optionalString debug "-debug"}";
    src = ./..;

    nativeBuildInputs = [cmake ninja makeWrapper qt6.wrapQtAppsHook];
    buildInputs = [quickshell extras plugin xkeyboard-config qt6.qtbase];
    propagatedBuildInputs = runtimeDeps;

    cmakeFlags =
      [
        (lib.cmakeFeature "ENABLE_MODULES" "shell")
        (lib.cmakeFeature "INSTALL_QSCONFDIR" "${placeholder "out"}/share/symmetria-shell")
      ]
      ++ cmakeVersionFlags;

    dontStrip = debug;

    prePatch = ''
      substituteInPlace assets/pam.d/fprint \
        --replace-fail pam_fprintd.so /run/current-system/sw/lib/security/pam_fprintd.so
      substituteInPlace shell.qml \
        --replace-fail 'ShellRoot {' 'ShellRoot {  settings.watchFiles: false'
    '';

    postInstall = ''
      makeWrapper ${quickshell}/bin/qs $out/bin/symmetria-shell \
      	--prefix PATH : "${lib.makeBinPath runtimeDeps}" \
      	--set FONTCONFIG_FILE "${fontconfig}" \
      	--set SYMMETRIA_LIB_DIR ${extras}/lib \
        --set SYMMETRIA_XKB_RULES_PATH ${xkeyboard-config}/share/xkeyboard-config-2/rules/base.lst \
      	--add-flags "-p $out/share/symmetria-shell"

      mkdir -p $out/lib
      ln -s ${extras}/lib/* $out/lib/

      # Ensure wrap_term_launch.sh is executable
      chmod 755 $out/share/symmetria-shell/assets/wrap_term_launch.sh
    '';

    passthru = {
      inherit plugin extras;
    };

    meta = {
      description = "A very segsy desktop shell";
      homepage = "https://github.com/caelestia-dots/shell";
      license = lib.licenses.gpl3Only;
      mainProgram = "symmetria-shell";
    };
  }
