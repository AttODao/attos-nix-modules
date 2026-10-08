# attos-nix-modules

AttODaoの共通NixOS設定。全ホストでHome Managerを組み込み、機能ごとのenableでシステム設定と全HMユーザーの設定をまとめて有効化する。

各moduleのpackage/version、設定項目、設定例、注意点は[Wiki](https://forgejo.attodao.cc/AttODao/attos-nix-modules/wiki)を参照。
既存構成を移行するエージェントは、編集前に[利用側dotfilesの移行手順](docs/migration.md)を読む。
対象checkout・全OS/guest/HM/imageの確認から、秘密・永続データの保護、変更前後の比較、評価・適用の区別までを扱う。
未完了の作業は[残作業台帳](docs/inventory.md)、完了済みの履歴はGit履歴/PR等へ残す。

## 導入・適用方法（共通）

個別moduleの説明ではなく、どのホストでも必要な導入手順。
詳しい構成例とチェックリストは[Wikiの導入・適用方法](https://forgejo.attodao.cc/AttODao/attos-nix-modules/wiki/getting-started)を参照。

### 1. inputを固定し、入口を一度importする

利用側のflakeへcanonical URLを追加し、各NixOS構成で `nixosModules.default` を一度だけ読み込む。
`nixos.default` は同じ入口の別名で、両方のimportは不要。

```nix
# flake.nixのinputsへ追加（既存nixpkgs inputは保持）
inputs.shared.url =
  "git+https://forgejo.attodao.cc/AttODao/attos-nix-modules.git?ref=main";

# outputsの引数にsharedを受け取り、各nixosSystemのmodulesへ追加
modules = [
  shared.nixosModules.default
  ./common.nix
  ./node-a.nix # 別の構成ではそのホスト用ファイル
];
```

利用側ルートの `common.nix` に共通の機能選択・ユーザー差分、`node-a.nix` 等に
ホスト固有の選択・標準設定を置ける。hardware configurationは各ホストから従来どおりimportする。
機能別import、独自resolver、利用側のHM module import・standalone HM出力は不要。

初回は意図した導入作業として `nix flake lock` を実行し、利用側の `flake.lock` にsharedとその依存を固定する。
取得済みのrevisionを確認してlockを版管理する。URL末尾に `&rev=<40桁のcommit>` を追加する固定方法も使える。
remoteのHEADに依存しないよう、URLの `?ref=main` は省略しない。
更新は利用側で `nix flake update shared` を明示的に実行し、lock差分を確認する（URLにrevを指定した場合はその値も変更）。
通常評価では `--no-write-lock-file` を使い、nixpkgs更新を同時に混ぜない。

共有flakeはnixpkgsを持たず、通常package・HMともホストの `pkgs` を使う。
利用側のnixpkgs pin・overlay・unfree許可を維持する。unfreeが必要ならホストの
`nixpkgs.config.allowUnfreePredicate` 等で許可し、全許可を導入の必須条件にしない。
HMは共有flakeがrevision固定したraw source（`flake = false`）から読み込む。
別のHM input/importや `home-manager.inputs.nixpkgs.follows` は追加しない。

### 2. ユーザー・互換性・利用側の入力を残す

```nix
# common.nix（名前・stateVersionは利用側の既存値に置換）
{ pkgs, ... }:
{
  users.users.attodao.isNormalUser = true;
  users.users.attodao.shell = pkgs.zsh;
  modules.home-manager.users = [ "attodao" ];
  modules.zsh.enable = true;
  modules.foot.enable = true;

  system.stateVersion = "25.11"; # 既存値を保持。更新に合わせて上げない
  home-manager.users.attodao = {
    home.stateVersion = "25.11"; # HMの既存値を別に保持
    programs.foot.settings.main.font = "monospace:size=13";
  };
}
```

- `modules.home-manager.users` は既定 `[]`。ユーザーを作成せず、重複・未宣言ユーザーを拒否する。
  共通HM設定は標準 `home-manager.users` に直接追加したユーザーも含め、全HMユーザーへ適用される。
- ユーザー作成・shell・group/sudo・linger、hardware、保存先、機器/ネットワーク固有値は利用側の責務。
- secretsは復号後の `"/run/secrets/..."` のようなruntimeパス文字列を渡す。
  内容をNix式・パスリテラル・`builtins.readFile` でstoreへ取り込まない。
  配置、owner/group/mode、読取権限、起動順、rotation時の再起動は利用側で管理する。
  復号unitへの依存はそのunitが存在する場合だけ指定する（SOPSの既定はactivation script）。
  認証・履歴・既存の可変データを宣言的設定で上書きしない。
- 通常の機能選択・共通入力は各moduleの公開 `modules.*` optionを優先する。
  公開APIで表さないホスト差分・ユーザーごとの差分は標準NixOS option / `home-manager.users.<name>` へ書く（上書き用escape hatch）。
  `mkDefault` の値は通常代入で上書きでき、通常優先度の共通値の変更に限り `lib.mkForce` を検討する。
  自動依存への通常代入のfalseは競合するため、無条件に強制無効化しない。
- カーソル等の取得可能なassetsは利用側でURL/hashを固定する。壁紙・ゲーム資産・保存先も利用側で維持する。
  custom package引数 `attopkgs` は共有側が供給するため、別のpackage供給経路は不要。

### 3. 移行を比較し、評価・buildしてから適用する

既存のアプリ・package供給元・生成設定・起動経路を記録し、永続データをバックアップする。
旧featureの依存が共有側でも同じとは限らないため、必要なソフトはenableまたは
標準 `home.packages` / `environment.systemPackages` で明示的に保持する。
全参照を置換し、ホストごとの機能・全HMユーザーの設定の同等性を確認してから、
旧resolver・featureMatrix・wrapper・重複HM import・不要なstandalone HM経路を削除する。

利用側ルートで実行する例（`HOST` / `USER` は対象に置換）:

```sh
# 評価のみ
nix eval --no-write-lock-file --raw '.#nixosConfigurations.HOST.config.system.build.toplevel.drvPath'
nix eval --no-write-lock-file --raw '.#nixosConfigurations.HOST.config.home-manager.users.USER.home.activationPackage.drvPath'
# buildのみ。実機へ適用しない
nix build --no-write-lock-file --no-link '.#nixosConfigurations.HOST.config.system.build.toplevel'
nix build --no-write-lock-file --no-link '.#nixosConfigurations.HOST.config.home-manager.users.USER.home.activationPackage'
```

共有側の[評価テスト](#検証)も別途実行する。`nix flake check` だけでは `tests/*.nix` は実行されない。
評価成功・build成功・実機動作は別の確認。生成設定の比較後、利用者の判断で一台ずつ
`sudo nixos-rebuild switch --flake .#HOST` を実行し、boot/PAM/desktop/user service/機器を確認する。
失敗時は前のgenerationへ `sudo nixos-rebuild switch --rollback`、起動不能時はboot menuから戻す。
再評価用にinput指定・lock・設定も元へ戻す。データ変更はgenerationのrollbackでは戻らず、バックアップから復旧する。
導入手順の記載だけではホストに適用されない。

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
| atcoder-go | HM | Zsh、Go・direnv・AtCoder CLI/oj/aclogin・project scaffold同梱 |
| zed | HM | 任意のcodex-acp npm policy |
| discord | HM | Fcitx5 |
| foot | HM | Fonts |
| ssh | NixOS + HM（clientのみ） | — |
| paseo | HM | Pi |
| public-services（公開サーバー） | NixOS、PaseoのみHM | サービス別。下記と[公開サービスAPI](https://forgejo.attodao.cc/AttODao/attos-nix-modules/wiki/module-public-services)を参照 |
| docker / swarm / traefik / dns / cloudflare-ddns / cloudflare-public-cnames / openssh | NixOS | Docker / Swarm等、詳細はサーバー設定 |
| ytdl-sub / open-terminal / forgejo-actions-runner / incus | NixOS | サービス別。HMユーザーなしでも利用可能 |
| noctalia | HM + 録画時NixOS | 任意のGPU screen recorder support |
| open-deck-desktop | NixOS + HM | AppImage support |
| fcitx5 / floorp / pandora-launcher / pcmanfm / pi / userDirs / vscode / linux-wallpaperengine | HM | — |

依存先を通常代入でfalseにすると競合する。依存を切る変更は、動作条件を確認した上で行う。

### enable以外の独自option

デスクトップ・非公開機能はNixOS側の `modules.<feature>`、公開サーバーは
`modules.public-services.<FQDN>.<service>` に指定する。
独自入力は現行ホスト差と、秘密path・保存先・機器/ネットワーク・identity等のconsumer必須入力に限定し、固定値や標準optionの汎用passthroughは公開しない。

- `hyprland.{settings,neowall.enable,lidSwitch.enable,headless}`: 共通Lua設定・壁紙shader起動・蓋イベント。`settings`は共有既定値へ再帰的に上書きし、listは置換する。全HMユーザーへ調整可能な既定値として適用し、ユーザー別の標準HM設定で上書きできる。旧`monitors`は廃止し、`settings.monitor`へ移す（従来値を保持する場合は各monitorに`scale = 1`を明示）。Moonlightの全画面HDR切替は`settings.window_rule = [ { match.class = "^com[.]moonlight_stream[.]Moonlight$"; no_auto_hdr = true; } ];`で抑止できる。詳細は[Hyprland](https://forgejo.attodao.cc/AttODao/attos-nix-modules/wiki/module-hyprland)。
- `greeter.{cursor,output}`: cursor archiveは有効時必須。outputは既定null。
- `noctalia.{package,systemd,dock.pinned,location.address,calendar.accounts,screenRecorder}`: locationは既定null、CalDAV account集合は既定 `{}`。録画は既定無効、`source = "portal"` / `codec = "h264"`、`convertToX.enable` は既定false。accountのpasswordはruntime `passwordFile` で渡す。共通入力は全HMユーザーへの調整可能な既定値。詳細は[Noctalia](https://forgejo.attodao.cc/AttODao/attos-nix-modules/wiki/module-noctalia)。
- `pipewire.{alsaDevices,loopbacks,virtualSinks}`: 既定 `{}` / `[]` / `{}`。型付き機器調整・loopback定義を共有設定へ変換し、device/node identityとlatency校正値はconsumerが渡す。
- `limine.quietBoot`: 既定true。falseは共有のPlymouth・quiet kernel/console/initrd presetを適用しない。kernel/GPUの選択はconsumer。
- `limine.splashImage`: 既定nullの画像path。指定時は黒背景・中央配置、最大960x360の汎用 `centered-logo` Plymouth themeを構築する。未指定時はupstream themeを維持。
- `desktop-theme.{cursor,cursorName,cursorSize}`: archiveは既定null、nameは`Custom-Cursors`、sizeは48。指定時は共有 `custom-cursors` が全HMユーザー向けに `Custom-Cursors` を生成する。
- `steam.firewall.{remotePlay,dedicatedServer,localNetworkGameTransfers}`: 各既定false。必要な開放をconsumerが選択する。Steam enableだけでこれらのportは開かない。
- `home-manager.backupFileExtension`: nullまたは非空文字列、既定null。標準HMの既存ファイルbackup suffixへ転送する。
- `open-deck-desktop.binfmt`: 既定false。Open-Deck有効時だけAppImage binfmtへ転送する。
- `paseo.{hostname,environmentFile}`: 単独時のhostnameは既定`localhost`。公開時は登録FQDNを継承する。environmentFile未指定は各ユーザーの `~/paseo/daemon.env`。既存の固定ポート127.0.0.1:6767を維持するため、複数ユーザーでのdaemon同時起動は競合する。
- `userDirs.dataDirectory`: 既定nullで各ユーザーのHOMEへ追従する。指定時は `"/mnt/data"` のような引用符付きの絶対パス文字列を使う。実データをstoreへ取り込まないようNixのパスリテラルは拒否する。
- `linux-wallpaperengine.wallpapers`: monitor / wallpaperのリスト。scalingの既定はfill。assetsやユーザーごとの調整は標準HM設定を使う。
- `wireguard-client.{tunnels,secretService}`: tunnelsはinterface名から復号済みruntime絶対パス文字列へのattrset、既定 `{}`。secretServiceは既存復号service名またはnull（既定）で、非空tunnels時だけrequires/afterへ追加。SOPSでは `sops.useSystemdActivation` がtrueの場合だけ指定する。秘密の取得・復号・権限・rotationはconsumerが管理する。

`desktop-theme.cursor` がnullの場合は各HMユーザーの標準 `home.pointerCursor.package` が必須。
ユーザーごとに別packageを使う場合も標準HMで上書きできる。archiveのURL/hash・licenseはconsumerに残す。
カーソル名/サイズは公開APIへ指定し、共有側がGTK・Xresources・Hyprcursorへ反映する。GTK/icon等の公開API外のユーザー差分は標準NixOS/HM optionを使う。
Limineの画像素材、kernel・GPU・mitigationはホストが選択し、汎用Plymouth実装は共有側に置く。
Hyprlandは全HMユーザーの設定済みPictures配下にScreenshotsをactivationで作成する（`.keep`不要）。
AtCoder Goは`modules.atcoder-go`で有効化し、project scaffold（devenv・scripts・template・snippet）をmoduleに同梱する。`atcoder-go.{goPackage,nixDirenv.enable,projectGoPackage}`でtoolchain・direnvを選択できる。`projectAssets`は既定`./assets`、独自scaffoldへの上書きも可能、null時は最小helperのみ。認証は配布しない。
`discord.{commandLineArgs,service.killMode}`、`zed.{userSettings,codexAcp.npmPolicy}`、`fcitx5.keyboardLayout`も公開入力を使う。Zedの既定npm policyはunmanaged、bounded-offlineはcache優先・retry/timeout制限を選ぶ。
`pi.{settingsMode,piSessionsSource,systemWide}`で宣言的/既存優先merge、extension source、全system userへのCLI導入を選ぶ。pi-review・pi-usage・pi-keep-goingもrevision/hash固定で同梱する。agent共通AGENTS.mdで、過去session再利用、context-modeでの大出力処理、subagent分割、edit失敗時の読み直しを促す。mergeは非object/不正JSONを保存せず、user所有0600でatomic更新する。認証・履歴は触らない。
`openssh.{settings,listenAddresses,startWhenNeeded,openFirewall,waitForNetwork}`はserver policyとlistener順序を選択する。listener/socket/firewallの未指定値はnative設定に追従し、明示した値だけを転送する。

Noctaliaのsystemd launcher、Hyprlandのheadless bootstrap/input/seatd、PipeWire virtual sink、Sunshineのheadless依存は共有側が実装し、consumerが公開入力を選択する。サーバーの入力・運用条件は
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
`jellyfin`, `ollama`（任意のOpen WebUIを同梱）, `searxng`, `mailserver`, `groupware`, `wireguard-server`,
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
単独利用は同じtyped入力を`modules.code-server` / `modules.sunshine`へ指定する。
code-serverは既定password認証でruntime `environmentFile` が必須（`PASSWORD` または
`HASHED_PASSWORD`）。更新・telemetryは既定無効で、保存済みの設定・認証は上書きしない。
旧Nerd Font組み込みpackageは `attopkgs.code-server { src = <固定したstandalone release>; }`
へ公開 `code-server.packageSource` でstandalone releaseを渡せる。`user` / `group`も公開入力で、account作成・権限はconsumerが保持する。
SunshineはHyprland・Steamも有効にする。公開 `sunshine.{settings,apps,waitForHeadlessOutput}`と`hyprland.headless` / `pipewire.virtualSinks`でheadless出力と音声を選択できる。headless待機とnative autoStartが有効なら、output再作成後にSunshineも起動する。pairing状態・device identity・streamingのfirewallはconsumerに残す。Web UIのproxy登録だけでstreaming portは開かない。

OllamaとOpen WebUIは`modules/ollama/`で一つのmoduleとして扱う。公開`modules.public-services.<FQDN>.ollama.enable`は所有OSのbackendを有効化し、同じrecordの`webui=true`で任意のWebUIも有効化する（既定false）。WebUI無効時はUI用Docker/Swarm/Terminal・secret/path・HTTP proxy routeを作らない。旧公開`open-webui`record・実装directoryは廃止し、保存先・モデル・unit名は保持する。`modules.ollama`は以下の単独利用入口としても使用できる。既存Paseoはpublic-to-global bridgeを保持する。

### localhost単独利用

`modules.<service>.enable = true`で公開registryなしに同じ実装を起動できる。サービス固有の既存typed入力を再利用し、公開endpoint用の`host/deploy/private/backendUrl/backendAddress`は不要。`hostname`は既定`localhost`で、DNS/CNAME/Traefikへの登録はしない。公開local配置との同時有効化は拒否するが、別owner/管理外endpoint登録との併用は可能。

```nix
modules.ollama.enable = true;
modules.vaultwarden = {
  enable = true;
  dataDir = "/srv/vaultwarden";
  environmentFile = "/run/secrets/vaultwarden.env";
};
```

OCI frontendはloopbackだけへportをpublishし、通常Docker bridgeを使う（Swarm不要）。data/credential/UID/GID等の既存必須入力はcallerが供給し、portやpackage等の追加調整は標準NixOS optionで行う。対応port・native mail TLS・WebUIの任意連携・SSH scopeは[public-services Wiki](https://forgejo.attodao.cc/AttODao/attos-nix-modules/wiki/module-public-services)を参照。Paseoは既存`modules.paseo`（hostname既定localhost）、SSH serverは`modules.ssh.server.enable`（`modules.ssh.enable`は従来どおりclient）。WireGuardのinterface/address/keyとfirewall policyはnative入力としてcallerが保持する。
保存先・秘密・公開hostname・subscriptions・WireGuard clients・Incus instance定義はconsumerが所有する。
サーバーの追加入力は`dns.listenAddresses`、`traefik.publishedPortRanges`、公開`ollama.{package,home,modelsDir,listenAddress,port,loadModels,environmentVariables,webui}`（`host`は所有OS、`listenAddress`はbind）、`incus.{preseed,initrdKernelModules,preseedKernelModules,provisionKernelModules,rebuild.flakeFile}`。
WireGuardのsync identity/group/runtime modeとIPv4 forwarding、MailserverのsystemName/ACME、GroupwareのproductName、VaultwardenのextraHosts、Karakeepの非秘密environmentも公開service recordへ指定する。
Swarmの`tokenTransport` / `tokenFetch`は既定無効の専用リンク用平文HTTP。source allowlistは暗号学的な認証ではない。tokenはcredential経由、fetchは0600でatomicに配置し、joinが依存する。
Forgejo runnerの`dynamicUser=true`は既存native登録を保ち、static user・tmpfiles・bindを作らない。native dataDir以外は拒否する。ytdl-subの`startConditionFile`は任意のruntime readiness marker。
localサービスの必須値、Docker / Swarm依存、既存stateの扱いは[Wiki](https://forgejo.attodao.cc/AttODao/attos-nix-modules/wiki)の各moduleページを参照。

## ホスト側に残すもの

hardware、ユーザー作成・権限・linger、secrets、stateVersion、保存先、機器固有の音声設定、
Steamのfirewall policy、Wallpaper Engine assets、unfree licenseの許可は利用側で管理する。
公開APIがある機能はそのoptionで選択し、package導入だけのアプリ、標準OBS設定、外部AAGLは利用側に残す。
`modules.openssh.enable` はserver有効化、`modules.ssh.enable` はclient設定で別の選択。
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
python3 modules/noctalia/test-recording.py
python3 modules/pi/test-merge-settings.py /path/to/nixpkgs /path/to/home-manager
python3 modules/cloudflare-ddns/test-sync-dns.py
python3 modules/swarm/test-swarm.py
python3 modules/forgejo/test-networks.py
python3 modules/ytdl-sub/test-stage-config.py
python3 modules/wireguard-server/test-wireguard-runtime.py
python3 modules/incus/test-provision.py
python3 modules/incus/test-rebuild.py
python3 modules/groupware/test-radicale-users.py
python3 modules/wireguard-client/test-import-tunnels.py
python3 modules/atcoder-go/test-commands.py # NIXPKGS=/path/to/pinned/nixpkgsでsource指定可
python3 modules/atcoder-go/test-project.py # bundled scaffold、mock Goのみ
python3 packages/code-server/test-install.py
```

現在の固定revisionは利用側の `flake.lock` を参照する。
利用側の全構成を比較・評価し、buildと実機確認は別工程として扱う。
完了条件は[移行手順](docs/migration.md)、次に行う作業は[残作業台帳](docs/inventory.md)を参照。
