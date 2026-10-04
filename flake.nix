{
  description = "Shared NixOS and Home Manager modules for AttODao";

  outputs = { ... }: {
    nixosModules.default = ./nixos/default.nix;
    homeModules = {
      default = ./home/default.nix;
      foot = ./home/foot.nix;
    };
  };
}
