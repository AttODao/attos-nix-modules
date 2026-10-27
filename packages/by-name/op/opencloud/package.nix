{
  callPackage,
  lib,
  path,
  pkgs,
}:
# OpenCloud 9.0.0のversion override。nixpkgsのgeneric.nixへ新しいversion・hashを渡す。
# 固定nixpkgsが9.0.0以上を提供したらそちらを使い（既存dataより古い版へ戻さない）、このoverrideを削除する。
if lib.versionAtLeast pkgs.opencloud.version "9.0.0" then
  pkgs.opencloud
else
  callPackage (import "${path}/pkgs/by-name/op/opencloud/generic.nix" {
    version = "9.0.0";
    hash = "sha256-S9bWTRai8+41yFHcKM65jz5IUmBYk7KR6UJ0v8htzdw=";
    # 9.0.0のservices/web/MakefileのWEB_ASSETS_VERSION。
    webVersion = "8.2.1";
    webHash = "sha256-m/2ADuGVf5kM8GNb7W0ttunAaV7TE/j/UqGwZl4bNiY=";
    webPnpmDepsHash = "sha256-XD5aM0c3aBPoTZkHa1Lsiho2xMhibO7Pm+huopeGkAQ=";
    idpWebPnpmDepsHash = "sha256-rj6KFrzuINVpxrrel2p2iWtJVH8Zg1jrZEIAs8S+8Qs=";
  }) { }
