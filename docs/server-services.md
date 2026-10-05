# サーバーサービス

旧 `server-dotfiles` のサービス実装を共有する。consumerの移行・lock更新・実機適用は別作業。
共有側は既存のOCI / native backendと保存レイアウトを維持し、ホスト一覧や秘密の内容を取り込まない。

## 公開サービスのAPI

```nix
modules.public-services."vault.example.org".vaultwarden = {
  enable = true;
  dataDir = "/srv/vaultwarden";
  environmentFile = "/run/secrets/vaultwarden.env";
};
```

- 公開サービスの独自設定は、enableを含めて `modules.public-services.<FQDN>.<service>` に置く。
- FQDNは小文字・有効なDNS labelで指定する。別の `public-hosts.nix` や共有ホスト台帳は不要。
- `enable` は既定false。`deploy` は通常true。`deploy = false` は別ホストのサービスを登録するだけで、local unit・依存・秘密・保存先を要求しない。
- `private` は通常false。privateのhostnameは公開CNAMEから除外し、TraefikのHTTP/TCP allowlistで制限する。同じhostnameの有効なサービスは同じvisibilityにする。
- HTTPサービスの `backendUrl` はTraefikから到達できるURL。別ホストなら明示的に上書きする。Docker自身のloopbackをnative hostの接続先に使わない。
- 1 hostnameにつきHTTP backendは1つ。同じbackendUrlのpublic/private alias混在は拒否する。
- 同じサービスのlocal deploymentは1つまで。既存のunit/container名を保持する。追加のremote登録は可能。
- 調整には標準NixOS / HM optionも使える。依存enableは通常代入のfalseと競合する。

`ssh` は既定 `deploy = false; private = true;`。
`code-server` / `sunshine` も既定 `deploy = false` で、local設定は各guestのdotfilesが所有する。
既存の `modules.paseo` APIのみ互換bridgeを保持する。

### サービスとlocalで必要な値

表のpathは、Nixパスリテラルではなく引用符付きの絶対runtime path文字列を渡す。
秘密をstoreへ取り込まない。runtime pathはstore内・colon・改行を拒否する。

| service | localで必要な独自設定 | 自動有効化する依存 / 補足 |
| --- | --- | --- |
| vaultwarden | `dataDir`, `environmentFile` | Docker・Swarm |
| forgejo | `dataDir`, `environmentFile`, `userUid`, `userGid`, `mailAddress`, `mailHost`, `sshHost`, `sshBindAddress` | Docker・Swarm。`sshPort` 既定22 |
| immich | `dataDir`, `environmentFile` | Docker・Swarm |
| karakeep | `dataDir`, `environmentFile`, `dataUid`, `dataGid`, `networkSubnet`, `networkGateway`, `chromeAddress` | Docker・Swarm。Monolithは `attopkgs` |
| opencloud | `dataDir`, `environmentFile`, `uid`, `gid` | Docker・Swarm |
| mineos | `dataDir`, `environmentFile`, `uid`, `gid` | Docker・Swarm。`gameHost`, `tcpPorts`, `udpPorts` はgateway用 |
| jellyfin | `dataDir`, `mediaDir` | Docker・Swarm・ytdl-sub。ytdl-subの入力もconsumerが指定 |
| open-webui | `dataDir`, `ollamaUrl`, `searxngUrl` または有効なSearXNG登録1件 | Docker・Swarm・Ollama・Open Terminal。`environmentFile` 未指定時はOpen Terminalのものを参照 |
| searxng | `environmentFile` | Docker・Swarm。runtime `SEARXNG_SECRET` |
| mailserver | `domains`, `accounts`, `stateVersion`, `dataDir`, `acmeHost`, `dkimDomains` | pinned simple-nixos-mailserver。gatewayでは `backendAddress` も必要 |
| groupware | `dataDir` | Roundcube・Radicale。`mailserverHostName` 未指定は同じFQDNのmailserverを有効化。gatewayでは `backendUrl` が必要 |
| wireguard-server | `privateKeyFile`, `serverPublicKeyFile`, `clientDns` | native `networking.wireguard.interfaces` のaddresses/listenPort等はconsumer |
| paseo | HMユーザー1名、既存runtime env | Pi。`environmentFile` 未指定は各ユーザーの `~/paseo/daemon.env` |
| ssh | `address`（remote登録でも必須） | `deploy = true` ならOpenSSH。`user` / `port` はendpoint metadataで、ユーザー作成・server port変更はしない |
| code-server / sunshine | `backendUrl` | guest側のenable・保存先・認証を変更しない。必要な場合のみ `insecureSkipVerify = true` |

Swarmを必要とするlocalサービスでは、consumerが `modules.swarm.role` とその役割の入力を指定する。
Docker / Swarm enable自体は依存から有効化するため、二重指定は不要。

### 別ホストのHTTP backendをgatewayに登録する例

```nix
modules.public-services = {
  "vault.example.org".vaultwarden = {
    enable = true;
    deploy = false;
    backendUrl = "http://vaultwarden:80"; # 同じSwarm overlay上のremote backend
  };
  "code.example.org".code-server = {
    enable = true;
    private = true;
    backendUrl = "http://10.88.0.10:4444";
  };
};
modules.traefik = {
  enable = true;
  dataDir = "/srv/traefik";
  environmentFile = "/run/secrets/cloudflare.env";
  privateNetworks = [ "10.252.0.0/24" ];
  certificateDomains = [ { main = "example.org"; sans = [ "*.example.org" ]; } ];
};
modules.swarm = {
  role = "manager";
  advertiseAddress = "10.250.0.1";
  networkSubnet = "10.251.0.0/24";
  networkGateway = "10.251.0.1";
};
```

TraefikはHTTP/HTTPSに加えMineOSのTCP/UDPとmailserverのTCPを生成する。
同じlistenerへの異なるbackendやvisibilityは拒否する。
private MineOSではUDPをallowlistできないため `udpPorts = [ ];` とし、VPN専用のUDP ingressはconsumerで管理する。
MineOSのport rangeを変更した場合は、標準OCI environmentの割当範囲も合わせる。
公開listenerのfirewallは共有gatewayが開く。backend・管理用port・NAT・許可interfaceはconsumerで制限する。

## 公開しないサービス / infrastructure

これらは `modules.<name>.enable` を使う。すべてNixOS scopeで、HMユーザーなしでも評価できる。

| module | consumer入力 / 標準option |
| --- | --- |
| docker | 通常はenableのみ。保存先・一般ユーザーのDocker権限は標準optionでconsumer管理 |
| openssh | enableのみ。認証鍵・アクセス許可・listen port等は標準 `services.openssh` |
| swarm | `role`。managerは `advertiseAddress`, `networkSubnet`, `networkGateway`。workerは `managerAddress`, `joinTokenFile`, `networkReadyUrl` |
| traefik | `dataDir`, `environmentFile`。private routeでは `privateNetworks` 必須。`certificateDomains`, `acmeEmail` は任意 |
| dns | `ingressAddresses`。WireGuard登録では `wireguardAddress` も必要。listener/firewallは標準dnsmasq / networking設定 |
| cloudflare-ddns | `environmentFile`, 非空の `records`。A-record名はconsumerが所有 |
| cloudflare-public-cnames | `environmentFile`, `target`。recordsは有効かつ非privateのnamespaceから導出 |
| ytdl-sub | `dataDir`, `cookieFile`, `subscriptionFiles.{youtube,twitch}`, `uid`, `gid`。`cronFile` は任意 |
| ollama | 保存先・listener・モデル・GPU/packageは標準 `services.ollama`。モデル一覧は共有側で固定しない |
| open-terminal | `dataDir`, `environmentFile`, `uid`, `gid`, `allowedOrigins`。Open WebUIからoriginの既定値を設定 |
| forgejo-actions-runner | `dataDir`, `tokenFile`, `url`, `name`。外部Forgejoでも利用可能。Docker依存 |
| incus | instancesがある場合 `stateDir`, `containers`。preseedがある場合 `initializePool`。bootstrapは標準 `virtualisation.incus.preseed` |

### DNSとCloudflare

```nix
modules.dns = {
  enable = true;
  ingressAddresses = [ "192.168.0.100" "10.250.0.1" ];
  wireguardAddress = "192.168.0.100";
};
services.dnsmasq.settings.listen-address = [ "127.0.0.1" "10.250.0.1" ];
modules.cloudflare-ddns = {
  enable = true;
  records = [ "example.org" ];
  environmentFile = "/run/secrets/cloudflare.env";
};
modules.cloudflare-public-cnames = {
  enable = true;
  target = "example.org";
  environmentFile = "/run/secrets/cloudflare.env";
  comment = "existing-managed-comment"; # 旧recordを引き継ぐ場合は実際のmarkerを指定
};
```

- envには `CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ZONE_ID` を用意する。Traefikではtokenをruntimeの保護された `CF_DNS_API_TOKEN` envへ変換する。
- dnsmasqはSSHのaddress、WireGuardの指定address、その他のingress addressを使用する。privateなhostnameもlocal DNSへ登録する。
- DDNSは定期A更新、CNAMEは起動・生成設定変更時の同期。configは `/etc/cloudflare/`、Traefik設定は `/etc/traefik/` に生成する。秘密の内容は含めない。
- CNAMEのstale削除は、同じtargetを持つ同じownership commentのCNAMEのみ。TXT/MX等は削除しない。target / marker変更時の旧record整理はconsumerで確認する。
- A/CNAMEのtype変換はCloudflare batchのDB transactionで行う。失敗時に先に旧recordだけを削除しない。DNSへの伝播自体はatomicではない。
- mail用MX/SPF/DKIM/DMARC・逆引き等はconsumerのDNS運用に残す。

## state・秘密・運用上の境界

- OCI image / volume構成は旧設定を保持する。floating tagも残す。`:latest` は `pull = "always"`、activationでは稼働中の該当unitだけtry-restartする。自動pruneの既定はweekly。
- サービスのrootを `dataDir` に渡す。Forgejoは `forgejo/postgres`、Immichは `library/postgres/redis/model-cache`、Karakeepは `data/meilisearch`、OpenCloudは `config/data`、Vaultwardenは `vw-data`、Open WebUIは `data` を維持する。
- ytdl-subはOCI、3時間ごとminute 15、run-on-startなし。設定だけをstageし、media・download archive・履歴・working directoryを消さない。旧cronの順次実行・最終command status・重複実行可能性を保持する。cookieのatomic交換後はbind mountの旧inodeを避けるためcontainer再起動が必要。
- Swarmは既存roleを変更しない。既存cluster/overlay/bridgeのnetwork値を自動で再構成しない。manager token出力は0600でatomic交換し、initのtoken出力はjournalへ流さない。worker token配布はconsumerが管理する。
- 任意のreadiness serverは `/traefik-network-ready` の状態だけを返し、directoryやtokenを公開しない。managerは `readinessAddress` / `readinessPort` を指定し、worker URLをそのendpointへ合わせる。Swarmの2377/TCP・7946/TCP+UDP・4789/UDPとreadiness用portのLAN-only許可はconsumer。
- Docker CLIに渡すworker join tokenは短時間process引数に現れる。ローカルユーザーの信頼・`/proc`へのアクセス制限もconsumerの責務。
- WireGuard keysはruntimeで読み、native peer宣言との二重管理を拒否する。`useNetworkd = false` のscript backendを使用。client endpointはFQDNとnative listenPort、または `clientEndpoint`。clientは `clients.<name>.{address,publicKeyFile,privateKeyFile}` で指定する。生成configはprivate keyを含み0600、既定保存先は `/run/wireguard/client-configs`。`wg-qr --list` / `wg-qr <name>` の閲覧権限もconsumer管理。
- mailserverはrevision `2c3a8c4e36ab8190010f9f104e48d042cc65b05f` とNAR hash固定のupstreamを静的importする。accountsはupstream schema、credentialはruntime fileのみ。DKIM selectorのkeyFileもruntime string。ACMEのcert定義・provider・credentials・terms・contact、既存stateVersionはconsumerが指定する。任意relayは `relayHost` / `relayPasswordMap`。
- Groupwareは受信accountにbcryptの `hashedPasswordFile` を要求し、Radicale用authをruntimeでatomic生成する。元のmail hashやcollectionは上書きしない。秘密の同じpathでのrotationには該当serviceの再起動が必要。secret producerの順序・restartUnitsはconsumerで管理する。
- Actions runnerのtokenFileは標準native moduleが読む `TOKEN=...` の登録env。dataDirは専用directoryとし、既存 `.runner` / `.labels` / `.token-hash` をまとめて移行する。native固定pathへbindし、static service user `gitea-runner` を使うため、既存fileのownership・親directoryのアクセスをconsumerで確認する。MineOS / runnerのDocker socketアクセスはhost root相当の権限を持つ。
- Incusはpoolの存在でpreseedをskipするcreate-only guard。daemon/parser errorでは初期化しない。既存poolだけではbootstrap完了を証明しない。既存guestのlaunch設定・削除された定義は変更しない。`managedDeviceNames` に挙げたdeviceだけ追加/指定propertyを更新し、typeや省略propertyは再構成しない。
- Incusの `containers.<name>` には `alias`, `metadata`, `rootfs`, `launchConfig` を指定する。privileged、root disk容量、physical storage、image供給元、WireGuardとの組合せはconsumer。image cacheはsource path基準で、同じpathの内容変更は検出しない。image更新は既存guestをrebuildせず、旧imageも自動削除しない。
- 一般ユーザー、shell、linger、GPU / unfree、権限、秘密の供給、保存先、実機への適用は共有側で決めない。Paseo以外のサーバー機能はHMユーザーなしで利用できる。

## 検証

`tests/public-services.nix`, `public-apps.nix`, `public-apps-heavy.nix`, `server-dynamic.nix`, `server-mail.nix` をroot READMEと同じ引数で評価する。

```sh
python3 modules/cloudflare-ddns/test-sync-dns.py
python3 modules/swarm/test-swarm.py
python3 modules/forgejo/test-networks.py
python3 modules/ytdl-sub/test-stage-config.py
python3 modules/wireguard-server/test-wireguard-runtime.py
python3 modules/incus/test-provision.py
python3 modules/groupware/test-radicale-users.py
```

API/CLIはfakeまたはloopbackで検証する。評価・scriptテストの成功はimage/packageのbuild成功や実機動作の保証ではない。
consumer移行時に、保存先とownership、secret供給順、生成設定、native protocol、既存データでの起動、rollbackを別途確認する。
