# attos-nix-modules

AttODaoの共通NixOS設定。全ホストでHome Managerを組み込み、機能ごとのenableでシステム設定と全HMユーザーの設定をまとめて有効化する。

各moduleのpackage/version、設定項目、設定例、注意点は[Wiki](https://git.attodao.cc/AttODao/attos-nix-modules/wiki)を参照。
新しい利用側環境の作成手順は[Wiki](https://git.attodao.cc/AttODao/attos-nix-modules/wiki/getting-started)を参照。

## 導入・適用方法（共通）

詳しい構成例とチェックリストは[Wikiの導入・適用方法](https://git.attodao.cc/AttODao/attos-nix-modules/wiki/getting-started)を参照。

### 1. inputを固定し、入口を一度importする

利用側のflakeへcanonical URLを追加し、各NixOS構成で `nixosModules.default` を一度だけ読み込む。
`nixos.default` は同じ入口の別名で、両方のimportは不要。

```nix
# flake.nixのinputsへ追加（既存nixpkgs inputは保持）
inputs.shared.url =
  "git+https://git.attodao.cc/AttODao/attos-nix-modules.git?ref=main";

# outputsの引数にsharedを受け取り、各nixosSystemのmodulesへ追加
modules = [
  shared.nixosModules.default
  ./common.nix
  ./node-a.nix # 別の構成ではそのホスト用ファイル
];
```

利用側ルートの `common.nix` に共通の機能選択・ユーザー差分、`node-a.nix` 等に
ホスト固有の選択・標準設定を置ける。hardware configurationは各ホストからimportする。
機能別import、独自resolver、利用側のHM module import・standalone HM出力は不要。

remoteのHEADに依存しないよう、URLの `?ref=main` は省略しない。

moduleは通常package・HM・`attopkgs`ともホストの `pkgs` で構築する。
共有flakeが固定するnixpkgsは `packages` / `legacyPackages` 出力（`nix shell attos-nix-modules#claude-code` 等）専用。
利用側で重複を避ける場合は `shared.inputs.nixpkgs.follows = "nixpkgs";` を指定できる。
unfreeが必要ならホストの `nixpkgs.config.allowUnfreePredicate` 等で許可し、全許可を導入の必須条件にしない。
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
  復号unitへの依存はそのunitが存在する場合だけ指定する（SOPSの既定はactivation script）。
- 通常の機能選択・共通入力は各moduleの公開 `modules.*` optionを優先する。
  公開APIで表さないホスト差分・ユーザーごとの差分は標準NixOS option / `home-manager.users.<name>` へ書く（上書き用escape hatch）。
- カーソル等の取得可能なassetsは利用側でURL/hashを固定する。壁紙・ゲーム資産・保存先も利用側で維持する。

## Home Managerの管理

- HMのsourceはこのflakeでrevision固定。現在は `c216bf5a1f173b0481bd5c8c489ebe5595ecc68c`。
- HMも利用ホストの `pkgs` を使用し、packageはNixOSユーザー環境へ導入する。
- ユーザー名・ホームディレクトリはNixOSのユーザー定義から導出する。
- HMの `home.stateVersion` は `mkDefault "26.05"`。既存ホストでは既存の値を上書き指定し、HM更新に連動して変更しない。
- `attopkgs` は共有側で利用ホストの `pkgs` から構築し、NixOS / HMへ渡す。
- 機能選択はNixOS側の `modules.*` に一本化し、`home.*` exportとstandalone HM経路は提供しない。
- `modules/home-manager/home.nix` が全HMユーザーへ共通helperを `config.lib.attos.*` で供給する。`mutableXdgConfigFiles`はappが書き換える設定（Fcitx5の`config`/`profile`、Solaarの`rules.yaml`/`config.yaml`）をstore symlinkでなく未存在時だけ0600でcopyし、`graphicalAppService`はGUI常駐app（Discord・OpenCloud・Kando）の`graphical-session.target`配下user serviceを生成する。生成するserviceと`fcitx5-daemon`に`Requisite=graphical-session.target`を設定し、ログアウト後の再起動でセッション外に起動しない。

ユーザー一覧に複数名を指定すると、固定メールアカウント・デバイス設定なども含め、
有効な機能の共通設定が全HMユーザーへ配布される。credential、secretの配置・権限は共有しない。

## 構造

```text
flake.nix
flake.lock
modules/
  default.nix               各機能を静的import
  home-manager/default.nix  HMユーザー一覧・共通HM設定・package引数
  home-manager/home.nix     全HMユーザー共通のhelper（`config.lib.attos.*`）
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
  default.nix               by-nameの自動登録と外部source input
  by-name/<2文字>/<name>/package.nix  nixpkgsと同じshard構成
```

公開option・module間の依存は各機能の `default.nix` に置く。
`home.nix` / `nixos.nix` は実設定を担当し、HM側は `osConfig.modules.<feature>` を参照する。
importをenableから組み立てず、設定を条件付きで適用する。独自のfeature探索・依存resolverは使わない。

## 機能と依存

全機能のenableは既定false。

| 機能 | 設定するscope | 自動有効化する依存 |
| --- | --- | --- |
| thunderbird | NixOS + HM | EDS・GNOME Keyring |
| fonts | NixOS | — |
| zsh | NixOS + HM | Starship同梱（gruvbox-rainbow presetはrepoへコピー済み。評価はpackageを読まない） |
| hyprland | NixOS + HM | Noctalia・Fcitx5・Foot・Yazi・userDirs（FootからFonts）。sessionは`Hyprland (uwsm-managed)`のみ |
| greeter | NixOS | Hyprland |
| attos-mouse | NixOS + HM | Logitech hidraw uaccess（Solaarとは排他） |
| attos-deck | NixOS | —（Stream Deck MK.2のsystem service・udev・専用group。`agent.enable`はsystemctl agentのsocket） |
| solaar | NixOS + HM | Noctalia、HM側にKando同梱 |
| pipeasio | NixOS + HM | PipeWire・Steam（`programs.steam.package`へWINEDLLPATH付きSteamを既定値として渡す） |
| pipewire | NixOS | rtkit・ALSA・Pulse |
| opencloud-client | NixOS + HM | — |
| immich-client | HM | —（`immich upload --watch`のuser service。認証は`immich login`で行う） |
| login-pin | NixOS | — |
| desktop-theme | HM | Fcitx5・標準HM Qt/qt6ct設定 |
| steam | NixOS + HM | Yazi（FootからFonts） |
| wireguard-client | NixOS | NetworkManager |
| limine | NixOS | — |
| atcoder-go | HM | Zsh、Go・direnv・AtCoder CLI/oj/aclogin・project scaffold同梱 |
| zed | HM | 任意のcodex-acp npm policy、claude-code有効時はClaude AgentにNixのclaudeを使用 |
| discord | HM | Fcitx5 |
| hermes-desktop | HM | —（remote専用。dashboard URLまたはSSH接続先） |
| foot | HM | Fonts |
| yazi | HM | Foot（FootからFonts） |
| ssh | NixOS + HM | client: —、`server.enable`: localhost限定OpenSSH |
| paseo | HM | Pi（claude-code有効時はClaude provider） |
| ccpocket | HM | —（CC Pocket Bridgeのuser service。agentはユーザーprofileのclaude/codexとSDK同梱のClaude Code） |
| hermes | NixOS | —（native systemd、sandboxは既定有効。devenv・nixを同梱） |
| karakeep / attos-hoyo-dashboard | NixOS | Docker |
| forgejo / immich / vaultwarden / opencloud | NixOS | —（native `services.<name>`。Forgejo・ImmichはローカルPostgreSQL） |
| searxng | NixOS | —（native `services.searx`） |
| strata | NixOS | Docker（digest固定のAMD image、greeter sessionまたはデスクトップの`strata-headless start`でon-demand起動するAPI・モデル別unit・polkit） |
| jellyfin | NixOS | 公開配置時のみytdl-sub（native `services.jellyfin`） |
| ollama | NixOS | `webui`時のみDocker、公開配置時はOpen Terminalも |
| groupware | NixOS | 同じhostのMailserver |
| mcsmanager / mailserver / wireguard-server / code-server | NixOS | — |
| public-services（公開サーバー） | NixOS、Paseo・CC PocketはHM | サービス別。下記と[公開サービスAPI](https://git.attodao.cc/AttODao/attos-nix-modules/wiki/module-public-services)を参照 |
| traefik | NixOS | —（native `services.traefik`） |
| docker / dns / cloudflare-ddns / cloudflare-public-cnames / openssh | NixOS | — |
| ytdl-sub | NixOS | —（native `services.ytdl-sub.instances`）。HMユーザーなしでも利用可能 |
| open-terminal / forgejo-actions-runner / incus | NixOS | サービス別。HMユーザーなしでも利用可能 |
| noctalia | HM | `screenRecorder.enable`かつ`source != "portal"`のとき`programs.gpu-screen-recorder`（既定値）。任意のHeadroom・systemd unit launcher・W Engine。W Engineはlinux-wallpaperengine・util-linux・procpsを同梱 |
| open-deck-desktop | HM（`binfmt`時NixOS） | —（`binfmt`時のみAppImage binfmt） |
| fcitx5 / floorp / pandora-launcher / pcmanfm / userDirs / vscode / linux-wallpaperengine | HM | —（pcmanfmの`inode/directory`既定はyazi無効時のみ。両方有効ならYaziが既定） |
| pi | HM + `systemWide`時NixOS | skills |
| claude-code | HM | skills、context-mode MCP同梱 |
| skills | HM | —（Pi・Claude Code共通のagent skill。有効なagentへだけ導入） |

依存先を通常代入でfalseにすると競合する。

Hyprlandの既定packageは通常の`Hyprland` sessionのentry（`hyprland.desktop`）に`NoDisplay=true`を付けてgreeterに出さず、`Hyprland (uwsm-managed)`だけを選択肢にする。UWSM sessionはこのentryをIDで参照して起動するため、entry自体は消さない（uwsmは`Hidden`のentryを拒否する）。標準`programs.hyprland.package`を置換した場合のsession管理は利用側の責任。

### enable以外の独自option

デスクトップ・非公開機能はNixOS側の `modules.<feature>`、公開サーバーは
`modules.public-services.<FQDN>.<service>` に指定する。
独自入力は現行ホスト差と、秘密path・保存先・機器/ネットワーク・identity等のconsumer必須入力に限定し、固定値や標準optionの汎用passthroughは公開しない。

- `hyprland.{settings,neowall.enable,lidSwitch.enable}`: 共通Lua設定・壁紙shader起動・蓋イベント。`settings`は共有既定値へ再帰的に上書きし、listは置換する（`window_rule`はfullscreen idle inhibitへ追加し、Solaarのruleとも結合）。全HMユーザーへ調整可能な既定値として適用し、ユーザー別の標準HM設定で上書きできる。monitor配置は`settings.monitor`へ書く。listは既定を置換するため、各monitorに`scale`も明示する。Moonlightの全画面HDR切替は`settings.window_rule = [ { match.class = "^com[.]moonlight_stream[.]Moonlight$"; no_auto_hdr = true; } ];`で抑止できる。詳細は[Hyprland](https://git.attodao.cc/AttODao/attos-nix-modules/wiki/module-hyprland)。
- `strata.{flavor,dataDir,models,context,apiKeyFile,user}`（公開`public-services.<FQDN>.strata`と共通）: DockerによるAPI専用機能。ローカル配置時はGPU flavor・保存先・root:root 0400の秘密file・既存accountが必須。単独時は127.0.0.1:8080。boot時には起動せず、`Strata (API only)`でモデルを選択する。greeter・GPU設定・電源キー用の`input` groupは利用側が用意する。containerは`user`の権限で動く。デスクトップの`strata-headless start [モデル名|番号]`でも起動でき、Servingまで待つ（`--no-wait`で即座に戻る）。startは設定userのlocalかつactiveなsessionだけ、stopはSSHからも許可する。`strata-headless status`はreadinessも表示する。デスクトップではcompositorやアプリとVRAMを共有する。Dockerのport publishはhost firewallを迂回するため到達性を別途制限する。詳細は[Strata](https://git.attodao.cc/AttODao/attos-nix-modules/wiki/module-strata)。
- `greeter.{cursor,output,defaultUser}`: cursor archiveは既定`desktop-theme.cursor`で、有効時に非null必須。theme名/sizeは`desktop-theme.{cursorName,cursorSize}`に従う。outputは既定null。`defaultUser`（既定null）はgreeterで事前選択するaccountで、nullならuser欄は空のまま。
- `login-pin.{user,pinDatabaseFile}`: 有効時にどちらも必須。`user`はPINでログインできる唯一のaccount（他のuserはPIN promptを通らずpasswordで認証）。`pinDatabaseFile`はpam_userdbのDB（`.db`で終わる絶対runtime path）。`/etc/security/login-pin/pins.db`を指定した場合だけhost管理となり、`set-login-pin`コマンドを導入してrootがそこへ書く。別pathは復号済みsecretなど利用側が供給する読み取り専用DB。greetd/loginのPAMには`pam_faillock`（5回失敗で300秒lock、成功で解除）と`pam_faildelay`（3秒）を入れる。PIN ruleはNixOSが挿入する早期pam_unix（gnome-keyring・zfs・`failDelay`などが有効なときの`unix-early`）より前に置き、最初のpromptでPINかpasswordのどちらか1回の入力でログインできる（PINが一致すればそこで認証完了、不一致なら同じ入力をpasswordとしてpam_unixが再利用）。PINでログインしたときはgnome-keyringはpasswordで解錠されない。標準`failDelay`は使わない（同じ早期pam_unixを追加するだけで順序を制御できないため）。
- `thunderbird.{profile,accounts}`: `profile`（既定`default`）は全HMユーザーに作る既定profile名。`accounts`（既定`{}`）はHMの`accounts.email.accounts`と同じ形のattrsで、全HMユーザーへ`thunderbird.enable = true`既定で適用する。1件以上宣言するときは1件だけ`primary = true`にする。address・server・表示名などの個人識別情報は利用側に置き、認証情報は各ユーザーのprofileに残る。
- `floorp.defaultPreferences`: enterprise policyが設定できないpref（bool・int・str）をautoconfigの`defaultPref`で渡す。既定はパスワードSync無効・マウスジェスチャー有効で、ユーザーは変更可能。利用側の定義は既定集合全体を置き換える。
- `floorp.{vaultwardenUrl,extensions}`: `vaultwardenUrl`（既定null）はBitwarden拡張のself-hosted server presetで、nullなら拡張の環境設定を出さない。`extensions`（拡張ID→install URL、既定は同梱の一覧）はpolicyで`normal_installed`として導入し、ユーザーは無効化できる。利用側の定義は既定一覧全体を置き換える。
- `opencloud-client.serverUrl`: 有効時必須。clientのaccount wizardに事前入力するserver URL。
- `noctalia.{package,systemd,dock.pinned,location.address,calendar.accounts,screenRecorder,idle,headroom.enable,systemdUnits.enable,wallpaperEngine}`: locationは既定null、CalDAV account集合は既定 `{}`。録画は既定無効、`source = "portal"` / `codec = "h264"`。`idle.{lockAfter,screenOffAfter,suspendAfter}`は各nullまたは正整数（秒）、既定nullはbehaviorを生成しない。Headroom・systemdUnits・wallpaperEngineは各既定無効。壁紙の割り当て・再生設定はW Engineのpanelがstate（`data.json`）として持ち、宣言しない。旧`modules.linux-wallpaperengine`とは同時有効化不可。community pluginの取得・手動更新はNoctaliaが行い、自動更新はofficialのみ。accountのpasswordはruntime `passwordFile` で渡す。launcherはfloating、polkit agent・blur付きlockscreen・MRU switcher・左上launcher hot corner・VPN labelを既定で有効にする。共通入力と共有の`programs.noctalia.settings`は各leafが`mkDefault`で、`home-manager.users.<name>`から`mkForce`なしに一部だけ上書きできる（listは置換）。詳細は[Noctalia](https://git.attodao.cc/AttODao/attos-nix-modules/wiki/module-noctalia)。
- `attos-mouse.settings`: 既定 `{ }` のTOML設定。共有のuwsm wrapper・static CJK font・GTK icon theme・Everforest色へ再帰mergeし、listは置換する。device・menu定義は利用側が所有する。build時に`check-config`で検証し、daemonがinotifyで再読込する。`modules.solaar.enable`とは同じbuttonをdivertするため排他。Wayland/Hyprland・MX Master 4向け。
- `attos-deck.{settings,credentials,agent}`: `settings`（既定`{ }`）はattos-deckの`config.toml`。共有既定（`time.timeZone`のtimezone、state `/var/lib/attos-deck`、ssh client・鍵、static CJK font）へ再帰mergeし、listは置換する。host・agent・取得元・home keyは利用側が所有し、build時に`check-config`で検証する。`credentials`（名前→runtime path、既定`{ }`）は`LoadCredential`で渡し、settingsからは`/run/credentials/attos-deck.service/<名前>`で参照する。serviceは`DynamicUser`で、Stream Deck（`0fd9:0080`）のhidrawをudevで`attos-deck-hid` groupへ渡す。SSH鍵は初回起動時にstateへ生成し、公開鍵をjournalへ出す。`agent.{enable,socketGroup,settings}`は許可したsystemctl操作だけを行うroot agent（`/run/attos-deck-agent.sock`、`Accept=yes`）。`socketGroup`は利用側の既存groupで有効時必須、同じhostのdeckは自動で参加する。遠隔のdeckは利用側が作るSSH account（このgroup所属、鍵は`restrict,command="/run/current-system/sw/bin/attos-deck-agent ssh"`）経由で使う。`agent.settings`の既定は`restart_failed = true`・`deny = ["sshd.service" "attos-deck-agent.socket"]`で、`units.<unit>.allow`に許可する操作を書く。詳細は[attos-deck](https://git.attodao.cc/AttODao/attos-nix-modules/wiki/module-attos-deck)。
- `solaar.deviceConfig`: 既定nullのpath。Solaarの`config.yaml`（デバイスserial・unit ID・設定値）を全HMユーザーの`~/.config/solaar/`へ未存在時だけ配置する。nullならSolaarが初回起動時に作る。rules.yamlも同じく未存在時だけ配置し、既存ファイルはSolaarの変更を保持する（共有既定を受け直すにはファイルを削除する）。デバイス識別子は利用側が持つ。
- `pipewire.{alsaDevices,loopbacks,virtualSinks}`: 既定 `{}` / `[]` / `{}`。型付き機器調整・loopback定義を共有設定へ変換し、device/node identityとlatency校正値はconsumerが渡す。
- `limine.quietBoot`: 既定true。Plymouth・quiet kernel/console設定と、kernel引数によるsystemd initrdの状態表示制御を追加する。falseではこれらを適用しない。kernel/GPUの選択はconsumer。
- `limine.splashImage`: 既定nullの画像path。指定時は黒背景・中央配置、最大960x360の汎用 `centered-logo` Plymouth themeを構築する。未指定時はupstream themeを維持。
- `desktop-theme.{cursor,cursorName,cursorSize}`: archiveは既定null、nameは`Custom-Cursors`、sizeは48。指定時は共有 `custom-cursors` が全HMユーザー向けに `Custom-Cursors` を生成する。
- `steam.firewall.{remotePlay,dedicatedServer,localNetworkGameTransfers}`: 各既定false。必要な開放をconsumerが選択する。Steam enableだけでこれらのportは開かない。
- `home-manager.backupFileExtension`: nullまたは非空文字列、既定null。標準HMの既存ファイルbackup suffixへ転送する。
- `open-deck-desktop.binfmt`: 既定false。Open-Deck有効時だけ`programs.appimage`をbinfmt付きで有効化する（他のAppImage用。Open-Deck自体はappimageToolsで包装済み）。
- `paseo.{hostname,environmentFile,relay.enable}`: 単独時のhostnameは既定`localhost`。公開時は登録FQDNを継承する。environmentFile未指定は各ユーザーの `~/paseo/daemon.env`。`relay.enable`（既定false）はPaseo relayを有効にし、local listenerの外からdaemonへ到達できるようにする。既存の固定ポート127.0.0.1:6767を維持するため、複数ユーザーでのdaemon同時起動は競合する。
- `ccpocket.{port,allowClaudeOAuth,environmentFile}`（公開 `public-services.<FQDN>.ccpocket` と共通）: 単独利用は127.0.0.1、公開時は同じhostnameの`ssh.address`でlistenし、起動時のURL・QRに`ws://<FQDN>:<port>`を出す。bridgeはTLSなしの平文ws://で話すため、listen addressと登録hostnameはprivate DNS/VPN network内からだけ到達できるものに限る。公開recordは同じhostnameのssh登録が必須（local DNSはssh.addressを返す）で、`private`は既定true。portは既定8765（firewallはconsumerが開ける）。`allowClaudeOAuth`（既定false）はAPI keyの代わりにClaude Codeのログインを使う`BRIDGE_ALLOW_CLAUDE_OAUTH=1`を設定する（upstreamが規約上の不確実性を明記した明示opt-in）。environmentFile未指定は各ユーザーの `~/.ccpocket/bridge.env`。fileが無ければ起動せず、`BRIDGE_API_KEY`が空なら起動を拒否する。`ANTHROPIC_API_KEY`もこのfileへ書く。API keyをjournalへ出さないためQR・deep linkにtokenを含めない（appでAPI keyを入力する）。固定portのため複数HMユーザーは拒否する。
- `userDirs.dataDirectory`: 既定nullで各ユーザーのHOMEへ追従する。指定時は `"/mnt/data"` のような引用符付きの絶対パス文字列を使う。実データをstoreへ取り込まないようNixのパスリテラルは拒否する。
- `linux-wallpaperengine.wallpapers`: opt-inで残す旧user service。monitor / wallpaperのリスト、scalingの既定はfill。Noctaliaから操作する場合は`noctalia.wallpaperEngine`を選び、両moduleは同時有効化しない。assetsやユーザーごとの調整は利用側で管理する。
- `wireguard-client.tunnels`: interface名からtunnel定義（`privateKeyFile`・`addresses`・`dns`・`peers`）へのattrset、既定 `{}`。標準`networking.networkmanager.ensureProfiles`でautoconnect無効のruntime profileを作り、秘密鍵は`NetworkManager-ensure-profiles.service`がruntime fileから読んでroot専用profileへ書く（NetworkManagerは利用者uidのsecret agentにしか問い合わせないため、root agent方式では手動接続できない）。秘密の取得・復号・権限・rotationはconsumerが管理し、rotation後は同serviceを再起動する。

`desktop-theme.cursor` がnullの場合は各HMユーザーの標準 `home.pointerCursor.package` が必須。
archiveのURL/hash・licenseはconsumerに残す。
カーソル名/サイズは公開APIへ指定し、共有側がGTK・Xresources・Hyprcursor・systemd user session環境へ反映する。Hyprland・user serviceはsession環境を継承する。
Limineの画像素材、kernel・GPU・mitigationはホストが選択し、汎用Plymouth実装は共有側に置く。
Hyprlandのスクリーンショット3種（領域・注釈・フォーカス中monitor全体）とAlt+TabはNoctaliaへ送る。保存先（Pictures配下のScreenshots）はNoctaliaが保存時に作成する（`.keep`不要）。全windowにfullscreen時のidle inhibit ruleを追加し、consumer・Solaarのruleと結合する。Noctaliaの壁紙はneowall・標準HM linux-wallpaperengine service・W Engineが有効なら既定で無効にし、background surfaceの二重描画を避ける。Incus agentを有効にしたVMではACPI電源要求を通常のpoweroffとして扱い、設定変更時にlogindをreloadする。物理desktop・laptopでは電源キーを無視する。
AtCoder Goは`modules.atcoder-go`で有効化し、project scaffold（devenv・CLI source・template）と統合CLI `atcoder-go`（init/sync/version/new/test/submit/snippet/login）をmoduleに同梱する。`atcoder-go.{goPackage,devenv.enable,nixDirenv.enable,projectGoPackage}`でtoolchain・devenv導入（既定true）・direnvを選択できる。`projectAssets`は既定`./assets`、独自scaffoldへの上書きも可能、null時はscaffoldせず、init/syncはgo.modを記録どおりに使う。認証は配布しない。
`hermes-desktop.{url,ssh}`はHermes Desktopの初期接続先で、有効時はちょうど一方を指定する。`url`はdashboard URL、`ssh`は`user@host[:port]`で、ユーザーのSSH鍵を使い接続先でapp専用dashboardを起動する。connection.jsonが無い場合だけ書き、認証・既存接続registryは管理しない。
`immich-client.watchDirectories`は起動時に再帰uploadし、以後監視するディレクトリで、既定nullは各ユーザーのXDG Pictures（`xdg.userDirs.pictures`）を使う。user serviceは`~/.config/immich/auth.yml`（`immich login <url> <api-key>`で作成）がある場合だけ起動し、認証情報は管理しない。
`discord.{commandLineArgs,service.killMode}`、`zed.{installEditor,userSettings,codexAcp.npmPolicy}`、`vscode.userSettings`、`fcitx5.keyboardLayout`も公開入力を使う。Zedの既定npm policyはunmanaged、bounded-offlineはcache優先・retry/timeout制限を選ぶ。SSH接続先専用ホストは`zed.installEditor = false`でZed本体を入れずsettings.jsonだけを管理する。
`pi.{settingsMode,systemWide}`で宣言的/既存優先mergeと全system userへのCLI導入を選ぶ。pi-sessions extensionのrevision/hashは共有module側で固定する。`pi.plugins.<name>.enable`（各既定true）で同梱extensionを個別選択する。公開switchと導入先は`modules/pi/resources.nix`のカタログから生成する。Pi MCP Adapterはnpm packageをversion固定（`modules/pi/resources.nix`を参照）で導入し、`plugins.pi-mcp-adapter.enable`で選択する（npm依存はPiが導入）。pi-review・pi-usage・pi-keep-going・pi-mermaid-studioもrevision/hash固定で同梱する。Mermaid StudioのSSH閲覧は実URLの動的portを使い、AGENTSがlocal転送コマンドとtoken付きURLの案内を促す。agent共通AGENTS.mdで、過去session再利用、context-modeでの大出力処理、subagent分割、edit失敗時の読み直しを促す。管理pluginは生成manifestの自動探索で読み、mergeで保持したpackagesに依存しない。merge時は `context-mode-1.0.169` のstore-path string登録だけを除去し、明示filter付きobjectや他のpackageを保持する。mergeは非object/不正JSONを保存せず、user所有0600でatomic更新する。認証・履歴は触らない。
`claude-code.contextMode.enable`（既定true）でcontext-mode MCP serverを選ぶ。`claude-code.lsp.{nixd,rust-analyzer,gopls}.enable`（各既定false）でホストpkgsのlanguage serverをClaude CodeのLSPへ登録する。packageは`attopkgs.claude-code`（sadjow/claude-code-nixをrevision/hash固定）。claude-code/context-modeのunfree許可は利用側、settings.json・認証・履歴は管理しない。
`skills.<name>.enable`（各既定true）でPi・Claude Code共通のskillを個別選択する。skillごとの取得元と対応agentは`modules/skills/catalog.nix`、取得repoの固定は`modules/skills/sources.nix`に置く。pi-mermaid-studio（Pi tool依存）・find-skills（npxでNix管理外へ追加）・ctx-upgrade（Nix管理installの書換え）はPiだけへ導入する。
`openssh.{settings,listenAddresses,startWhenNeeded,openFirewall,waitForNetwork,listenServices}`はserver policyとlistener順序を選択する。listener/socket/firewallの未指定値はnative設定に追従し、明示した値だけを転送する。`listenServices`は既定[]で、指定したnetwork setup serviceをlistener/socketのwants/afterへ追加する。

Noctaliaのsystemd launcher、PipeWire virtual sinkは共有側が実装し、consumerが公開入力を選択する。サーバーの入力・運用条件は
[Wikiの公開サービスAPI](https://git.attodao.cc/AttODao/attos-nix-modules/wiki/module-public-services)と各moduleページに記載する。

### SSH client

`modules.ssh.enable = true;` で、全HMユーザーへ共通接続先を設定する。
`attofort` / `attobox` / `git` / `github` を利用でき、
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
`~/.ssh/config` の手編集は次回activationで置き換わる。
鍵・known_hostsは管理せず、sshd・firewall・認証policyも変更しない。

## ホスト状態レポート（NixOS）

`modules.host-report.enable` はrootのtimerで15分ごとにホスト状態とjournalの認証兆候を集計し、
`/var/lib/host-report/<host>.json` をatomic更新する（生ログ・秘密鍵・sudo引数は出力しない）。
`readerGroup`（既定null）は既存の閲覧group、`onCalendar` は収集時刻。
`publish.{enable,address,port}` は自ホストJSONだけの静的HTTP配信（既定無効、address必須、port 9180）。
`fetch.<host>.url` は信頼する内部link上の他ホストのJSONをrootで取得する。firewallは利用側で限定する。
`alert.{enable,to,from,sendmail,repeatInterval,staleAfter,authFailures,diskPercent,smartPercentageUsed,diskWritesPerDayGB}` はsendmailによる
新規・継続・解消通知（既定無効、宛先必須、間隔86400秒・鮮度3600秒・認証失敗20件/run・disk 90%）。
SMARTはmodel・温度・稼働時間・exit statusの意味、NVMeのcritical_warningとビットの意味・percentage_used・spare・累積書込bytes・media errors、ATAの主要raw属性を保存する（serialは含めない）。
失敗通知には具体的なSMART値を含める。`alert.smartPercentageUsed` は既定80（1–255、nullで無効）、NVMeの寿命使用率が以上なら `smart-wear/<device>`、spareがthreshold+10ポイント以下でも警告する。
`disk_writes` は実ディスクの書込量、`swap_io` はpswpin/pswpoutを直近24時間のbytesで記録する。
`alert.diskWritesPerDayGB` は正整数またはnull（既定null=無効、decimal GB）。24時間分の履歴が揃い、観測した書込量が超過すると `disk-writes/<device>` を通知する。
再起動・カウンタ減少の区間は破棄し、履歴不足時は通知しない。24時間境界をまたぐ区間を含めず外挿もしないため、`observed_seconds` と `window_complete` を併記する。schemaは1のまま、新fieldを持たないpeerも読み取れる。
`logChecks.<name>.{units,pattern,ipPattern,failure}` は有効なnative serviceだけに追加するjournal checkの調整入力。
SSH成功・sudo・Fail2banは認証失敗とは別集計。直近24時間の件数と前回cursorをroot専用stateに保持する。
閲覧側の管理権限・ネットワーク制限は緩めない。[Wiki](https://git.attodao.cc/AttODao/attos-nix-modules/wiki/module-host-report)参照。

## サーバー機能

公開サービスは、enableを含む独自設定を一つのnamespaceへ集約する。

```nix
modules.public-services."vault.example.org".vaultwarden = {
  enable = true;
  host = "service-host";
  backendUrl = "http://10.0.0.2:8000";
  dataDir = "/srv/vaultwarden";
  environmentFile = "/run/secrets/vaultwarden.env";
};
```

対応サービス: `forgejo`, `immich`, `karakeep`, `vaultwarden`, `opencloud`, `mcsmanager`,
`jellyfin`, `ollama`（任意のOpen WebUIを同梱）, `searxng`, `attos-hoyo-dashboard`, `mailserver`, `groupware`, `wireguard-server`,
`paseo`, `ccpocket`, `ssh`, `code-server`, `hermes`, `strata`。
DNS・公開CNAME・Traefikはこのnamespaceから導出し、consumerの `public-hosts.nix` をimportしない。
`deploy = false` はendpoint登録のみで、local unit・秘密・保存先を要求しない。
HTTPサービスは有効時に `backendUrl = "http://<address>:<port>"`（port明示）が必須。gatewayのupstreamであり、Dockerサービスの所有OSはcontainerをこのaddress:portへpublishする。native service（Forgejo・Immich・Vaultwarden・OpenCloud・Jellyfin・SearXNG）はこのaddress:portでlistenし、`127.x`以外ならfirewallをこの宛先address・portだけ開ける。
通常は `private = false`（SSH endpointとMCSManager・Hermesの管理面は既定true）。`private` はサービスごとの指定で、そのサービスのgateway HTTP/TCP routeをallowlist制限する。同じhostnameでpublicとprivateのサービスを併用でき（例: mailserverを公開したまま `groupware` のWebだけprivate）、公開CNAMEからは有効なサービスがすべてprivateのhostnameだけを除外する。

`public-services.<FQDN>.<service>.privateExtraNetworks`（非空文字列のlist、既定`[]`）は、そのprivate HTTP routeだけに`modules.traefik.privateNetworks`からの追加許可を与える。非空なら`private = true`必須。TCP/UDPやstandaloneには適用せず、firewall・routing・認証も変更しない。

Forgejoは同じhostnameでWebとSSHを提供する。公開時、所有OSはForgejo内蔵SSH server（user `git`）を `backendUrl` のaddressの2222でlistenさせ、TraefikがTCP 22からそこへ中継する（`private` はHTTPと共通）。`forgejo.sshAddresses`（既定[]=全address）を指定するとTraefikはそのgateway addressごとに22でlistenしてfirewallもそのaddress宛てだけを許可し、local DNSもそのhostnameへ `ingressAddresses` のうち一致するaddressだけを返す。同じ22を使うhost sshdは別addressへbindする。`forgejo.trustedProxies`（IP/CIDRのlist、既定loopbackのみ）は`X-Forwarded-*`を信頼するproxyで、公開時は`backendUrl`へ接続してくるgateway（Traefik）のaddressを利用側が列挙する。未指定のままではclient IPがgateway addressとして記録される。

Traefikの`accessLog.enable`（既定false）は`/var/log/traefik/access.log`へ最小JSONログを記録する（header・queryは保存しない、日次rotation、`accessLog.rotate`は既定7世代＋現行）。`fail2ban.enable`（既定false、access log必須）は公開registryのForgejo・Immich・Jellyfin・AttOsHoYoDashboardの検証済みログイン失敗だけをhostname・method・path・statusで絞り、gatewayの`traefik-auth` jailで全port・protocolを遮断する。既定は10分10回・1時間（反復時延長、最大1日）で、調整は標準`services.fail2ban.jails.traefik-auth.settings`、信頼IPはconsumerの`services.fail2ban.ignoreIP`を使う。Vaultwardenの400は正常な2FA要求とも重なるため数えない。その他の未対応サービス・メール/Forgejo SSHのTCP認証失敗は検出しない。根拠・制約は[Wiki](https://git.attodao.cc/AttODao/attos-nix-modules/wiki/module-traefik)を参照。

Traefikは全HTTPS routerにHSTS（1年、subdomainを含まない）と`nosniff`のheader middlewareを付け、TLS 1.2未満を拒否する（frame/CSP等のpolicyは各applicationが持つ）。`traefik.listenServices`（既定[]）はlistenerがbindするaddressを作るnetwork setup service（WireGuard等）で、Traefikのwants/afterへ追加する。

SearXNGの公開 `searxng.limiter`（既定true）はrate limiter・bot対策をlocal Valkey socket付きで有効にする。falseはscrapingに晒すため、loopbackからしか届かない単独利用でだけ検討する。`trustedProxies`（文字列list、既定[]）はclient addressを判別するために `X-Forwarded-For` / `X-Real-IP` を信頼するreverse proxyのaddress/CIDRで、loopbackは引き続き信頼する。`passNetworks`（文字列list、既定[]）はlimiter・bot対策を除外して無制限のAPI利用を許すclient address/CIDRで、信頼する自動化hostなど最小範囲に絞る。どちらも `limiter = true` が必要。`environmentFile`の`SEARXNG_SECRET`は必須で、未設定ならsettings生成前にunitが失敗する。
OpenCloudの公開共有linkは既定でpasswordを必須にする（`OC_SHARING_PUBLIC_SHARE_MUST_HAVE_PASSWORD=true`）。Jellyfinの保存先は`jellyfin:jellyfin` 0750で作る。
attos-hoyo-dashboardの `timezoneOffset`（`+09:00`形式、local配置時必須）はdailyリセット時刻の固定UTC offsetで、`time.timeZone`から導出しない。DBはimageが作る`POSTGRES_USER`（superuser）で接続する。任意の `metricsEnvironmentFile` は `METRICS_TOKEN=…` を含むdotenvのruntime pathで、app containerだけに渡す。設定したときだけ `/metrics` がBearer token付きで公開される。

OpenSSH serverの公開 `modules.openssh.passwordAuthentication` は既定false。trueならpassword/PAM keyboard-interactiveを許可し、falseと矛盾するnative認証上書きは拒否する。listener・firewall・AllowUsers・root login policyはconsumerが標準NixOS optionで設定する。
Vaultwardenの公開 `signupsAllowed` は既定false。false時はそれを上書きするdomain whitelistも空にする。whitelistはSSOと共有され、SSOの実効domain制限への影響は別途確認する。設定はNixと `environmentFile` だけが正で、`CONFIG_FILE` を読み書きできないpathに向けるため既存 `dataDir/vw-data/config.json` は読まれず、adminパネルの設定保存は永続化しない。

MCSManagerはnative web/daemonを別の非root accountで動かし、Docker socketを渡さない。`dataDir`、既存 `webUser` / `daemonUser` / `group`、runtime `daemonKeyFile` をconsumerが供給する。`generateDaemonKey=true`（既定false）は `dataDir/daemon-key` をroot 0600で初回のみatomic生成し、既存keyを置換しない。この場合 `daemonKeyFile` はnullまたは同pathに限る。管理 `backendUrl` / `daemonBackendUrl` は同じprivate HTTPS hostnameのwebと `/daemon/`（prefixをstripしない）へproxyする。`listenAddress` は既定loopback、management portは自動で開けない。`backendAddress` / `tcpPorts` / `udpPorts` は独立したゲーム公開で、privateはゲームを非公開にしない。初期管理者はprivate初期化UI、または任意のruntime `initialAdminFile`（userName/bcrypt passWord hash）で作成し、既存usersは保持する。

Hermesはupstreamのrelease（`flake.nix`の`hermes-agent` tag、`flake.lock`を参照）のNixOS module（`services.hermes-agent`、native systemd）で、gateway（cronを実行）の`hermes-agent`とdashboard（ブラウザChat/TUI）の`hermes-backend`を動かす。公開入力は `hermes.{dataDir,user,group,backendUrl,apiServerBackendUrl,readOnlyPaths,sandbox}`（`dataDir`はlocal配置時必須、`user`/`group`は既定`hermes`の既存account、`backendUrl`は有効なrecordで必須）、公開recordは `private = true` 必須。`apiServerBackendUrl`（既定null）を指定すると、同じhostnameの`/api-server/`をprefixを外してgatewayのAPI server（OpenAI互換、既定8642）へ中継し、dashboardと同じprivate allowlistを付ける。API serverの有効化・bindはruntimeの設定で、このoptionは行わない。`dataDir`がHOMEで、`HERMES_HOME`は`<dataDir>/.hermes`、作業directoryは`<dataDir>/workspace`。dashboardのbindは既定で単独時`127.0.0.1`、公開時`0.0.0.0`。`services.hermes-agent.backend.host`で変更する。`sandbox = true`（既定）では`users.users.<user>.linger`は禁止（user managerのcron workerがsandbox外で動くため。無効時cronはgateway内で動く）。
両unitは`hermes.sandbox = true`（既定）で既定拒否のsandboxで動く。`/mnt` `/media` `/srv` `/opt` `/var` `/run`をtmpfsで空にし、`ProtectHome = "tmpfs"`で`/home` `/root`を隠し、`dataDir`をread-write、明示した`hermes.readOnlyPaths`（絶対pathのlist、既定[]）をread-onlyでbindする（`bash -l`用の`/run/current-system`、glibcが`/var/run/nscd`で探すnscd、systemd-resolvedの`/run/systemd/resolve`はread-only）。`ProtectSystem=strict`、`NoNewPrivileges`、capabilityなし、`PrivateDevices`、`ProtectProc=invisible`。Hermesはsudo・`trusted-users`を持たず、`nix shell nixpkgs#...`と、`extraPackages`の`nix`・`devenv`で作業ごとの環境を宣言的に組む（upstreamの実行時tool `nodejs`・`ripgrep`・`ffmpeg-headless`も入れる。terminalの`bash -l`がpackage wrapperのPATHを外すため）。宛先の制限（private network・localhost）はhost固有値なので利用側のfirewallで行う。
upstreamはactivation時に`config.yaml`へNixの`settings`（既定は`terminal.cwd`のみ）をdeep mergeし、`.managed`を置く。他のkey、`.env`、認証・履歴は変更しない。両unitは`HERMES_MANAGED=false`とHermesのmanaged scope（`HERMES_MANAGED_DIR`）で、Nixが書くkeyだけを固定し、他のkeyはHermesが`hermes config set`で変更できる。sandbox有効時のunit外のshellは`.managed`により全keyが変更不可のまま。`sandbox = false`はOS全体がHermes専用の信頼境界（専用container等）の場合だけ選ぶ。両unitから全filesystemが見えるため`readOnlyPaths`は空必須で、linger禁止も適用しない。upstreamの`NoNewPrivileges`・`ProtectSystem`・`PrivateTmp`も無効にし、gatewayの子として動くagentのtoolが利用側で許可されたsudo・system全体への書込みを使えるようにする。`/tmp`はSSH sessionと共有する。CLIとpython3をsystem-wideに導入し、全PAM sessionへ`HERMES_HOME`・`HERMES_MANAGED=false`・unitと同じ`HERMES_MANAGED_DIR`をexportする。login shellとHermes DesktopのSSH接続（remoteで`hermes serve`を起動）がgatewayと同じstate・managed scopeを使う。provider/model、内蔵password認証、`dashboard.public_url` / `trusted_proxies` はoperatorがruntimeでbootstrapし、その後dashboardから編集する。内蔵password認証はVPN/trusted network専用。proxyの実IPをtrustする。詳細は[公式dashboard](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/web-dashboard.md)。

### 複数マシンへの配置

各サービスの `host` に実際の `networking.hostName` を指定する。有効時は必須。
複数OSで同じnamespaceを共有でき、`enable && deploy && host一致` の実体だけが起動する。
`deploy` は全サービスで既定true。通常は `enable` と `host` だけで選択し、
`deploy = false` は管理外endpointの登録に使う。
DNS・CNAME・gatewayは配備先によらず有効な全endpointを参照する。
`host` はSSH aliasや親ホスト名ではなく、サービスが動くOS自身のhostname。

保存先・runtime secret等のlocal必須値は所有OSだけで要求する。
backendの到達性、firewall、ユーザー・secretsの供給はconsumerが管理する。
Traefikはgateway host上のnative serviceで、各 `backendUrl` へ直接接続する。Open WebUIはTerminalと同じhostのlocal Docker bridge `backend-open-terminal` で接続し、SearXNGへは有効なSearXNG recordの `<backendUrl>/search` で接続する（containerから届くaddressを選ぶ）。WebUIの `backend-ollama` bridgeはinterface名 `br-open-webui` 固定で、host Ollamaへの許可はconsumerのfirewallで行う。
同一host上のlocal deploymentはサービス種別ごとに1件まで。Groupwareの暗黙Mailserver依存も同じhostを継承する。

code-serverも `enable = true; host = "<所有OS>";` でnative実体を有効にする。
単独利用は同じtyped入力を`modules.code-server`へ指定する。
code-serverは既定password認証でruntime `environmentFile` が必須（`PASSWORD` または
`HASHED_PASSWORD`）。単独利用は127.0.0.1:4444、公開時は他のnative serviceと同じく `backendUrl` のaddress:portでlistenする（全interfaceへbindしない）。更新・telemetryは既定無効で、保存済みの設定・認証は上書きしない。
Nerd Font組み込みpackage（`attopkgs.code-server { src = <固定したstandalone release>; }`）は、
公開 `code-server.packageSource` にstandalone releaseを渡して選ぶ。`user` / `group`も公開入力で、account作成・権限はconsumerが保持する。

OllamaとOpen WebUIは`modules/ollama/`で一つのmoduleとして扱う。公開`modules.public-services.<FQDN>.ollama.enable`は所有OSのbackendを有効化し、同じrecordの`webui=true`で任意のWebUIも有効化する（既定false）。WebUI無効時はUI用Docker/Terminal・secret/path・HTTP proxy routeを作らない。WebUIは独立したrecordを持たず、container/unit名は`open-webui`を使う。`modules.ollama`は以下の単独利用入口としても使用できる。既存Paseoはpublic-to-global bridgeを保持する。

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

native serviceは127.0.0.1でlistenし、OCI frontendはloopbackだけへportをpublishして通常Docker bridgeを使う（Open WebUIだけはhost networkで127.0.0.1へbind）。data/credential等の既存必須入力はcallerが供給する。対応port・native mail TLS・WebUIの任意連携・SSH scopeは[public-services Wiki](https://git.attodao.cc/AttODao/attos-nix-modules/wiki/module-public-services)を参照。Paseoは既存`modules.paseo`（hostname既定localhost）、SSH serverは`modules.ssh.server.enable`（`modules.ssh.enable`はclient）。WireGuardのinterface/address/keyとfirewall policyはnative入力としてcallerが保持する。
保存先・秘密・公開hostname・subscriptions・WireGuard clients・Incus instance定義はconsumerが所有する。
サーバーの追加入力は`dns.listenAddresses`、公開`ollama.{package,home,modelsDir,listenAddress,port,loadModels,environmentVariables,webui}`（`host`は所有OS、`listenAddress`はbind）、`incus.{package,preseed,initrdKernelModules,preseedKernelModules,rebuild.flake}`。
WireGuardのsync identity/group/runtime modeとIPv4 forwarding、MailserverのsystemName/ACME、GroupwareのproductName、Vaultwardenの`extraHosts`（hostの`networking.hosts`へ追加）、Karakeepの非秘密environmentも公開service recordへ指定する。
Incusの公開 `guests.<name>.{type,launchConfig,managedDeviceNames}`（`type` は `virtual-machine` / `container`）はhost activationでは適用せず、`guest <name> boot|stop|delete|rebuild [action]` で明示的に操作する。`boot` は不足guestだけ `rebuild.flake`（registry別名やgit URLなどのflake参照。毎回最新を取得し、`rebuild ACTION FLAKE` か `--flake` で上書き可能）の標準NixOS metadataとVMならqcow2、containerならsquashfsをbuild・importして作成し、作成用imageを削除する。同名の別type instanceは削除/変換せず拒否する。consumer guestは標準 `incus-virtual-machine-image.nix` / `incus-container-image.nix` とroot password lockを明示する。初期login password/private fileの再供給は `guest <name> passwd <user>` / `guest <name> push-file <user> <source> <home-relative-path>`。bootstrapは既存認証を上書きせず、file配送はuser権限で行う。storage wipeはactivationとは別工程。
Forgejo runnerは有効化したhostで動き、jobはDocker containerで実行する。Forgejoのuser/org runnerとしての登録scopeが信頼境界になるため、hostを信頼して任せられるownerだけに登録する。nixpkgs標準 `services.forgejo-runner` を使い、Forgejoの「新しいランナーを作成」で得た `uuid` と、対になるtokenだけを含む `tokenFile` が必要（廃止された登録トークンには非対応）。`docker=false` はhost実行専用runner用。`url`（既定null）は接続先Forgejo URLで、nullならstandalone instanceまたはpublic-servicesに登録した単一hostnameから導出する。`fetchInterval`（既定null）は `runner.fetch_interval` で、nullはrunner既定の2秒を使う。同じlabelの別runnerより長くすると、そのrunnerが停止中・busyのときにjobを拾いやすくなる。`jobLimits.cpus` と `jobLimits.memory`（ともに既定null）はjob containerのDocker `--cpus` と `--memory` で、nullは無制限。memory指定時は同値の `--memory-swap` も設定しswapを使わせない。`dockerHost`（既定null）は `container.docker_host` で、nullは `-`（socketを渡さない）。`"automount"` はhostのDocker socketを全jobへmountし、workflowにrunner hostのrootを与えるため明示opt-inに限る。Incus guestへのfile配送は `incus.guests.<name>.credentialFiles`（既定{}）のguest絶対destination→host runtime sourceを使う。値はsource pathの文字列
Karakeep/ChromeのOCI version/index digestとPaseo 0.12.0を固定し、runtime latest取得をしない。Forgejo（LTSでなく`forgejo`）・Immich・Vaultwarden・Jellyfin・SearXNG・ytdl-subは利用ホストのnixpkgsのpackageを使う。OpenCloud（rolling）は利用ホストのnixpkgsのgeneric.nixで9.0.0を組む`attopkgs.opencloud`を使い、nixpkgsが9.0.0以上になったらそちらに切り替わる。既存dataを作ったversionより古いpackageへ戻さない（Karakeep・Open WebUIはnixpkgs版がimageより古いためDockerのまま）。
localサービスの必須値、Docker依存、既存stateの扱いは[Wiki](https://git.attodao.cc/AttODao/attos-nix-modules/wiki)の各moduleページを参照。

## ホスト側に残すもの

機器固有の音声設定、Steamのfirewall policy、Wallpaper Engine assets、unfree licenseの許可は利用側で管理する。
公開APIがある機能はそのoptionで選択し、package導入だけのアプリ、標準OBS設定、外部AAGLは利用側に残す。
`modules.openssh.enable` はserver有効化、`modules.ssh.enable` はclient設定で別の選択。
login-pinは`login-pin.user`に指定した1 accountのgreetd / TTYに限定する。
Open-Deckのupstream desktop entryは `--no-sandbox` を使うため、Electron sandboxは無効。

## 自動更新

Forgejo Actions（`.forgejo/workflows/update.yml`）が毎週土曜03:00 JST（手動実行も可）に更新PRを作る。Actionsは何もbuildしない。jobは共有Docker runner（label `docker`）上の固定digestの `nixos/nix` containerで動き、repoは `git clone` で取得する。secretは `BOT_TOKEN`（PR作成用bot account）だけで、使うstepにだけ渡す。3つのjobは `needs:` で直列に走る（複数ホストの評価を共有runnerで並列に走らせるとOOMするため）。評価する利用側ホストの一覧は手動実行時のinput `consumers` で上書きできる。PRのタイトル・本文は日本語。

- `update/flake-inputs`: HM revision・hermes-agent release tag・flake.lock。
- `update/packages`: version固定のcustom package（Open-DeckのAppImage、CC Pocket Bridgeを含む）、Pi plugin catalog（`modules/pi/resources.nix`）とskill repo（`modules/skills/sources.nix`）の固定。StrataのAPI専用image（`modules/strata/nixos.nix`）はRenovateの対象外で、registryのtag一覧から全flavorの`<version>-<flavor>`が揃う最新の数値版を選び、tag・digestをまとめて更新する。取得失敗や揃う版がない場合はimageの固定を変更しない。
- OCI image: Renovate（`renovate.json`）がmodule内の `image = lib.mkDefault "name:tag@sha256:..."` とForgejo runner labelの `docker://name:tag@sha256:...` をimageごとのPRで更新する。PostgreSQLのmajor更新はdump/restoreが必要なため無効。

flake input・packageのPRは、`nix flake check --no-build` と利用側全ホストの `--override-input` 評価（buildなし）を通してから作る。処理は `attos-ci`（[packages/README.md](packages/README.md)）。
mergeは手動。必要ならmerge前にホストで `nixos-rebuild build` する。利用側は各repoの週次更新PR（土曜05:00 JST）でpinを上げて採用し、各ホストが自身でbuild・適用する。
共有runnerは外部のjobも実行するため、このrepoと利用側repoのmainはbranch protectionでbotにPR作成だけを許す運用を推奨する。

## 検証

このrepoはテストを持たない。変更時は次の評価で確認する。

```sh
nix flake check --no-build 'path:.'
nix eval --raw 'path:.#packages.x86_64-linux.<name>.drvPath' # 変更したpackage
```

利用側では `--override-input shared "path:$(realpath ../attos-nix-modules)"` を付けて全OS・HM・imageを評価する。
