{
  description = "Shared NixOS configuration with integrated Home Manager for AttODao";

  inputs = {
    # packages出力専用。moduleのattopkgsは利用ホストのpkgsで構築する。
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # flake出力の組み立て（systems・perSystem・flake.modules）。moduleの評価には関わらない。
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/2c0c1f01521469cf0271180c453c79782d53c2f6";
      flake = false;
    };
    claude-code-nix = {
      url = "github:sadjow/claude-code-nix";
      flake = false;
    };
    # hermes moduleが使うupstream NixOS moduleと、hermes-desktopのsource。
    # upstreamのPython環境はupstreamのlockで固定するため、nixpkgsはfollowsしない。
    hermes-agent.url = "github:NousResearch/hermes-agent/v0.23.0";
    # scarlett-driver（CLI・daemon・gpui GUI）。root直下のpackage.nixでsourceからbuildする。
    scarlett-driver = {
      url = "git+https://git.attodao.cc/AttODao/scaelett-driver?ref=refs/tags/v0.1.1";
      flake = false;
    };
    # Upstream module imported by modules/mailserver; pinned here instead of a fetchTarball in the module.
    nixos-mailserver = {
      url = "gitlab:simple-nixos-mailserver/nixos-mailserver/4a06abf89ea5e38a3e0f9bf12f3036095d4a24a2";
      flake = false;
    };
  };

  outputs =
    inputs@{
      flake-parts,
      nixpkgs,
      home-manager,
      ...
    }:
    let
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
      # standalone Home Manager用の入口。NixOSと同じmodules.<name>.*をHM側で書く。
      homeManagerDefault = import ./modules/home-manager/standalone.nix { inherit attopkgsFor; };
      # home.nixを持つfeature（home-managerはenableを持たない共通helperなので除く）。
      homeFeatures = builtins.filter (
        name: name != "home-manager" && builtins.pathExists (./modules + "/${name}/home.nix")
      ) (map baseNameOf (import ./modules).imports);
    in
    flake-parts.lib.mkFlake { inherit inputs; } (
      { config, lib, ... }:
      {
        # flake.modules.<class>.<name>（nixos・homeManager）を出力する。
        imports = [ flake-parts.flakeModules.modules ];

        # packagesはx86_64-linuxだけで評価・buildする（moduleは利用ホストのpkgsで動き、systemに依存しない）。
        systems = [ "x86_64-linux" ];

        perSystem =
          { system, ... }:
          let
            legacyPackages = attopkgsFor (
              import nixpkgs {
                inherit system;
                config.allowUnfree = true;
              }
            );
          in
          {
            inherit legacyPackages;
            # passthru.skipFlakeCheck = true を宣言したpackage（hermes-desktop: upstream nix/lib.nixがeval中に
            # lockfile sourceを読み、--no-buildのflake checkで失敗する）はcheckされるpackagesから外す
            # （legacyPackagesとattopkgsには残る）。
            packages = lib.filterAttrs (
              _: value: lib.isDerivation value && !(value.passthru.skipFlakeCheck or false)
            ) legacyPackages;
            # `nix fmt -- <files>`。flakeのnixpkgsのnixfmtで整形する。
            formatter = nixpkgs.legacyPackages.${system}.nixfmt;
          };

        flake = {
          attopkgs = { pkgs }: attopkgsFor pkgs;
          overlays.default = final: _prev: { attopkgs = attopkgsFor final; };
          modules.nixos.default = default;
          nixos.default = default;
          # homeManager.defaultは全featureのHM設定を読み、modules.<name>.*で選ぶ。
          # homeManager.<name>はdefaultにmodules.<name>.enable = mkDefault trueを足したもの。
          modules.homeManager = {
            default = homeManagerDefault;
          }
          // lib.genAttrs homeFeatures (name: {
            imports = [ homeManagerDefault ];
            modules.${name}.enable = lib.mkDefault true;
          });
          homeModules = config.flake.modules.homeManager;
        };
      }
    )
    # flake-partsのnixosModules optionは値をdeferredModuleとして包む（importsが数段深くなる）。
    # 深さが変わると利用側でのmoduleの並びが変わり、listの定義順（environment.systemPackages等）と
    # drvPathが変わるため、nixosModules.defaultはoptionを通さずにそのまま出す。
    // {
      nixosModules.default = default;
    };
}
