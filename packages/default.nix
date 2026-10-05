{ pkgs }:
{
  pipeasio = pkgs.callPackage ./pipeasio.nix { };
  pi = pkgs.callPackage ./pi.nix { };
  context-mode = pkgs.callPackage ./context-mode.nix { };
  open-deck-desktop = pkgs.callPackage ./open-deck-desktop.nix { };
  custom-cursors = { cursor }: pkgs.callPackage ./custom-cursors.nix { inherit cursor; };
  pandora-launcher = pkgs.callPackage ./pandora-launcher.nix { };
  pandoragh = pkgs.callPackage ./pandoragh.nix { };
}
