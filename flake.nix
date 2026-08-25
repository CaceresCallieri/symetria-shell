{
  description = "Desktop shell for Symmetria";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    quickshell = {
      url = "git+https://git.outfoxxed.me/outfoxxed/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    symmetria-cli = {
      url = "github:caelestia-dots/cli";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.caelestia-shell.follows = "";
    };
  };

  outputs = {
    self,
    nixpkgs,
    ...
  } @ inputs: let
    forAllSystems = fn:
      nixpkgs.lib.genAttrs nixpkgs.lib.platforms.linux (
        system: fn nixpkgs.legacyPackages.${system}
      );
  in {
    formatter = forAllSystems (pkgs: pkgs.alejandra);

    packages = forAllSystems (pkgs: rec {
      symmetria-shell = pkgs.callPackage ./nix {
        rev = self.rev or self.dirtyRev;
        stdenv = pkgs.clangStdenv;
        quickshell = inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
          withX11 = false;
          withI3 = false;
        };
        app2unit = pkgs.callPackage ./nix/app2unit.nix {inherit pkgs;};
        symmetria-cli = inputs.symmetria-cli.packages.${pkgs.stdenv.hostPlatform.system}.default;
      };
      with-cli = symmetria-shell.override {withCli = true;};
      debug = symmetria-shell.override {debug = true;};
      default = symmetria-shell;
    });

    devShells = forAllSystems (pkgs: let
      system = pkgs.stdenv.hostPlatform.system;

      # Qt packages that install QML modules the shell imports.
      #
      # Do NOT add `qtquickcontrols2`. It is a Qt5-era package name that does
      # not exist in pkgs.qt6 — Qt 6 merged Qt Quick Controls into
      # qtdeclarative, which therefore already provides QtQuick,
      # QtQuick.Controls, QtQuick.Templates, QtQuick.Layouts, QtQuick.Shapes
      # and Qt.labs.*. Referencing it aborts flake evaluation with
      # `undefined variable 'qtquickcontrols2'`.
      qtQmlPackages = with pkgs.qt6; [
        qtdeclarative
        qtmultimedia
        qt5compat
        qtsvg
      ];

      qmlImportPathOf = packages:
        pkgs.lib.concatStringsSep ":"
        (map (p: "${p}/${pkgs.qt6.qtbase.qtQmlPrefix}") packages);
    in {
      default = let
        shell = self.packages.${system}.symmetria-shell;
      in
        pkgs.mkShell.override {stdenv = shell.stdenv;} {
          inputsFrom = [shell shell.plugin shell.extras];
          packages = with pkgs; [clazy material-symbols rubik nerd-fonts.caskaydia-cove];
          SYMMETRIA_XKB_RULES_PATH = "${pkgs.xkeyboard-config}/share/xkeyboard-config-2/rules/base.lst";
        };

      # Lint-only shell, used by .github/workflows/lint.yml.
      #
      # It deliberately does NOT use `inputsFrom`. The main package lists
      # `plugin` in its buildInputs, so `inputsFrom = [shell]` forces the
      # symmetria-qml-plugin derivation to build — and that derivation has been
      # failing since before 2026-05 on `pkg_check_modules(... libcava
      # REQUIRED)`, which is also why every `update-flake-inputs` run is red.
      # Depending on the default devShell would make the lint job hostage to an
      # unrelated break.
      #
      # The cost of the separation is that `Symmetria`, `Symmetria.Internal`
      # and `Symmetria.Services` do not resolve in CI, since those modules come
      # from that same plugin. Three warning categories are parked at `info` in
      # .qmllint.ini because of it — see the note there, which records the
      # exact condition for restoring them.
      lint = pkgs.mkShell {
        # qt6.qtdeclarative supplies both qmllint and qmlformat.
        packages = [pkgs.qt6.qtdeclarative pkgs.shellcheck pkgs.ruff pkgs.uv];

        # Set explicitly rather than left to the Qt setup hooks. nixpkgs splits
        # qtdeclarative's binaries from its QML modules across store outputs,
        # so qmllint's own default import directory — which it derives from the
        # location of its binary — resolves nothing at all. Without this, even
        # `import QtQuick` fails, which is exactly what the first CI run showed
        # (6,268 import errors).
        QML_IMPORT_PATH = qmlImportPathOf (
          qtQmlPackages ++ [inputs.quickshell.packages.${system}.default]
        );
      };
    });

    homeManagerModules.default = import ./nix/hm-module.nix self;
  };
}
