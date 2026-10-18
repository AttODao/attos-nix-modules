{
  description = "Shared NixOS configuration with integrated Home Manager for AttODao";

  inputs = {
    # packages出力専用。moduleのattopkgsは利用ホストのpkgsで構築する。
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/acd21c5a3420a9d5fd0ed06299b10828267ef9ba";
      flake = false;
    };
    claude-code-nix = {
      url = "github:sadjow/claude-code-nix";
      flake = false;
    };
    # hermes-desktopのsource。hermes moduleのimageと同じreleaseに固定する。
    hermes-agent = {
      url = "github:NousResearch/hermes-agent/v0.21.6";
      flake = false;
    };
  };

  outputs =
    inputs@{ nixpkgs, home-manager, ... }:
    let
      inherit (nixpkgs) lib;
      attopkgsFor = pkgs: import ./packages { inherit pkgs inputs; };
      default =
        { pkgs, ... }:
        {
          imports = [
            "${home-manager}/nixos"
            ./modules
          ];
          _module.args.attopkgs = attopkgsFor pkgs;
        };
      legacyPackages = lib.genAttrs [ "x86_64-linux" ] (
        system:
        attopkgsFor (
          import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          }
        )
      );
    in
    {
      attopkgs = { pkgs }: attopkgsFor pkgs;
      overlays.default = final: _prev: { attopkgs = attopkgsFor final; };
      inherit legacyPackages;
      packages = lib.mapAttrs (_: lib.filterAttrs (_: lib.isDerivation)) legacyPackages;
      nixosModules.default = default;
      nixos.default = default;
    };
}
