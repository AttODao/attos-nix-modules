{ pkgs }:
let
  # EGL back endのdefault framebuffer向けDSA修正がMinecraftに必要。
  # nixpkgsが3.1.5以上を提供したら、このoverrideを削除する。
  version = "3.1.5";
  overrideLib =
    base:
    base.virtualglLib.overrideAttrs {
      inherit version;
      src = base.fetchurl {
        url = "https://github.com/VirtualGL/virtualgl/releases/download/${version}/VirtualGL-${version}.tar.gz";
        hash = "sha256-ijJJxPqO6pKDYsqXuP4W5bNW46GM0W2H4++nKocHULY=";
      };
    };
in
pkgs.virtualgl.override {
  virtualglLib = overrideLib pkgs;
  # upstream wrapperの32-bit対応を保ち、両architectureで同じ修正版を使う。
  pkgsi686Linux = pkgs.pkgsi686Linux // {
    virtualglLib = overrideLib pkgs.pkgsi686Linux;
  };
}
