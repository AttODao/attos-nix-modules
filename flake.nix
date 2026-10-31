{
  description = "Shared NixOS configuration with integrated Home Manager for AttODao";

  inputs = {
    # packages出力専用。moduleのattopkgsは利用ホストのpkgsで構築する。
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/095fef2f265c3c0da4fe315efba8f8a04495ab34";
      flake = false;
    };
    claude-code-nix = {
      url = "github:sadjow/claude-code-nix";
      flake = false;
    };
    # hermes moduleが使うupstream NixOS moduleと、hermes-desktopのsource。
    # upstreamのPython環境はupstreamのlockで固定するため、nixpkgsはfollowsしない。
    hermes-agent.url = "github:NousResearch/hermes-agent/v0.22.5";
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
      # passthru.skipFlakeCheck = true を宣言したpackage（hermes-desktop: upstream nix/lib.nixがeval中に
      # lockfile sourceを読み、--no-buildのflake checkで失敗する）はcheckされるpackagesから外す
      # （legacyPackagesとattopkgsには残る）。
      packages = lib.mapAttrs (
        _: lib.filterAttrs (_: value: lib.isDerivation value && !(value.passthru.skipFlakeCheck or false))
      ) legacyPackages;
      nixosModules.default = default;
      nixos.default = default;
    };
}
