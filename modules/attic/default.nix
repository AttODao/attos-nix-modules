{
  config,
  lib,
  pkgs,
  ps,
  ...
}:
let
  s = ps.select config "attic";
  dataDir = ps.require "attic" "dataDir" s.cfg.dataDir;
  environmentFile = ps.require "attic" "environmentFile" s.cfg.environmentFile;
  listen = ps.listen s 8080;
  # atticdのlistenはSocketAddrなので、IPv6 literalは角括弧で囲む。
  listenAddress =
    if lib.hasInfix ":" listen.address then
      "[${listen.address}]:${toString listen.port}"
    else
      "${listen.address}:${toString listen.port}";
in
{
  options.modules = ps.moduleOptions "attic" (
    ps.common "Attic Nix binary cache server"
    // {
      # 署名済みのNARとpush tokenの発行面なので、明示しない限りgatewayのprivate allowlistの内側に置く。
      private = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Restrict the gateway route to the private networks and keep the hostname out of public CNAMEs. Defaults to true for the binary cache; false exposes cache reads of public caches and the token-protected push API to the Internet.";
      };
      dataDir = ps.pathOption "Root holding the SQLite database (server.db) and the local NAR/chunk storage (storage/); created as atticd:atticd 0750. Required when deployed locally.";
      environmentFile = ps.pathOption "Runtime environment file supplying ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64 (base64 of an RSA PEM PKCS#1 private key, e.g. `openssl genrsa -traditional 4096 | base64 -w0`). Required when deployed locally.";
      retentionPeriod = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "30 days";
        example = "6 months";
        description = "garbage-collection.default-retention-period (humantime): objects whose creation and last access are both older are collected. \"0\" disables time-based collection; a cache can override it with `attic cache configure <cache> --retention-period`.";
      };
    }
  );

  config = lib.mkMerge [
    { assertions = s.assertions; }
    (lib.mkIf s.enabled {
      services.atticd = {
        enable = true;
        inherit environmentFile;
        # upstreamがdatabase.url・storage・chunkingをmkDefault（1000）で置くため、共有既定はその上の900にする。
        # 利用側は services.atticd.settings の通常代入（100）でkeyごとに上書きできる。
        settings = lib.mapAttrsRecursive (_: lib.mkOverride 900) {
          listen = listenAddress;
          # clientへ返すcache-configのendpoint。未設定だとHost headerから合成される。
          api-endpoint = "${ps.url s 8080}/";
          # 公開時はgatewayのhostnameだけを受ける。単独利用は空（全Host）のまま。
          allowed-hosts = lib.optional (!s.standalone) s.hostname;
          database.url = "sqlite://${dataDir}/server.db?mode=rwc";
          storage = {
            type = "local";
            path = "${dataDir}/storage";
          };
          # upstreamのchunking既定値と同じ（64KiB以上のNARを平均64KiBのchunkに分けて重複排除）。
          # 変えると既存chunkと切れ目がずれて重複排除が効かなくなるので、運用後は変えない。
          chunking = {
            nar-size-threshold = 65536;
            min-size = 16384;
            avg-size = 65536;
            max-size = 262144;
          };
          compression.type = "zstd";
          garbage-collection = {
            interval = "12 hours";
            default-retention-period = s.cfg.retentionPeriod;
          };
        };
      };
      # upstreamはDynamicUserで/var/lib/private/atticdだけを書けるため、dataDirを所有できる静的accountで動かす。
      # userとgroupを両方静的に作るので、atticd-atticadm（DynamicUser=yes, User=atticd）もこのaccountを使う。
      users.users.atticd = {
        isSystemUser = true;
        group = "atticd";
      };
      users.groups.atticd = { };
      systemd.tmpfiles.rules = [
        "d ${builtins.toJSON dataDir} 0750 atticd atticd -"
        "d ${builtins.toJSON "${dataDir}/storage"} 0750 atticd atticd -"
      ];
      networking.firewall = ps.backendFirewall config s [ ];
      systemd.services.atticd = {
        unitConfig.RequiresMountsFor = [
          dataDir
          environmentFile
        ];
        serviceConfig = {
          DynamicUser = lib.mkForce false;
          ReadWritePaths = [ dataDir ];
        };
      };
      environment.systemPackages = [ pkgs.attic-client ];
    })
  ];
}
