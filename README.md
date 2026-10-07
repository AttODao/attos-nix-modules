# attos-nix-modules

AttODaoの共通NixOS設定。全ホストでHome Managerを組み込み、機能ごとのenableでシステム設定と全HMユーザーの設定をまとめて有効化する。

各moduleのpackage/version、設定項目、設定例、注意点は[Wiki](https://forgejo.attodao.cc/AttODao/attos-nix-modules/wiki)を参照。

## 使い方

利用側のflakeで、このrepoの `nixosModules.default` をNixOS moduleリストへ一度追加する。
`nixos.default` は同じ入口の別名。Home Managerを利用側で別途importする必要はない。

```nix
# flake.nix
inputs.shared.url =
  "git+https://forgejo.attodao.cc/AttODao/attos-nix-modules.git";

# nixosSystemのmodulesに追加
modules = [
  shared.nixosModules.default
  ./configuration.nix
];
```

```nix
# configuration.nix
{ pkgs, ... }:
{
  users.users.attodao.isNormalUser = true;
  modules.home-manager.users = [ "attodao" ];

  modules.thunderbird.enable = true;
  modules.foot.enable = true;
  modules.zsh.enable = true;

  # ユーザー作成・権限・ログインシェルは利用側。
  users.users.attodao.shell = pkgs.zsh;
}
```

これだけでThunderbirdのHM設定とNixOS側のEvolution Data Server・GNOME Keyring、
Footと依存するFontsの両scope、Zsh / Starshipの両scopeが有効になる。
`modules.home-manager.users` の既定値は `[]`。ユーザー作成は行わず、重複や未宣言ユーザーを拒否する。

HMの差分がある場合だけ、標準optionを使う。

```nix
home-manager.users.attodao = {
  home.stateVersion = "25.11"; # 移行前の値があれば保持する
  programs.foot.settings.main.font = "monospace:size=13";
};
```

共通設定が通常優先度で指定する値の変更には `lib.mkForce` が必要。
Footのfont / alphaやFontsの既定fontは `mkDefault` のため通常代入で上書きできる。

## Home Managerの管理

- HMのsourceはこのflakeでrevision固定。現在は `acd21c5a3420a9d5fd0ed06299b10828267ef9ba`。
- raw source input（`flake = false`）として取得するため、HMのためだけのnixpkgs inputは不要。
- HMも利用ホストの `pkgs` を使用し、packageはNixOSユーザー環境へ導入する。
- ユーザー名・ホームディレクトリはNixOSのユーザー定義から導出する。
- HMの `home.stateVersion` は `mkDefault "26.05"`。既存ホストでは従来の値を上書き指定し、HM更新に連動して変更しない。
- `attopkgs` は共有側で利用ホストの `pkgs` から構築し、NixOS / HMへ渡す。
- 機能選択はNixOS側の `modules.*` に一本化。以前の `home.*` exportとstandalone HM経路は提供しない。
- shared moduleは、標準 `home-manager.users` に直接追加したユーザーにも適用される。

ユーザー一覧に複数名を指定すると、固定メールアカウント・デバイス設定なども含め、
有効な機能の共通設定が全HMユーザーへ配布される。credential、secretの配置・権限は共有しない。

## 構造

```text
flake.nix
flake.lock
modules/
  default.nix               各機能を静的import
  home-manager/default.nix  HMユーザー一覧・共通HM設定・package引数
  thunderbird/
    default.nix             公開option・依存・両scopeの接続
    home.nix                HM設定
    nixos.nix               NixOS設定
  <feature>/
    default.nix
    home.nix                必要な場合のみ
    nixos.nix               必要な場合のみ
    <assets>                付随するscript・desktop entry・palette等
packages/
tests/
docs/
```

公開option・module間の依存は各機能の `default.nix` に置く。
`home.nix` / `nixos.nix` は実設定を担当し、HM側は `osConfig.modules.<feature>` を参照する。
importをenableから組み立てず、設定を条件付きで適用する。独自のfeature探索・依存resolverは使わない。

## 機能と依存

全機能のenableは既定false。

| 機能 | 設定するscope | 自動有効化する依存 |
| --- | --- | --- |
| thunderbird | NixOS + HM | EDS・GNOME Keyring |
| fonts | NixOS + HM | — |
| zsh | NixOS + HM | Starship同梱 |
| hyprland | NixOS + HM | Noctalia・Fcitx5・Foot・PCManFM・userDirs（FootからFonts） |
| greeter | NixOS | Hyprland |
| solaar | NixOS + HM | Noctalia、HM側にKando同梱 |
| pipeasio | NixOS + HM | PipeWire |
| pipewire | NixOS | rtkit・ALSA・Pulse |
| opencloud-client | NixOS + HM | — |
| login-pin | NixOS | — |
| desktop-theme | HM | Fcitx5・標準HM Qt/qt6ct設定 |
| steam | NixOS + HM | PCManFM |
| wireguard-client | NixOS | NetworkManager |
| limine | NixOS | — |
| atcoder | HM | Zsh、Go・direnv・AtCoder CLI/oj/aclogin同梱 |
| discord | HM | Fcitx5 |
| foot | HM | Fonts |
| ssh | NixOS + HM（clientのみ） | — |
| paseo | HM | Pi |
| public-services（公開サーバー） | NixOS、PaseoのみHM | サービス別。下記と[公開サービスAPI](https://forgejo.attodao.cc/AttODao/attos-nix-modules/wiki/module-public-services)を参照 |
| docker / swarm / traefik / dns / cloudflare-ddns / cloudflare-public-cnames / openssh | NixOS | Docker / Swarm等、詳細はサーバー設定 |
| ytdl-sub / ollama / open-terminal / forgejo-actions-runner / incus | NixOS | サービス別。HMユーザーなしでも利用可能 |
| fcitx5 / floorp / noctalia / open-deck-desktop / pandora-launcher / pcmanfm / pi / userDirs / vscode / linux-wallpaperengine | HM | Open-DeckはNixOS AppImage supportも有効化 |

依存先を通常代入でfalseにすると競合する。依存を切る変更は、動作条件を確認した上で行う。

### enable以外の独自option

デスクトップ・非公開機能はNixOS側の `modules.<feature>`、公開サーバーは
`modules.public-services.<FQDN>.<service>` に指定する。
独自入力は現行ホスト差と、秘密path・保存先・機器/ネットワーク・identity等のconsumer必須入力に限定し、固定値や標準optionの汎用passthroughは公開しない。

- `hyprland.{monitors,neowall.enable,lidSwitch.enable}`: モニター・壁紙shader起動・蓋イベント。詳細は[Hyprland](https://forgejo.attodao.cc/AttODao/attos-nix-modules/wiki/module-hyprland)。
- `greeter.{cursor,output}`: cursor archiveは有効時必須。outputは既定null。
- `noctalia.{dock.pinned,screenRecorder.enable}`: account/locationはユーザーごとの標準HM設定へ。詳細は[Noctalia](https://forgejo.attodao.cc/AttODao/attos-nix-modules/wiki/module-noctalia)。
- `paseo.{hostname,environmentFile}`: hostnameは有効時必須。environmentFile未指定は各ユーザーの `~/paseo/daemon.env`。既存の固定ポート127.0.0.1:6767を維持するため、複数ユーザーでのdaemon同時起動は競合する。
- `userDirs.dataDirectory`: 既定nullで各ユーザーのHOMEへ追従する。指定時は `"/mnt/data"` のような引用符付きの絶対パス文字列を使う。実データをstoreへ取り込まないようNixのパスリテラルは拒否する。
- `linux-wallpaperengine.wallpapers`: monitor / wallpaperのリスト。scalingの既定はfill。assetsやユーザーごとの調整は標準HM設定を使う。
- `wireguard-client.tunnels`: interface名から復号済みruntime絶対パス文字列へのattrset。既定 `{}`。秘密の取得・復号・起動順序・rotationはconsumerが管理する。

`desktop-theme` は各HMユーザーの標準 `home.pointerCursor.package` が必須。
既存 `attopkgs.custom-cursors { cursor = <取得済みarchive>; }` を渡し、URL/hashはconsumerに残す。
GTK/icon・カーソル名/サイズは標準HM optionで、Steamのfirewallは標準 `programs.steam.*` で調整する。
Limineは共通のquiet bootだけを設定し、kernel・GPU・mitigation・Plymouth素材はホストが選択する。
AtCoderはホストのGoを既定とし、toolchain固定は標準HM `programs.go.package` に指定する。
プロジェクト固有のテンプレート・ライブラリ・devenv定義や認証状態は配布しない。

その他のデスクトップ独自optionはenableのみ。サーバーの入力・運用条件は
[Wikiの公開サービスAPI](https://forgejo.attodao.cc/AttODao/attos-nix-modules/wiki/module-public-services)と各moduleページに記載する。詳細の調整には標準NixOS / HM optionも使う。

### SSH client

`modules.ssh.enable = true;` で、全HMユーザーへ共通接続先を設定する。
`attofort` / `attobox` / `devcon` / `desktop` / `git` / `github` を利用でき、
Gitは `git.attodao.cc`、GitHubは `github.com` でも同じ設定を使う。
接続先・ユーザー名は [modules/ssh/home.nix](modules/ssh/home.nix) を参照。
鍵は各ユーザーの `~/.ssh/id_ed25519` を参照するだけで、配布・生成しない。

有効な公開SSH登録のFQDN・`user`もclient設定へ反映する。追加設定は登録済みユーザーの標準HMへ書き、共通の既定値を通常代入で変更できる。

```nix
{
  modules.ssh.enable = true;
  home-manager.users.alice.programs.ssh.settings = {
    extra = {
      HostName = "extra.example.org";
      User = "operator";
      Port = 2222;
    };
    attofort.User = "operator";
    git.IdentityFile = "~/.ssh/git_key";
  };
}
```

共通設定は接続多重化・keepalive・`StrictHostKeyChecking accept-new` を使用する。
初回のhost keyは自動登録するが、変更されたkeyは拒否する。
OpenSSHのowner check対策として、生成したconfigをactivationでユーザー所有の実ファイル（0600）に配置し、
NixOSの `programs.ssh.systemd-ssh-proxy.enable` は既定falseにする。
`~/.ssh/config` の手編集は次回activationで置き換わるため、追加設定は標準`programs.ssh.settings`へ書く。
鍵・known_hostsは管理せず、sshd・firewall・認証policyも変更しない。

## サーバー機能

公開サービスは、enableを含む独自設定を一つのnamespaceへ集約する。

```nix
modules.public-services."vault.example.org".vaultwarden = {
  enable = true;
  host = "service-host";
  dataDir = "/srv/vaultwarden";
  environmentFile = "/run/secrets/vaultwarden.env";
};
```

対応サービス: `forgejo`, `immich`, `karakeep`, `vaultwarden`, `opencloud`, `mineos`,
`jellyfin`, `open-webui`, `searxng`, `mailserver`, `groupware`, `wireguard-server`,
`paseo`, `ssh`, `code-server`, `sunshine`。
DNS・公開CNAME・Traefikはこのnamespaceから導出し、consumerの `public-hosts.nix` をimportしない。
`deploy = false` はendpoint登録のみで、local unit・秘密・保存先を要求しない。
通常は `private = false`。private hostnameは公開CNAMEから除外し、gatewayでallowlist制限する。

### 複数マシンへの配置

各サービスの `host` に実際の `networking.hostName` を指定する。有効時は必須。
複数OSで同じnamespaceを共有でき、`enable && deploy && host一致` の実体だけが起動する。
`deploy` は全サービスで既定true。通常は `enable` と `host` だけで選択し、
`deploy = false` は管理外endpointの登録に使う。
DNS・CNAME・gatewayは配備先によらず有効な全endpointを参照する。
`host` はSSH aliasや親ホスト名ではなく、サービスが動くOS自身のhostname。

保存先・runtime secret等のlocal必須値は所有OSだけで要求する。
backendの到達性、Docker/Swarm network、firewall、ユーザー・secretsの供給はconsumerが管理する。
同一host上のlocal deploymentはサービス種別ごとに1件まで。
OCI upstreamは既存の内部DNS名・portで固定されるため、別hostの同種サービスを
FQDNごとに分離する仕組みではない。Groupwareの暗黙Mailserver依存も同じhostを継承する。

code-server / Sunshineも `enable = true; host = "<所有OS>";` でnative実体を有効にする。
別のglobal enable aliasは追加しない。
code-serverは既定password認証でruntime `environmentFile` が必須（`PASSWORD` または
`HASHED_PASSWORD`）。更新・telemetryは既定無効で、保存済みの設定・認証は上書きしない。
旧Nerd Font組み込みpackageは `attopkgs.code-server { src = <固定したstandalone release>; }`
を標準 `services.code-server.package` に渡せる。
SunshineはHyprland・Steamも有効にするが、headless出力・音声sink・pairing状態・
streamingのfirewallはconsumerに残す。Web UIのproxy登録だけでstreaming portは開かない。

公開するサービスの独自enable aliasは追加しない。既存Paseoは互換bridgeを保持する。
保存先・秘密・公開hostname・subscriptions・WireGuard clients・Incus instance定義はconsumerが所有する。
localサービスの必須値、Docker / Swarm依存、既存stateの扱いは[Wiki](https://forgejo.attodao.cc/AttODao/attos-nix-modules/wiki)の各moduleページを参照。

## ホスト側に残すもの

hardware、ユーザー作成・権限・linger、secrets、stateVersion、保存先、機器固有の音声設定、
Steamのfirewall、Wallpaper Engine assets、unfree licenseの許可は利用側で管理する。
greeterのカーソルアーカイブも利用側で取得する。login-pinは従来どおりattodaoのgreetd / TTYに限定する。
Pi等の認証・履歴・可変データは管理しない。
Open-Deckのupstream desktop entryは `--no-sandbox` を使うため、Electron sandboxは無効。

## 検証

利用ホストで固定したnixpkgs sourceと、このflakeで固定したHM sourceを渡す。

```sh
nix-instantiate --eval --strict tests/integrated.nix \
  --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
```

各機能の`tests/*.nix`も同じ引数で評価する。`tests/desktop-hosts.nix`はattodesk/attolap相当の選択・標準上書き・toplevel/activationのdrvPathを確認する（実機・ビルドの再現性証明ではない）。`tests/lib.nix` は共通helperのため単独評価の対象外。
sourceの取得・実体化が必要な評価には `--read-write-mode` を追加する。成功時は `true`。

```sh
python3 modules/login-pin/test-check-login-pin.py
python3 modules/pipeasio/test-register-steam-prefixes.py
python3 modules/cloudflare-ddns/test-sync-dns.py
python3 modules/swarm/test-swarm.py
python3 modules/forgejo/test-networks.py
python3 modules/ytdl-sub/test-stage-config.py
python3 modules/wireguard-server/test-wireguard-runtime.py
python3 modules/incus/test-provision.py
python3 modules/groupware/test-radicale-users.py
python3 modules/wireguard-client/test-import-tunnels.py
python3 modules/atcoder/test-commands.py # NIXPKGS=/path/to/pinned/nixpkgsでsource指定可
python3 packages/code-server/test-install.py
```

共有側の実装のみ変更しており、各dotfilesへの移行・lock更新・rebuildは別作業。
完了済みの共有実装、利用側の移行手順、未実装候補は[作業台帳](docs/inventory.md)を参照。
