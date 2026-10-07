# Guest-shaped public API projections; evaluation only, not an image/runtime test.
{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
  codeServerSource ? null,
  projectAssets ? null,
}:
let
  t = import ./lib.nix {
    inherit nixpkgs homeManager system;
    nixpkgsConfig.allowUnfree = true;
  };
  inherit (t) pkgs lib;
  cursor = pkgs.fetchurl {
    url = "https://example.invalid/cursor.zip";
    hash = lib.fakeHash;
  };
  scaffold =
    if projectAssets != null then
      projectAssets
    else
      builtins.toPath (
        toString (
          pkgs.runCommand "guest-scaffold-fixture" { } ''
            mkdir -p "$out/atcoder/scripts"
            printf '%s\n' 'exit 0' > "$out/atcoder/scripts/project"
            touch "$out/devenv.nix" "$out/devenv.yaml" "$out/envrc" "$out/gitignore"
          ''
        )
      );
  shellPackage = pkgs.writeShellScriptBin "noctalia" "exit 0";
  projectGo = pkgs.writeShellScriptBin "go" "exit 0";
  registry.modules.public-services = {
    "code.example.test".code-server = {
      enable = true;
      host = "development";
      backendUrl = "http://10.88.0.10:4444";
    };
    "sunshine.example.test".sunshine = {
      enable = true;
      host = "desktop";
      backendUrl = "https://10.88.0.11:47990";
    };
  };
  development =
    (t.evalSystem {
      users = [ "dev" ];
      modules = [
        registry
        {
          networking.hostName = "development";
          users.users.dev = {
            shell = pkgs.zsh;
            linger = true;
          };
          modules = {
            atcoder = {
              enable = true;
              goPackage = pkgs.go;
              nixDirenv.enable = false;
              projectAssets = scaffold;
              projectGoPackage = projectGo;
            };
            openssh = {
              enable = true;
              startWhenNeeded = false;
              settings = {
                PasswordAuthentication = true;
                KbdInteractiveAuthentication = true;
                UseDns = false;
              };
            };
            public-services."code.example.test".code-server = {
              packageSource = codeServerSource;
              user = "dev";
              group = "users";
              environmentFile = "/home/dev/code-server/server.env";
            };
          };
        }
      ];
    }).config;
  desktop =
    (t.evalSystem {
      users = [ "attodao" ];
      modules = [
        registry
        {
          networking.hostName = "desktop";
          users.users.attodao = {
            shell = pkgs.zsh;
            linger = true;
            extraGroups = [
              "render"
              "video"
              "input"
              "audio"
            ];
          };
          modules = {
            zsh.enable = true;
            desktop-theme = {
              enable = true;
              inherit cursor;
            };
            discord = {
              enable = true;
              commandLineArgs = "--ozone-platform=wayland";
              service.killMode = "mixed";
            };
            fcitx5.keyboardLayout = "us";
            hyprland.headless = {
              enable = true;
              outputName = "moonlight";
            };
            noctalia = {
              package = shellPackage;
              systemd = {
                enable = true;
                requires = [ "hyprland-headless-output.service" ];
                after = [ "hyprland-headless-output.service" ];
              };
            };
            openssh = {
              enable = true;
              openFirewall = false;
              startWhenNeeded = false;
              settings.AllowUsers = [ "attodao" ];
            };
            pipewire = {
              enable = true;
              virtualSinks.sunshine = {
                name = "sink-sunshine-stereo";
                description = "Sunshine Stereo";
              };
            };
            public-services."sunshine.example.test".sunshine = {
              settings = {
                audio_sink = "sink-sunshine-stereo";
                output_name = "moonlight";
              };
              apps = [
                {
                  name = "Desktop";
                  image-path = "desktop.png";
                }
                {
                  name = "Low Res Desktop";
                  prep-cmd = [
                    {
                      do = "change-output";
                      undo = "restore-output";
                    }
                  ];
                }
                {
                  name = "Steam Big Picture";
                  detached = [ "steam-big-picture" ];
                }
              ];
              waitForHeadlessOutput = true;
            };
            zed = {
              enable = true;
              userSettings = {
                autosave = "on_focus_change";
                agent_servers."codex-acp".default_config_options.reasoning_effort = "xhigh";
              };
              codexAcp.npmPolicy = "bounded-offline";
            };
          };
        }
      ];
    }).config;
  disabled = t.cfgFor [
    {
      modules = {
        atcoder = {
          projectAssets = scaffold;
          nixDirenv.enable = false;
        };
        discord = {
          commandLineArgs = "--ozone-platform=wayland";
          service.killMode = "mixed";
        };
        hyprland.headless.enable = true;
        noctalia = {
          package = shellPackage;
          systemd.enable = true;
          systemd.requires = [ "missing.service" ];
        };
        pipewire.virtualSinks.unused = {
          name = "unused";
          description = "Unused";
        };
        zed.codexAcp.npmPolicy = "bounded-offline";
        public-services = {
          "code.example.test".code-server = {
            host = "nixos";
            packageSource = /nonexistent/release;
            user = "absent";
          };
          "sunshine.example.test".sunshine = {
            host = "nixos";
            waitForHeadlessOutput = true;
            settings.audio_sink = "unused";
          };
        };
      };
    }
  ];
  devHome = t.hm development "dev";
  deskHome = t.hm desktop "attodao";
  disabledHome = t.hm disabled "test";
  projectCommand = lib.findFirst (p: lib.getName p == "atcoder-go") null devHome.home.packages;
  sink =
    builtins.head
      desktop.services.pipewire.extraConfig.pipewire."99-sunshine-sink"."context.objects";
  lua = deskHome.xdg.configFile."hypr/hyprland.lua".text;
in
assert development.services.code-server.user == "dev";
assert development.services.code-server.group == "users";
assert development.services.code-server.extraEnvironment.HOME == "/home/dev";
assert
  development.systemd.services.code-server.serviceConfig.EnvironmentFile
  == "/home/dev/code-server/server.env";
assert
  codeServerSource == null
  ||
    toString development.services.code-server.package.CODE_SERVER_SOURCE == toString codeServerSource;
assert devHome.programs.go.package == pkgs.go;
assert devHome.programs.direnv.enable && !devHome.programs.direnv.nix-direnv.enable;
assert projectCommand != null && projectCommand.meta.priority == -10;
assert lib.hasInfix (builtins.unsafeDiscardStringContext "${projectGo}/bin") projectCommand.text;
assert lib.hasInfix (builtins.unsafeDiscardStringContext "${scaffold}/atcoder/scripts/project")
  projectCommand.text;
assert development.services.openssh.settings.PasswordAuthentication;
assert !development.services.openssh.startWhenNeeded;
assert !development.modules.hyprland.enable && !development.services.sunshine.enable;
assert desktop.services.seatd.enable && desktop.services.seatd.group == "render";
assert desktop.systemd.services.seatd.environment.SEATD_VTBOUND == "0";
assert desktop.systemd.services ? container-udevd;
assert lib.elem "c /dev/input/event63 0660 root input - 13:127" desktop.systemd.tmpfiles.rules;
assert lib.hasInfix "\"output\" \"create\" \"headless\" \"moonlight\""
  desktop.systemd.user.services.hyprland-headless-output.serviceConfig.ExecStart;
assert desktop.systemd.user.services.hyprland-bootstrap.serviceConfig.Restart == "always";
assert
  deskHome.programs.noctalia.package == shellPackage && deskHome.programs.noctalia.systemd.enable;
assert
  deskHome.systemd.user.services.noctalia.Unit.Requires == [ "hyprland-headless-output.service" ];
assert !lib.hasInfix "uwsm app -t service -- noctalia" lua;
assert lib.hasInfix "fcitx5-daemon.service xdg-desktop-portal.service" lua;
assert desktop.systemd.user.services.sunshine.requires == [ "hyprland-headless-output.service" ];
assert desktop.services.sunshine.settings.audio_sink == "sink-sunshine-stereo";
assert
  map (app: app.name) desktop.services.sunshine.applications.apps == [
    "Desktop"
    "Low Res Desktop"
    "Steam Big Picture"
  ];
assert sink.args."factory.name" == "support.null-audio-sink";
assert sink.args."node.name" == "sink-sunshine-stereo";
assert
  sink.args."object.linger"
  &&
    sink.args."audio.position" == [
      "FL"
      "FR"
    ];
assert deskHome.systemd.user.services.discord.Service.KillMode == "mixed";
assert
  deskHome.programs.discord.package.drvPath
  == (pkgs.discord.override { commandLineArgs = "--ozone-platform=wayland"; }).drvPath;
assert
  deskHome.programs.zed-editor.enable
  && deskHome.programs.zed-editor.userSettings.autosave == "on_focus_change";
assert lib.hasInfix "fetch-timeout=10000"
  deskHome.home.file.".local/share/zed/external_agents/registry/npx/codex-acp/.npmrc".text;
assert deskHome.xresources.properties."Xcursor.theme" == "Custom-Cursors";
assert deskHome.xresources.properties."Xcursor.size" == 48;
assert deskHome.i18n.inputMethod.fcitx5.settings.inputMethod."Groups/0/Items/1".Layout == "us";
assert !desktop.services.openssh.openFirewall && !desktop.services.openssh.startWhenNeeded;
assert desktop.services.openssh.settings.AllowUsers == [ "attodao" ];
assert !desktop.modules.pi.enable && !desktop.modules.paseo.enable;
assert !disabled.services.code-server.enable && !disabled.services.sunshine.enable;
assert !disabled.services.seatd.enable && !(disabled.systemd.services ? container-udevd);
assert
  !(disabled.systemd.user.services ? hyprland-bootstrap)
  && !(disabled.systemd.user.services ? hyprland-headless-output);
assert
  !disabled.services.pipewire.enable
  && !(disabled.services.pipewire.extraConfig.pipewire ? "99-unused-sink");
assert !disabledHome.programs.go.enable && !disabledHome.programs.direnv.enable;
assert
  !disabledHome.programs.discord.enable
  && !disabledHome.programs.noctalia.enable
  && !disabledHome.programs.zed-editor.enable;
assert !(disabledHome.home.file ? ".local/share/zed/external_agents/registry/npx/codex-acp/.npmrc");
assert
  development.system.build.toplevel.drvPath != "" && desktop.system.build.toplevel.drvPath != "";
assert
  devHome.home.activationPackage.drvPath != "" && deskHome.home.activationPackage.drvPath != "";
true
