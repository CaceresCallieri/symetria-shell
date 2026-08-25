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

    devShells = forAllSystems (pkgs: {
      default = let
        shell = self.packages.${pkgs.stdenv.hostPlatform.system}.symmetria-shell;

        # Every package that installs QML modules the shell imports. qmllint
        # resolves `import QtQuick`, `import Quickshell` and `import Symmetria`
        # through QML_IMPORT_PATH built from this list.
        #
        # Qt is split across derivations: QtQuick and QtQml ship in
        # qtdeclarative, QtQuick.Controls and QtQuick.Templates in
        # qtquickcontrols2, and so on. Listing only qtdeclarative resolves
        # QtQuick and leaves QtQuick.Controls failing.
        qmlModulePackages =
          (with pkgs.qt6; [
            qtdeclarative
            qtquickcontrols2
            qtmultimedia
            qt5compat
            qtsvg
          ])
          ++ [shell.quickshell shell.plugin];

        qmlImportPath =
          pkgs.lib.concatStringsSep ":"
          (map (p: "${p}/${pkgs.qt6.qtbase.qtQmlPrefix}") qmlModulePackages);
      in
        pkgs.mkShell.override {stdenv = shell.stdenv;} {
          inputsFrom = [shell shell.plugin shell.extras];
          # qt6.qtdeclarative is already pulled in transitively by inputsFrom,
          # but it is listed explicitly because the lint job depends on the
          # `qmllint` binary being on PATH, and a transitive build input is not
          # a contract. See .github/workflows/lint.yml.
          # qt6.qtdeclarative (qmllint) and shellcheck are listed explicitly
          # because the lint job depends on both binaries being on PATH, and a
          # transitive build input is not a contract. Pinning shellcheck here
          # also keeps developers and CI on one version — the runner's
          # preinstalled 0.9.0 disagreed with a local 0.11.0 on this repo.
          # See .github/workflows/lint.yml.
          packages = with pkgs; [clazy material-symbols rubik nerd-fonts.caskaydia-cove qt6.qtdeclarative shellcheck];
          SYMMETRIA_XKB_RULES_PATH = "${pkgs.xkeyboard-config}/share/xkeyboard-config-2/rules/base.lst";

          # Set explicitly rather than left to the Qt setup hooks. nixpkgs
          # splits qtdeclarative's binaries and its QML modules across store
          # outputs, so qmllint's own default import directory — which it
          # derives from the location of its binary — resolves nothing at all.
          # Without this, even `import QtQuick` fails.
          QML_IMPORT_PATH = qmlImportPath;
        };
    });

    homeManagerModules.default = import ./nix/hm-module.nix self;
  };
}
