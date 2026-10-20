{
  description = "Shared NixOS configuration with integrated Home Manager for AttODao";

  inputs = {
    # packages出力専用。moduleのattopkgsは利用ホストのpkgsで構築する。
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/94c556362d7ef878175d2f0eb3045565d1685b0c";
      flake = false;
    };
    claude-code-nix = {
      url = "github:sadjow/claude-code-nix";
      flake = false;
    };
    # hermes moduleが使うupstream NixOS moduleと、hermes-desktopのsource。
    # upstreamのPython環境はupstreamのlockで固定するため、nixpkgsはfollowsしない。
    hermes-agent.url = "github:NousResearch/hermes-agent/v0.22.2";
    # Upstream module imported by modules/mailserver; pinned here instead of a fetchTarball in the module.
    nixos-mailserver = {
      url = "gitlab:simple-nixos-mailserver/nixos-mailserver/4a06abf89ea5e38a3e0f9bf12f3036095d4a24a2";
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
            inputs.hermes-agent.nixosModules.default
            ./modules
            "${inputs.nixos-mailserver}"
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
      # hermes-desktopはupstream nix/lib.nixがeval中にlockfile sourceを読み、--no-buildのflake checkで
      # 失敗するため、checkされるpackagesから外す（legacyPackagesとattopkgsには残る）。
      packages = lib.mapAttrs (
        _: lib.filterAttrs (name: value: lib.isDerivation value && name != "hermes-desktop")
      ) legacyPackages;
      nixosModules.default = default;
      nixos.default = default;
    };
}
