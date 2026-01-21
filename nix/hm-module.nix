self: {
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) system;

  cli-default = self.inputs.symmetria-cli.packages.${system}.default;
  shell-default = self.packages.${system}.with-cli;

  cfg = config.programs.symmetria;
in {
  imports = [
    (lib.mkRenamedOptionModule ["programs" "symmetria" "environment"] ["programs" "symmetria" "systemd" "environment"])
  ];
  options = with lib; {
    programs.symmetria = {
      enable = mkEnableOption "Enable Symmetria shell";
      package = mkOption {
        type = types.package;
        default = shell-default;
        description = "The package of Symmetria shell";
      };
      systemd = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable the systemd service for Symmetria shell";
        };
        target = mkOption {
          type = types.str;
          description = ''
            The systemd target that will automatically start the Symmetria shell.
          '';
          default = config.wayland.systemd.target;
        };
        environment = mkOption {
          type = types.listOf types.str;
          description = "Extra Environment variables to pass to the Symmetria shell systemd service.";
          default = [];
          example = [
            "QT_QPA_PLATFORMTHEME=gtk3"
          ];
        };
      };
      settings = mkOption {
        type = types.attrsOf types.anything;
        default = {};
        description = "Symmetria shell settings";
      };
      extraConfig = mkOption {
        type = types.str;
        default = "";
        description = "Symmetria shell extra configs written to shell.json";
      };
      cli = {
        enable = mkEnableOption "Enable Symmetria CLI";
        package = mkOption {
          type = types.package;
          default = cli-default;
          description = "The package of Symmetria CLI"; # Doesn't override the shell's CLI, only change from home.packages
        };
        settings = mkOption {
          type = types.attrsOf types.anything;
          default = {};
          description = "Symmetria CLI settings";
        };
        extraConfig = mkOption {
          type = types.str;
          default = "";
          description = "Symmetria CLI extra configs written to cli.json";
        };
      };
    };
  };

  config = let
    cli = cfg.cli.package;
    shell = cfg.package;
  in
    lib.mkIf cfg.enable {
      systemd.user.services.symmetria = lib.mkIf cfg.systemd.enable {
        Unit = {
          Description = "Symmetria Shell Service";
          After = [cfg.systemd.target];
          PartOf = [cfg.systemd.target];
          X-Restart-Triggers = lib.mkIf (cfg.settings != {}) [
            "${config.xdg.configFile."symmetria/shell.json".source}"
          ];
        };

        Service = {
          Type = "exec";
          ExecStart = "${shell}/bin/symmetria-shell";
          Restart = "on-failure";
          RestartSec = "5s";
          TimeoutStopSec = "5s";
          Environment =
            [
              "QT_QPA_PLATFORM=wayland"
            ]
            ++ cfg.systemd.environment;

          Slice = "session.slice";
        };

        Install = {
          WantedBy = [cfg.systemd.target];
        };
      };

      xdg.configFile = let
        mkConfig = c:
          lib.pipe (
            if c.extraConfig != ""
            then c.extraConfig
            else "{}"
          ) [
            builtins.fromJSON
            (lib.recursiveUpdate c.settings)
            builtins.toJSON
          ];
        shouldGenerate = c: c.extraConfig != "" || c.settings != {};
      in {
        "symmetria/shell.json" = lib.mkIf (shouldGenerate cfg) {
          text = mkConfig cfg;
        };
        "symmetria/cli.json" = lib.mkIf (shouldGenerate cfg.cli) {
          text = mkConfig cfg.cli;
        };
      };

      home.packages = [shell] ++ lib.optional cfg.cli.enable cli;
    };
}
