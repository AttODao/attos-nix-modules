{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix { inherit nixpkgs homeManager system; };
  inherit (t) lib;
  base = t.cfgFor [ ];
  cfg = t.cfgFor [ { modules.ssh.enable = true; } ];
  ssh = t.hm cfg "test";
  settings = ssh.programs.ssh.settings;
  text = ssh.home.file.".ssh/config".text;
  overridden = t.hmFor [
    { modules.ssh.enable = true; }
    {
      home-manager.users.test.programs.ssh.settings = {
        extra = {
          HostName = "extra.example.org";
          User = "other";
          Port = 2222;
        };
        attofort.User = "other";
        git.IdentityFile = "~/.ssh/git_key";
        "*".ServerAliveInterval = 60;
      };
    }
  ];
  multi =
    (t.evalSystem {
      users = [ "alice" ];
      modules = [
        {
          modules.ssh.enable = true;
          modules.public-services."multi.example.org".ssh = {
            enable = true;
            host = "remote";
            address = "10.0.0.2";
            user = "remote";
          };
          users.users.alice.home = "/srv/alice";
          users.users.bob = {
            isNormalUser = true;
            home = "/srv/bob";
          };
          home-manager.users.bob.programs.ssh.settings."multi.example.org".User = "bob-remote";
        }
      ];
    }).config;
  disabled = t.hmFor [
    {
      modules.public-services."disabled.example.org".ssh = {
        enable = true;
        host = "remote";
        address = "10.0.0.3";
        user = "remote";
      };
    }
  ];
  registry = t.hmFor [
    {
      modules.ssh.enable = true;
      modules.public-services."git.attodao.cc".ssh = {
        enable = true;
        host = "remote";
        address = "10.0.0.4";
        user = "registry-git";
      };
    }
  ];
  invalidHost = builtins.tryEval (t.cfgFor [ { modules.ssh.extra = "invalid"; } ]).modules.ssh.extra;
in
assert !invalidHost.success;
assert !disabled.programs.ssh.enable;
assert !(disabled.programs.ssh.settings ? extra);
assert !base.modules.ssh.enable;
assert !base.home-manager.users.test.programs.ssh.enable;
assert !(base.home-manager.users.test.home.activation ? installSshConfig);
assert base.programs.ssh.systemd-ssh-proxy.enable;
assert ssh.programs.ssh.enable && !ssh.programs.ssh.enableDefaultConfig;
assert !cfg.programs.ssh.systemd-ssh-proxy.enable;
assert !cfg.services.openssh.enable;
assert
  builtins.attrNames settings == [
    "*"
    "attobox"
    "attofort"
    "desktop"
    "devcon"
    "git"
    "github"
  ];
assert settings.attofort.data.HostName == "attofort.attodao.cc";
assert settings.attobox.data.HostName == "attobox.attodao.cc";
assert settings.devcon.data.HostName == "dev.attodao.cc";
assert settings.devcon.data.User == "dev";
assert settings.desktop.data.HostName == "desk.attodao.cc";
assert settings.git.data.HostName == "git.attodao.cc";
assert settings.github.data.HostName == "github.com";
assert settings.git.data.User == "git" && settings.github.data.User == "git";
assert settings.git.data.IdentitiesOnly && settings.github.data.IdentitiesOnly;
assert lib.hasInfix "Host git git.attodao.cc" text;
assert lib.hasInfix "Host github github.com" text;
assert lib.hasSuffix "  UserKnownHostsFile ~/.ssh/known_hosts\n" text;
assert !ssh.home.file.".ssh/config".enable;
assert lib.hasInfix "install -m 600" ssh.home.activation.installSshConfig.data;
assert builtins.isString ssh.home.activationPackage.drvPath;
assert overridden.programs.ssh.settings.extra.data.Port == 2222;
assert overridden.programs.ssh.settings.attofort.data.User == "other";
assert overridden.programs.ssh.settings.git.data.IdentityFile == "~/.ssh/git_key";
assert overridden.programs.ssh.settings."*".data.ServerAliveInterval == 60;
assert lib.hasInfix "Host extra" overridden.home.file.".ssh/config".text;
assert overridden.programs.ssh.settings.attobox.data.HostName == "attobox.attodao.cc";
assert multi.home-manager.users.alice.programs.ssh.enable;
assert multi.home-manager.users.bob.programs.ssh.enable;
assert
  multi.home-manager.users.alice.programs.ssh.settings."multi.example.org".data.HostName
  == "multi.example.org";
assert
  multi.home-manager.users.alice.programs.ssh.settings."multi.example.org".data.User == "remote";
assert
  multi.home-manager.users.bob.programs.ssh.settings."multi.example.org".data.User == "bob-remote";
assert registry.programs.ssh.settings."git.attodao.cc".data.User == "registry-git";
assert lib.elem "git" registry.programs.ssh.settings."git.attodao.cc".before;
assert lib.hasInfix "/srv/alice/.ssh"
  multi.home-manager.users.alice.home.activation.installSshConfig.data;
assert lib.hasInfix "/srv/bob/.ssh"
  multi.home-manager.users.bob.home.activation.installSshConfig.data;
true
