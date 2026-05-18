# TODO:
# - Make it easy for regular vim/nvim to install without Nixvim using Github release?
{
  description = "Neovim sessions management plugin";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: 
  let
    overlay = final: prev: {
      nvimObsessions = final.callPackage ./nix/package.nix {
        pname = "obsessions";
        version = "0.1.0";
      };
    };
    mkObsessionsNvim = pkgs: pkgs.neovim.override {
      configure = {
        packages.obsessions.start = [ pkgs.nvimObsessions ];
        customLuaRC = "require('obsessions').setup()";
      };
    };
    supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    forEachSupportedSystem = f: nixpkgs.lib.genAttrs supportedSystems (system: f {
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ overlay ];
      };
    });
  in {
    overlays.default = overlay;

    packages = forEachSupportedSystem ({ pkgs }: let
      nvimWithObsessions = mkObsessionsNvim pkgs;
    in rec {
      default = nvimObsessions;
      nvimObsessions = pkgs.nvimObsessions;
      nvimObsessionsApp = nvimWithObsessions;
    });

    apps = forEachSupportedSystem ({ pkgs }: let
      nvimWithObsessions = mkObsessionsNvim pkgs;
      app = {
        type = "app";
        program = "${nvimWithObsessions}/bin/nvim";
      };
    in {
      default = app;
      app = app;
    });

    nixvimModules.default = { config, lib, pkgs, ... }:
    let
      cfg = config.programs.obsessions;
    in {
      options.programs.obsessions = {
        enable = lib.mkEnableOption "obsessions.nvim session manager";

        storagePath = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Custom path for session storage. Defaults to vim.fn.stdpath('data')/obsessions.";
        };

        autosaveInterval = lib.mkOption {
          type = lib.types.int;
          default = 300;
          description = "Autosave interval in seconds. Set to 0 to disable.";
        };

        restoreLastSession = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Restore the last active session on VimEnter.";
        };

        picker = lib.mkOption {
          type = lib.types.enum [ "auto" "telescope" "fzf_lua" "select" ];
          default = "auto";
          description = "Picker backend for session selection.";
        };

        lazyLoadBuffers = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Create named buffer stubs and lazy-load content on access.";
        };

        newSessionLayout = lib.mkOption {
          type = lib.types.enum [ "fullscreen" "bottom" "right" ];
          default = "fullscreen";
          description = "Terminal layout when creating a new session.";
        };

        newSessionTerminalHeight = lib.mkOption {
          type = lib.types.int;
          default = 15;
          description = "Terminal height (rows) when newSessionLayout = \"bottom\".";
        };

        newSessionTerminalWidth = lib.mkOption {
          type = lib.types.int;
          default = 80;
          description = "Terminal width (columns) when newSessionLayout = \"right\".";
        };

        lockTimeout = lib.mkOption {
          type = lib.types.int;
          default = 5000;
          description = "Milliseconds to wait for a session write lock before giving up.";
        };

        pickerKeymaps = lib.mkOption {
          type = lib.types.submodule {
            options = {
              delete = lib.mkOption {
                type = lib.types.str;
                default = "<C-d>";
                description = "Picker keymap to delete the highlighted session.";
              };
              rename = lib.mkOption {
                type = lib.types.str;
                default = "<C-r>";
                description = "Picker keymap to rename the highlighted session.";
              };
            };
          };
          default = { };
          description = "Custom keymaps used inside the session picker.";
        };
      };
      config = lib.mkIf cfg.enable {
        extraPlugins = [ self.packages.${pkgs.stdenv.hostPlatform.system}.nvimObsessions ];

        extraConfigLua = let
          luaOpts = builtins.concatStringsSep "\n" (
            lib.optional (cfg.storagePath != null)
              "['storage-path'] = '${cfg.storagePath}',"
            ++ [
              "['autosave-interval'] = ${toString cfg.autosaveInterval},"
              "['restore-last-session'] = ${lib.boolToString cfg.restoreLastSession},"
              "['picker'] = '${cfg.picker}',"
              "['lazy-load-buffers'] = ${lib.boolToString cfg.lazyLoadBuffers},"
              "['new-session-layout'] = '${cfg.newSessionLayout}',"
              "['new-session-terminal-height'] = ${toString cfg.newSessionTerminalHeight},"
              "['new-session-terminal-width'] = ${toString cfg.newSessionTerminalWidth},"
              "['lock-timeout'] = ${toString cfg.lockTimeout},"
              "['picker-keymaps'] = { delete = '${cfg.pickerKeymaps.delete}', rename = '${cfg.pickerKeymaps.rename}' },"
            ]);
        in "require('obsessions').setup({${luaOpts}})";
      };
    };

    devShells = forEachSupportedSystem ({ pkgs }: {
      default = pkgs.mkShell {
        packages = with pkgs; [ luajitPackages.fennel ];
      };
    });
  };
}
