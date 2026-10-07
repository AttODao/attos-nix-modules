# nix-instantiate --eval --strict --read-write-mode tests/common-consumer-options.nix \
#   --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix {
    inherit nixpkgs homeManager system;
    nixpkgsConfig.allowUnfreePredicate =
      pkg: (import "${toString nixpkgs}/lib").getName pkg == "context-mode";
  };
  inherit (t) lib pkgs;
  base = t.cfgFor [ ];
  source = pkgs.writeTextDir "package.json" "{}";
  cursor = pkgs.writeText "cursor.zip" "";
  inputs = {
    modules = {
      pi = {
        settingsMode = "merge";
        piSessionsSource = source;
        systemWide = true;
      };
      limine.quietBoot = false;
      openssh = {
        settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = "no";
        };
        listenAddresses = [ { addr = "192.0.2.10"; } ];
        startWhenNeeded = false;
        openFirewall = false;
        waitForNetwork = true;
      };
      desktop-theme = {
        inherit cursor;
        cursorName = "Custom-Cursors";
        cursorSize = 32;
      };
    };
  };
  disabled = t.cfgFor [ inputs ];
  disabledHome = t.hm disabled "test";
  enabled = t.cfgFor [
    inputs
    {
      modules = {
        pi.enable = true;
        limine.enable = true;
        openssh.enable = true;
        desktop-theme.enable = true;
      };
      boot.kernelParams = [ "debug" ];
      home-manager.users.test.programs.pi-coding-agent.configDir = "/home/test/custom-pi";
    }
  ];
  home = t.hm enabled "test";
  namedCursor = t.hmFor [
    {
      modules.desktop-theme = {
        enable = true;
        cursorName = "Other-Cursors";
        cursorSize = 24;
      };
      home-manager.users.test.home.pointerCursor.package =
        pkgs.writeTextDir "share/icons/Other-Cursors/cursors/left_ptr" "";
    }
  ];
  defaults = t.cfgFor [ { modules.openssh.enable = true; } ];
  native = t.cfgFor [
    {
      modules.openssh.enable = true;
      services.openssh = {
        settings.AllowUsers = [ "operator" ];
        listenAddresses = [
          {
            addr = "127.0.0.1";
            port = 2222;
          }
        ];
        startWhenNeeded = true;
        openFirewall = false;
      };
    }
  ];
  socket = t.cfgFor [
    {
      modules.openssh = {
        enable = true;
        startWhenNeeded = true;
        waitForNetwork = true;
        listenAddresses = [
          {
            addr = "127.0.0.1";
            port = 2222;
          }
        ];
      };
    }
  ];
  multi =
    (t.evalSystem {
      users = [
        "alice"
        "bob"
      ];
      modules = [
        inputs
        { modules.pi.enable = true; }
      ];
    }).config;
  hasPackage = package: cfg: lib.any (p: p.outPath == package.outPath) cfg.environment.systemPackages;
in
assert !disabled.services.openssh.enable;
assert disabled.services.openssh.settings == base.services.openssh.settings;
assert disabled.services.openssh.listenAddresses == base.services.openssh.listenAddresses;
assert disabled.services.openssh.startWhenNeeded == base.services.openssh.startWhenNeeded;
assert disabled.services.openssh.openFirewall == base.services.openssh.openFirewall;
assert !(disabled.systemd.services ? sshd);
assert !(disabled.systemd.sockets ? sshd);
assert !disabled.boot.loader.limine.enable;
assert !disabled.boot.plymouth.enable;
assert !disabledHome.programs.pi-coding-agent.enable;
assert !(disabledHome.home.activation ? mergePiSettings);
assert !hasPackage t.attopkgs.pi disabled;
assert !hasPackage t.attopkgs.context-mode disabled;
assert !disabledHome.home.pointerCursor.enable;
assert disabledHome.xresources.properties == (t.hm base "test").xresources.properties;
assert !disabled.modules.fcitx5.enable;
assert enabled.boot.loader.limine.enable;
assert !enabled.boot.plymouth.enable;
assert enabled.boot.consoleLogLevel == base.boot.consoleLogLevel;
assert enabled.boot.initrd.verbose == base.boot.initrd.verbose;
assert lib.elem "debug" enabled.boot.kernelParams;
assert lib.all (p: !(lib.elem p enabled.boot.kernelParams)) [
  "quiet"
  "udev.log_level=3"
  "rd.systemd.show_status=auto"
];
assert defaults.services.openssh.settings == base.services.openssh.settings;
assert defaults.services.openssh.listenAddresses == base.services.openssh.listenAddresses;
assert defaults.services.openssh.startWhenNeeded == base.services.openssh.startWhenNeeded;
assert defaults.services.openssh.openFirewall == base.services.openssh.openFirewall;
assert
  !(lib.elem "network-online.target" (
    if defaults.services.openssh.startWhenNeeded then
      defaults.systemd.sockets.sshd.after
    else
      defaults.systemd.services.sshd.after
  ));
assert enabled.services.openssh.enable;
assert !enabled.services.openssh.settings.PasswordAuthentication;
assert !enabled.services.openssh.settings.KbdInteractiveAuthentication;
assert enabled.services.openssh.settings.PermitRootLogin == "no";
assert
  enabled.services.openssh.listenAddresses == [
    {
      addr = "192.0.2.10";
      port = null;
    }
  ];
assert !enabled.services.openssh.startWhenNeeded;
assert !enabled.services.openssh.openFirewall;
assert !(lib.elem 22 enabled.networking.firewall.allowedTCPPorts);
assert lib.elem "network-online.target" enabled.systemd.services.sshd.after;
assert lib.elem "network-online.target" enabled.systemd.services.sshd.wants;
assert native.services.openssh.settings.AllowUsers == [ "operator" ];
assert
  native.services.openssh.listenAddresses == [
    {
      addr = "127.0.0.1";
      port = 2222;
    }
  ];
assert native.services.openssh.startWhenNeeded;
assert !native.services.openssh.openFirewall;
assert native.modules.openssh.listenAddresses == native.services.openssh.listenAddresses;
assert native.modules.openssh.startWhenNeeded == native.services.openssh.startWhenNeeded;
assert native.modules.openssh.openFirewall == native.services.openssh.openFirewall;
assert socket.systemd.sockets.sshd.socketConfig.ListenStream == [ "127.0.0.1:2222" ];
assert lib.elem "network-online.target" socket.systemd.sockets.sshd.after;
assert lib.elem "network-online.target" socket.systemd.sockets.sshd.wants;
assert home.programs.pi-coding-agent.enable;
assert !home.home.file."/home/test/custom-pi/settings.json".enable;
assert home.home.file."/home/test/custom-pi/extensions/pi-sessions".source == source;
assert home.home.sessionVariables.PI_CODING_AGENT_DIR == "/home/test/custom-pi";
assert lib.hasInfix "/home/test/custom-pi" home.home.activation.mergePiSettings.data;
assert lib.hasInfix "chmod 0600" home.home.activation.mergePiSettings.data;
assert home.home.activation.mergePiSettings.before == [ "linkGeneration" ];
assert home.home.activation.mergePiSettings.after == [ "writeBoundary" ];
assert home.home.activationPackage.drvPath != "";
assert home.programs.pi-coding-agent.settings.sessions.autoTitle.refreshTurns == 4;
assert lib.hasInfix "context-mode-1.0.169" (
  builtins.head home.programs.pi-coding-agent.settings.packages
);
assert hasPackage t.attopkgs.pi enabled;
assert hasPackage t.attopkgs.context-mode enabled;
assert lib.all (user: (t.hm multi user).home.activation ? mergePiSettings) [
  "alice"
  "bob"
];
assert home.home.pointerCursor.package == t.attopkgs.custom-cursors { inherit cursor; };
assert home.home.pointerCursor.name == "Custom-Cursors";
assert home.home.pointerCursor.size == 32;
assert home.xresources.properties."Xcursor.theme" == "Custom-Cursors";
assert home.xresources.properties."Xcursor.size" == 32;
assert home.systemd.user.sessionVariables.XCURSOR_SIZE == "32";
assert home.systemd.user.sessionVariables.HYPRCURSOR_SIZE == "32";
assert namedCursor.home.pointerCursor.name == "Other-Cursors";
assert namedCursor.xresources.properties."Xcursor.theme" == "Other-Cursors";
assert namedCursor.xresources.properties."Xcursor.size" == 24;
assert namedCursor.systemd.user.sessionVariables.XCURSOR_THEME == "Other-Cursors";
true
