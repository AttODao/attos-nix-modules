{ pkgs }:
{
  atcoder-cli = pkgs.callPackage ./atcoder-cli.nix { };
  atcoder-oj = pkgs.callPackage ./atcoder-oj.nix { };
  atcoder-aclogin = pkgs.callPackage ./atcoder-aclogin.nix { };
  atcoder-commands = args: pkgs.callPackage ./atcoder-commands.nix args;
  vm-rebuild = args: pkgs.callPackage ./vm-rebuild.nix args;
  vm-bootstrap = args: pkgs.callPackage ./vm-bootstrap.nix args;
  mcsmanager = pkgs.callPackage ./mcsmanager.nix { };
  paseo = pkgs.callPackage ./paseo.nix { };
  code-server =
    { src }:
    pkgs.callPackage ./code-server.nix {
      inherit src;
      nerdFont = pkgs.nerd-fonts.jetbrains-mono;
    };
  karakeep-monolith = pkgs.callPackage ./karakeep-monolith.nix { };
  pipeasio = pkgs.callPackage ./pipeasio.nix { };
  pi = pkgs.callPackage ./pi.nix { };
  context-mode = pkgs.callPackage ./context-mode.nix { };
  open-deck-desktop = pkgs.callPackage ./open-deck-desktop.nix { };
  custom-cursors = { cursor }: pkgs.callPackage ./custom-cursors.nix { inherit cursor; };
  centered-plymouth-theme =
    { image }: pkgs.callPackage ./centered-plymouth-theme.nix { inherit image; };
  pandora-launcher = pkgs.callPackage ./pandora-launcher.nix { };
  pandoragh = pkgs.callPackage ./pandoragh.nix { };
}
