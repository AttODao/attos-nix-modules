{
  description = "Shared NixOS configuration with integrated Home Manager for AttODao";

  inputs.home-manager = {
    url = "github:nix-community/home-manager/acd21c5a3420a9d5fd0ed06299b10828267ef9ba";
    flake = false;
  };

  outputs =
    { home-manager, ... }:
    let
      default = {
        imports = [
          "${home-manager}/nixos"
          ./modules
        ];
      };
    in
    {
      attopkgs = import ./packages;
      nixosModules.default = default;
      nixos.default = default;
    };
}
