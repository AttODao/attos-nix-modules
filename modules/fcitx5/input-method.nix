# Home Manager modules/i18n/input-method/default.nix without the GTK 2 immodule cache.
# nixpkgs marks gtk2 broken (https://github.com/NixOS/nixpkgs/issues/410814), but Home Manager
# still builds gtk2-immodule.cache unconditionally, so evaluating any fcitx5 user fails.
# home.nix disables the upstream module and imports this copy; options and the remaining
# behaviour are unchanged. Drop this file once Home Manager stops referencing gtk2, and refresh
# it from the locked Home Manager source when that module changes.
{
  config,
  pkgs,
  lib,
  modulesPath,
  ...
}:
let
  cfg = config.i18n.inputMethod;

  allowedTypes = lib.types.enum [
    "fcitx5"
    "nabi"
    "uim"
    "hime"
    "kime"
  ];

  gtk3Cache =
    pkgs.runCommandLocal "gtk3-immodule.cache"
      {
        buildInputs = [
          pkgs.gtk3
          cfg.package
        ];
      }
      ''
        mkdir -p $out/etc/gtk-3.0/
        GTK_PATH=${cfg.package}/lib/gtk-3.0/ \
          gtk-query-immodules-3.0 > $out/etc/gtk-3.0/immodules.cache
      '';
in
{
  meta.maintainers = with lib.maintainers; [
    kranzes
  ];

  imports = [
    "${modulesPath}/i18n/input-method/fcitx5.nix"
    "${modulesPath}/i18n/input-method/hime.nix"
    "${modulesPath}/i18n/input-method/kime.nix"
    "${modulesPath}/i18n/input-method/nabi.nix"
    "${modulesPath}/i18n/input-method/uim.nix"
    (lib.mkRemovedOptionModule [
      "i18n"
      "inputMethod"
      "enabled"
    ] "Use i18n.inputMethod.type and i18n.inputMethod.enable instead.")
  ];

  options.i18n = {
    inputMethod = {
      enable = lib.mkEnableOption "an additional input method type";

      type = lib.mkOption {
        type = lib.types.nullOr allowedTypes;
        default = null;
        example = "fcitx5";
        description = ''
          Select the enabled input method. Input methods are software to input
          symbols that are not available on standard input devices.

          Input methods are especially used to input Chinese, Japanese and
          Korean characters.

          Currently the following input methods are available in Home Manager:

          `fcitx5`
          : A customizable lightweight input method.
            The next generation of fcitx.
            Addons (including engines, dictionaries, skins) can be added using
            [](#opt-i18n.inputMethod.fcitx5.addons).

          `nabi`
          : A Korean input method based on XIM. Nabi doesn't support Qt 5.

          `uim`
          : The "universal input method" is a library with an XIM bridge.
            uim mainly supports Chinese, Japanese and Korean.

          `hime`
          : An extremely easy-to-use input method framework.

          `kime`
          : A Korean IME.
        '';
      };

      package = lib.mkOption {
        internal = true;
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          The input method method package.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      (lib.hm.assertions.assertPlatform "i18n.inputMethod" pkgs lib.platforms.linux)
    ];

    home.packages = [
      cfg.package
      gtk3Cache
    ];
  };
}
