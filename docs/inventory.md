# 共通化候補のモジュール別調査

[移行計画・共有方法へ戻る](./README.md)

## 表の読み方

- **L**: `.dotfiles`（attodesk / attolap）、**S**: server（attofort / attobox）、**D**: dev（devcon、Nix出力名development）、**R**: remote（desktop）。commitは[計画書](./README.md#1-調査対象と確認できた範囲)に記録。
- feature表の`repo: category/name/file.nix`は、そのrepoの**`modules/features/`からの相対パス**。例: `L: development/pi/home.nix`は`modules/features/development/pi/home.nix`。
- `H`はHome Manager、`N`はNixOS。単純に同名moduleをまとめるのではなく、option・生成設定・起動経路を比較した。
- **A**: 別repoにも設定の重複がある。優先して抽出する。
- **B**: 同repo内の複数hostでは共有済み。共通repoへの移動は候補だが、初回は必須ではない。
- **保留**: 一台のみ、または同名でも役割が別。初回はローカルに残す。

共有対象はAttODaoの共通ポリシーであり、万人向けの汎用設定集を作る作業ではない。共通のメールアカウントやサービスURLは共有できるが、credentialと権限は別扱いにする。

## 1. CLI / 開発 / 接続

| module・優先度 | 比較した設定本体 | 共通化する内容 | ホスト側へ残す差分・注意 |
| --- | --- | --- | --- |
| **zsh / A / H+N** | L/R: `system/zsh/{home,nixos}.nix`、D: `system/zsh/{home,nixos}.nix`、S: `applications/zsh/nixos.nix` | Hのenable・autosuggestion・syntax highlightingはL/D/Rで同一。Sにも同じ機能のN設定がある。HとNの薄い設定を分ける | L/Rの`users.users.attodao.shell`、D/Sのcore側ユーザーshellはローカル。Nの`autosuggestions`とHの`autosuggestion`は別optionで、文字列置換で統一しない。`environment.shells`の差も維持 |
| **starship / A / H+N** | L/R: `development/starship/home.nix`、D: `system/starship/home.nix`、S: `applications/starship/nixos.nix` | Gruvbox palette、format、言語表示、directory置換、time、character等の`settings`全体が同一。`data/starship.nix`等へ一度だけ置く | Hの`enableZshIntegration`はH adapterへ。SにはHMを入れず`programs.starship.settings`へ共通データを渡す |
| **pi / A / H+N** | L/D: `development/pi/{home,package,context-mode}.nix`、D: 同`nixos.nix`、S: `applications/pi/{nixos,package,context-mode}.nix` | Pi 1.0.2 overrideとcontext-mode 1.0.169 overrideは3 repoで完全一致。ponytail v4.10.3、context-mode登録、defaultTools、autoTitle refreshTurns、tmux/bunも共通 | Lはhost pkgs、S/Dは専用`pi-nixpkgs`。pi-sessionsはL/Dが`3f7cd30…`、Sが`80970d0…`で同一ではない。Sのユーザーhome/tmpfiles/可変JSON merge、DのPaseo向けoverlay、HMのconfigDirは各adapterへ。RにはPi featureがなく、新規導入しない |
| **SSH client / A / H+N** | L/D/R: `networking/ssh/home.nix`、S: `applications/ssh/nixos.nix`。接続先データはSの`modules/nixos/core/public-hosts.nix` | ControlMaster/ControlPersist/ControlPath、keepalive、accept-new等の共通設定。L/D/Rのconfig生成・600で実ファイル配置・ssh wrapperはほぼ同じ。接続先の重複部分も共有データ候補 | Sはsystem設定からFQDN hostを生成、Hはaliasを持つ。SSH clientとsshdを別exportにする。全`public-hosts.nix`を移すのではなく必要なSSHデータだけを候補にする。実ファイル配置/owner-check回避を消さない |
| **OpenSSH server / A / N** | S/D: `services/openssh/nixos.nix`、L/R: `networking/ssh/nixos.nix` | S/Dのenable、PasswordAuthentication=true、KbdInteractiveAuthentication=true、UseDns=falseはコメントとmodule引数の有無を除けば同一。ここはそのまま抽出できる | Lはenableだけ。RはAllowUsers、root禁止、keyboard-interactive無効、openFirewall=false、eth0だけ22許可。S/Dの認証policyをL/Rへ自動適用しない。共通のserver起動と認証policyは区別する |
| **nix-ld / A / N** | S: `applications/nix-ld/nixos.nix`、D/R: `system/nix-ld/nixos.nix` | 有効化を共有。D/Rの共通libraryはstdenv.cc.cc、openssl、zlib、zstd、curl、libxml2、libcap | Sはlibraryの追加指定なし。Dはnodejs、RはGL/Wayland/X11/audio/fliteを追加。library全体の和集合を全hostへ配布しない。共通library listを採用する場合もSの実効値が変わる点を別変更として扱う。Lは未導入 |
| **paseo / A / N** | S/D: `services/paseo/nixos.nix` | Piだけを有効にするprovider設定、relay/MCP/voice/webUI設定、npx launcher、systemd unit、0700/0600、env file必須、configのrestartTriggers、再起動処理 | Sはattodao・public-hostsからhostname取得、Dはdev・devcon hostname固定。SのPATHにはtmux/bun/context-modeがあるがDにはない。user/home/hostname/env pathの少数option化は有用。`npx @latest`の固定化は別作業 |

### SSH clientで「表記差」と「実際の差」を分ける

- L/DのHost節の順番、共通`Port 22`の重複、derivation名`attodao-ssh-config`/`dev-ssh-config`は、そのまま機能差とは扱わない。ただしHost patternの優先順位は一般には意味があるので、生成後の`ssh -G`も確認する。
- Lは`git.attodao.cc`に`IdentitiesOnly yes`。Dではこの指定が`github.com`側にあり、Gitサーバー側にはない。DだけのGitHub節もある。**ここは意味的差分**。
- Rのattobox/attofort/devcon/desktop節はIdentityFileを明示しない。既定鍵で同じ結果になることはあっても、L/Dと同一設定とは断定しない。
- Sにはsystemd-ssh-proxy includeを無効にするowner-check回避がある。Hのwrapper/activationと同じ目的でも、配置する層が違う。

## 2. デスクトップ / マルチメディア

ここでLと書いた共有moduleは、特記がなければattodeskとattolapの両方で有効。

| module・優先度 | 比較した設定本体 | 共通化する内容 | ホスト側へ残す差分・注意 |
| --- | --- | --- | --- |
| **foot / A / H** | L/R: `desktop/foot/home.nix` | 完全一致。foot/server有効、Inconsolata 11、alpha=0.65 | font/size等は`mkDefault`でローカルoverride可能にする |
| **fonts / A / N** | L/R: `system/fonts/nixos.nix` | 完全一致。Inconsolata Nerd Font、Noto CJK、fontconfigのsans/serif/monospace既定値 | D/Sへデスクトップ用fontを自動導入しない。package listもあるがdefaultFontsという設定があり、今回の対象 |
| **floorp / A / H** | L/R: `networking/floorp/home.nix` | 完全一致。floorp-bin、Sync対象、password/autofill制限、検索、vertical tabs/gesture、拡張強制導入、Vaultwarden接続先 | OpenDeck拡張を含むので関連導入を確認。ユーザーのbrowser profileデータ自体は移さない |
| **obs-studio / A / H** | L/R: `audio-video/obs-studio/home.nix` | 完全一致の`programs.obs-studio.enable` | 一行でもpackage列挙だけではないため対象。LのfeatureはPipeWire依存を明記、Rは明記しないがPipeWire feature自体は有効。依存機能を落とさない |
| **pipewire / A / N** | L/R: `audio-video/pipewire/nixos.nix`、L: `hosts/attodesk/audio.nix` | rtkit、PipeWire、ALSA、Pulseの共通有効化 | Rの`99-sunshine-sink`はdesktop固有。LのKURO loopback/Scarlett設定はattodesk固有で既にhost側。device名、buffer値、仮想sinkは共通moduleへ混ぜない |
| **desktop-theme / A / H** | L/R: `desktop/desktop-theme/{home,cursor}.nix` | `cursor.nix`は完全一致。Yanfei/Xcursor→Hyprcursor生成、size=48、GTK Adwaita-dark/Papirus-Dark、Fcitx/Qt/Wayland環境設定、xprofile/environment.d | Lは`pointerCursor.hyprcursor.enable`あり。Rはhome.sessionVariablesのcursor変数とXresources定義が追加されている。重複注入を整理できるが、現行HM対応とXWaylandで実効値を確認してから。cursor buildを2 repoに残さない |
| **pcmanfm / A / H** | L/R: `desktop/pcmanfm/home.nix`と`pcmanfm.desktop` | desktop entry、Papirus iconのPNG生成、directory MIME default、XDG userDirsの基本形。`.desktop` assetは完全一致 | attodeskだけdataDirectory=/mnt/hdd1、attolap/desktopはhome配下。Screenshots/.keepはattolap/desktopだけ。共有設定からhostName分岐を取り除き、保存先とディレクトリ作成をローカルへ |
| **discord / A / H** | L/R: `networking/discord/home.nix` | enable、fcitx起動待ち、start-minimized、graphical-sessionへの関連付け、restart設定 | Rだけ`--ozone-platform=wayland`のpackage overrideとKillMode=mixed。Lへ適用するなら挙動変更であり、抽出時には維持。遅れているrepo側の改善を消さない |
| **thunderbird / A / H+N** | L/R: `networking/thunderbird/{home,nixos}.nix` | ESR、日本語、minimize addon、profile/settings、IMAP/SMTP/Gmail設定。Nのevolution-data-server/gnome-keyringは完全一致 | Lだけ`mail.shell.checkDefaultClient=false`。共通化後のポリシー追加候補だが抽出と分ける。認証情報・メールの実データは共有しない |
| **OpenCloud client / A / H+N** | L/R: `networking/opencloud/{home,nixos}.nix` | 二重autostart抑止、desktop entry非表示、systemd user service、Wizard ServerUrl。N設定は完全一致 | Lはpkgs.opencloud-desktop、Rは専用opencloud-nixpkgsから供給。起動コマンドが選択packageを参照する形にする。Lはattodeskだけ、attolapは未導入。SのOpenCloud serverとは別module |
| **steam / A / H+N** | L/R: `gaming/steam/{home,nixos}.nix` | Nのenable、Hのsteam/steamlink MIMEは共通。H設定は完全一致 | Lはattodeskだけ。remotePlay/dedicatedServer/localNetworkGameTransfersのopenFirewallはLだけ。Rへportを開く変更にしない。差の意図は確認対象 |
| **SKK / A / H** | L: `system/skk/home.nix`、R: `system/fcitx5-skk/home.nix` | 名前は違うがFcitx5+SKK、addons、Wayland frontend、hotkey、SKK優先group、autostart抑止という同じ機能 | `Name`/`"Name"`は表記差。一方keyboard-usのLayoutはLが空文字、Rがusで異なる。Lに後発の実ファイル化activationとExitType=cgroupがある。Rへの適用は別の修正commitにする |
| **hyprland / A / H+N** | L/R: `desktop/hyprland/{home,nixos}.nix`、L: 同`greeter.nix` | Lua config、UWSM、dconf/gvfs、装飾/blur/border/animation/input/gesture、window/workspace操作、アプリ起動・スクリーンショット・Noctalia操作keybind | attodeskの3画面/HDR、attolapのlid/neowall、実機power/logind/greeterはローカル。Rのseatd/VTBOUND=0/linger、bootstrap、headless moonlight出力、portal defaultはdesktop固有。Rの絶対package path指定とLのPATH依存は表記差でなく実行環境差もある |
| **noctalia / A / H+N** | L/R: `desktop/noctalia/home.nix`、L: 同`nixos.nix`と録画script 2本 | Everforest palette、bar/order/表示、shell/panel、dock基本、天気/所在地、calendar/CalDAV、nightlight、screen_recorder基本、録画dir作成 | Lはnative programs.noctalia、Rは外部Noctalia HM module。LはHyprland startupから起動、Rはsystemd+headless-output待ち。dock editorはLがcode、RがZed。attodeskの追加ゲーム/HDR HEVC/focused録画/自動X用変換、その他のportal/h264を分ける。secret runtime pathとstandalone HMのnull対応も維持 |
| **open-deck-desktop / A・供給方式は保留 / H(+N)** | L: `peripherals/open-deck-desktop/{home,nixos}.nix`、`update-open-deck-desktop.sh`、R: 同`{home,package}.nix`。両repoの`.desktop` | アイコンsource、desktop統合、OpenDeck用途の共通部分。用途は共通だが単純に本文をコピーできない | Lはactivation時にGitHub latest AppImageをhomeへ取得・appimage-run/binfmt使用、Rはv1.0.5+hash固定のwrapType2。desktop entryのExec/Icon/Versionも異なる。方式を選ぶまでは供給adapterを残す。L方式を「最新版だから正」とはしない |

## 3. NixOS基盤 / 同repo内の共有設定

以下はfeature以外のcore設定も含む。ここではパスをrepo rootから記載する。

| 設定・優先度 | 元ファイル | 共通化候補 | 残すもの・境界 |
| --- | --- | --- | --- |
| **locale / A** | L/S/R: `modules/nixos/core/locale.nix` | 3 repoで完全一致。Asia/Tokyo、ja_JP.UTF-8、LC_ALL | Dに同じcore定義はない。導入するかは別判断 |
| **Nix基本 / A** | 全repo: `modules/nixos/core/nix.nix` | allowUnfree、nix-command/flakes有効化 | trusted-usersはLがroot/@wheelのmkForce、Sは通常定義、Rはrootのみ、Dは設定なし。D/Rのsandbox=falseはコンテナ事情。Sのregistry/nixPath/auto-optimise-store、DのAndroid licenseはローカル。L/RのHM CLI package・backup設定はHM連携側へ |
| **networking / 部分共有** | L/S/R: `modules/nixos/core/networking.nix`、D: `hosts/development/networking.nix`、S: `hosts/*/networking.nix` | L/RのNetworkManager、S/Dのnetworkdという機能別の共通部分。必要なら小さなdesktop/networkd profile内へ | hostname、NIC、IP、route、NAT、DNS、port許可を共有baseへ移さない。全hostを同一network managerへ統一する作業ではない |
| **graphics/input / 部分共有** | L/R: `modules/nixos/hardware/{graphics,input}.nix` | hardware.graphics/uinputの有効化。desktop-system profile等に含める候補 | LのDualSense hidraw rulesとgame-devices rules、RのIncus device node/udevdは別。GPU/入力機器の割当・group GIDを共有しない |
| **boot/limine / 部分共有・後回し** | L: `modules/features/system/limine/nixos.nix`、S: `modules/nixos/core/boot.nix` | 物理4hostのLimine有効、systemd-boot無効、EFI、世代数10の共通部分 | LはZen/Plymouth/quiet、SはXanMod/bzImage workaround/initrd.systemd。attodeskのmitigations=off/nowatchdog/performance/amdgpuは固有。コンテナには導入しない。Plymouthのassetとderivationを置き去りにしない |
| **users / ローカル** | 全repo: `modules/nixos/core/users.nix`、L/R/D: `home/*/default.nix` | 同名attodao等があるだけで権限共通とは扱わない | devユーザー、docker/wheel/render/input/uinput等、authorizedKeys、sudo、homeDirectory、stateVersionは各host/userの宣言へ。stateVersionが全て26.05でも共有の可変既定値にしない |
| **SOPS / 実装のみ候補、宣言はローカル** | L/S/R: `modules/nixos/core/secrets.nix` | binary secretのformat/key/mode等の反復はあるが、数行helperを共有API化する必要は薄い | secret集合・owner/group/restartUnits・Age鍵path・sopsFileはローカル。L/Rのcalendar secret、LのPIN、Sのサービスsecretを一括配布しない |
| **container base / 小部分共有・後回し** | D: `hosts/development/container.nix`、R: `hosts/desktop/default.nix`、S: `containers/incus/shared/base.nix` | D/Rのboot.isContainerと/sbin/init symlink処理。現状の小さな重複として把握 | Sのbaseはbootstrap image用でsshdをmkForce falseにする別役割。imageを運用後のdev/desktop設定と同じにしない。sandbox例外、devices、init/profileを利用環境ごとに保持 |

### B: 共有リポジトリへ移せるが、既に同repo内で共有されているもの

| module | 元ファイル | 設定内容 | 推奨 |
| --- | --- | --- | --- |
| **vscode** | L: `development/vscode/home.nix` | attodesk/attolap共通のkeybinding変更。Ctrl+J/Q/Spaceの解除、Ctrl+Alt+Spaceのsuggest操作 | 共通repoへ移す候補。RのZedやDのcode-serverと同一視しない |
| **login-pin** | L: `system/login-pin/{module,nixos}.nix`、`check-login-pin.py`、`set-login-pin.sh` | 両実機の6桁PIN/PAM実装、ユーザー/services指定、通常password fallback | module実装とassetは移せる。有効化policyとSOPS/hashの対応はhost側。server/remoteへ自動適用しない。既存optionを再利用 |
| **wireguard-client** | L: `networking/wireguard-client/nixos.nix` | hostごとの暗号化conf検出、ファイル名検証、SOPS、NetworkManagerへの一時import/削除、autoconnect無効 | 汎用のimport service部分は移せる。元repo相対secretsRoot/hostName探索はローカルへ。実際のtunnelがないhostではserviceを作らない現行挙動を維持。SのVPN serverとは別 |
| **docker** | S: `services/docker/nixos.nix` | 両server共通のDocker/OCI backend、weekly prune、latest imageのpull=always assertion、activation時restart | 共通repoへ移すなら設定本体をそのまま。新たなimage update policyは加えない。現時点ではS内の一箇所変更でも両hostへ反映可能 |
| **service-storage** | S: `modules/nixos/core/service-storage.nix` | named storageの型、filesystem/tmpfiles生成、root/mountPoint整合性・重複検証 | 実装は共有できるが他repoにconsumerなし。初回は保留可。disk UUID、root、mount条件はSのhostsへ。サービス側RequiresMountsFor契約を壊さない |
| **bluetooth/thermal/firmware** | L: `modules/nixos/hardware/{bluetooth,thermal}.nix`、S: `modules/nixos/core/hardware.nix` | L両実機のBluetooth/thermald、S両実機のredistributable firmware許可 | 物理host用policyとしてのみ候補。CPU/デバイス/コンテナの違いを無視して全hostへ適用しない |

## 4. 初回は共通化しない設定ありfeature

「設定があること」と「今、複数ホストで同じ設定を使っていること」を区別する。以下はpackage列挙だけの対象外とは別枠。

### L: attodeskだけ / attolapだけ

| featureと主なファイル | 有効host | 調査結果・残す理由 |
| --- | --- | --- |
| `audio-video/musescore-midi/home.nix` | attodesk | MIDI Throughへの接続bridgeとuser service。今は一台のみ |
| `desktop/kando/home.nix` | attodesk | pie menu設定。共有moduleが存在しない他hostへ新規導入する必要なし |
| `gaming/aagl-launchers/nixos.nix` | attodesk | 外部AAGL NixOS module、launcher有効化、cache設定。現在は一台のみ |
| `gaming/linux-wallpaperengine/home.nix` | attodesk | Steam assetsと3画面のwallpaper設定。モニター依存が大きい |
| `gaming/pandora-launcher/home.nix`とPython資産 | attodesk | launcherの取得/起動実装。現在は一台のみ。Lのjdk25導入とは別で扱う |
| `gaming/pipeasio/{home,nixos,package}.nix`とPython/test資産 | attodesk | Wine/Steam環境のASIOとprefix登録。単一hostかつ既存testあり。移す必要が出た時もpackage・登録script・testを一体で扱う |
| `peripherals/solaar/{home,nixos}.nix`、`config.yaml`、`rules.yaml` | attodesk | デバイス設定とKando/Noctalia操作。個体/入力ルールを全hostへ配布しない |
| `system/laptop-power/nixos.nix` | attolap | power-profiles-daemon/upower。ノートPC用途固有 |

### S: サービスの役割分担

以下の主設定は全て`modules/features/services/<name>/nixos.nix`。`hosts`と`requires`を確認した。**両serverに同じサービスがあるわけではない。** 共通のDocker基盤を使うことだけを理由に、サービス固有moduleを別repoへ移さない。

| feature | 有効host | 固有設定・関連参照 |
| --- | --- | --- |
| `cloudflare-ddns` | attofort | DDNS script、env secret、home storage |
| `cloudflare-public-cnames` | attofort | CNAME更新script、public-hosts台帳、secret/storage |
| `dns` | attofort | dnsmasqとpublic-hosts台帳 |
| `forgejo` | attobox | OCI構成、database secret、disk01 storage、Swarm連携 |
| `forgejo-actions-runner` | attobox | runner、登録secret、disk01 storage、Forgejo/Docker依存 |
| `groupware` | attobox | Roundcube/Radicale/nginx、mail-config参照、disk01 storage |
| `immich` | attofort | OCI構成、env、home storage、Swarm連携 |
| `incus` | attofort | Incus/preseed、image/bootstrap、development/desktopのdevice/address定義、WireGuard依存 |
| `jellyfin` | attobox | OCI構成、disk02 storage、ytdl-sub/Swarm依存 |
| `karakeep` | attobox | OCI構成、Monolith patch、env、disk01 storage |
| `mailserver` | attobox | simple-nixos-mailserver import、mail-config、TLS/DKIM/secret、disk01 storage |
| `mineos` | attofort | OCI構成、env、home storage、Swarm連携 |
| `ollama` | attofort | Ollama設定、専用ollama storage |
| `open-terminal` | attofort | OCI構成、env、home storage、Open WebUI向け連携 |
| `open-webui` | attofort | OCI構成、Ollama/Open Terminal/SearxNG連携、home storage |
| **`opencloud` server** | attobox | OCI server・env・disk01 storage。L/Rのdesktop client設定とは用途もoptionも別 |
| `searxng` | attofort | OCI/settings/env、Open WebUI向け検索連携 |
| `traefik` | attofort | public-hosts台帳からrouting、Docker socket/network、home storage |
| `vaultwarden` | attobox | OCI構成、env、disk01 storage |
| `wireguard` server | attofort | clients.nix、鍵/peer同期script、VPN subnet/firewall/DNS。LのNetworkManager clientとは別 |
| `ytdl-sub` | attobox | OCI構成、subscription/cron/config資産、cookie secret、disk02 storage |
| `swarm` | attofort + attobox | `attofort.nix`はmanager初期化/network/token提供、`attobox.nix`はworker join/network待ち。役割が異なり、同じ設定本文ではない。manager address/subnet/役割宣言をS内へ残す |

Sの`public-hosts.nix`はSSH/PaseoだけでなくDNS・CNAME・Traefik・WireGuardに使われる。共有SSHデータを取り出す場合も、インフラ側の名前/公開範囲を無断で統合・変更しない。Sの`containers/incus/*`は運用設定をcloneするbootstrap imageで、D/Rの運用後flakeの代替ではない。

### D: devconだけ

| featureと主なファイル | 設定内容 | 判断 |
| --- | --- | --- |
| `development/android-sdk/home.nix` | SDK/build tools 37、NDK、環境変数、adb USB vendor指定 | SDK設定はpackageだけではないが他hostに同じ設定なし。USB個体側はローカル |
| `development/atcoder/home.nix`、`host/*.nix`、`project/` | Go/AtCoder tools、command、project/template/snippet資産 | 他hostにconsumerなし。現行のプロジェクト配置と可変データを維持 |
| `development/jdk/home.nix` | jdk17とJAVA_HOME | Lのjdk featureはjdk25を追加するだけ。名称が同じでもversion/環境設定は別。Dは厳密にはpackageのみではないが共有対象がないため保留 |
| `services/code-server/{nixos,package}.nix`、`install.sh`、`nerd-font.css` | code-server custom package/font、devユーザー、4444/password auth、runtime env file | LのVS CodeやRのZedとは別。現在は単一hostなので保留 |

### R: desktopだけ

| featureと主なファイル | 設定内容 | 判断 |
| --- | --- | --- |
| `development/zed/home.nix` | autosave、codex-acp reasoning、npx registryのnpmrc | LはVS Codeへ変更済み。editorの選択はhost側に残し、単純にLへ合わせない |
| `gaming/sunshine/nixos.nix` | wlr capture、moonlight出力、Sunshine sink、配信アプリ、解像度prep、eth0 firewall、headless-output依存 | desktopの役割そのもの。今回ローカルに残す |

## 5. remote-dotfilesの差分分類

Rの最終commitは2026-09-21、L/S/Dには2026-10-04の変更がある。ただし、全差分が遅れではない。

| 分類 | 確認した差分 | 進め方 |
| --- | --- | --- |
| **単純な表記差** | SKKのattr keyの引用符、SSH節の異なる並び、S/D OpenSSHのコメント/`{ ... }:`、Starshipのmodule wrapper | formatterと設定データの共通化で吸収。適用対象のlayerは区別 |
| **後発修正の未取り込み** | LのFcitx設定永続化とExitType=cgroup。L履歴`07b9e23`（2026-10-04）に根拠あり | 共通の基礎設定を抽出後、Rへの修正適用を別commitで検証 |
| **module/依存の更新差** | LのNoctalia native化は`028292f`（2026-10-04）、Rは旧外部flake。RのOpenCloud専用package set、D/SのPi専用package set | adapterを残して共通本文を抽出。nixpkgs/HM更新と混ぜない |
| **アプリ選択の差** | LのVS Code、RのZed。Lは`388c31d`（2026-10-04）で変更 | host policyとして保持。dock/keybindの共通部分と分ける |
| **明確なhost固有** | seatd/linger/headless出力、Sunshine sink/port、Incus devices、HDR実画面、lid/neowall、保存先 | 各hostへ残す。Rを実機向け設定へ置換しない |
| **方針を確認すべき差** | Discord Wayland/KillMode、OpenDeck固定版vs動的更新、Steam firewall、SSH鍵/認証、cursor注入箇所、SKK keyboard Layout、Thunderbird既定client確認 | 抽出時は保存。変更するなら目的と確認手順を付けた別commit |

SのPiもL/Dより新しいpi-sessions revisionを持つ。**Lを無条件に正とするのではなく、共通部分と差分を分けてから採用する。**

## 6. 今回の対象外: パッケージを導入するだけのfeature

全59定義。ここでは`modules/features/`以下の**feature directory**を記載する。この一覧の設定共通化moduleは作らず、将来の簡素化でpackage listへ直接まとめる。

### L: 27

- `audio-video/celluloid`, `audio-video/musescore`
- `desktop/app2unit`, `desktop/ark`, `desktop/loupe`, `desktop/mission-center`, `desktop/qt6ct`, `desktop/quickshell`, `desktop/seahorse`
- `development/android-tools`, `development/forgejo-cli`, `development/gh`, `development/git`, `development/jdk`, `development/nil`, `development/nixd`, `development/python-tools`
- `gaming/moonlight`, `gaming/protonup-qt`
- `networking/curl`, `networking/telegram`, `networking/wget`
- `peripherals/streamcontroller`
- `system/fastfetch`, `system/ripgrep`, `system/unzip`, `system/zip`

`python-tools`は`python3.withPackages`によるpackage集合のみ。`moonlight`はWireGuard feature依存を持つが、設定本文はpackage導入のみ。`limine/plymouth-theme/default.nix`はfeatureではなく、Limine moduleがcallPackageするderivationなので、この27件には数えない。

### S: 9

- `applications/curl`, `applications/git`, `applications/jq`, `applications/nodejs`, `applications/ripgrep`, `applications/unzip`, `applications/vim`, `applications/wget`, `applications/zip`

### D: 7

- `development/android-tools`, `development/gcc`, `development/go`, `development/nodejs`
- `system/git`, `system/ripgrep`, `system/vim`

### R: 16

- `audio-video/musescore`
- `desktop/ark`, `desktop/qt6ct`, `desktop/seahorse`
- `development/codex`, `development/gh`, `development/git`, `development/nil`, `development/nixd`
- `networking/curl`, `networking/telegram`, `networking/wget`
- `system/fastfetch`, `system/ripgrep`, `system/unzip`, `system/zip`

## 7. 抽出時に見落としやすい資産・境界

- `desktop-theme/cursor.nix`: asset取得/hashとHyprcursor変換を一箇所にする。
- `desktop/pcmanfm/pcmanfm.desktop`: L/Rで同一。icon生成と一緒に移す。
- `peripherals/open-deck-desktop/open-deck-desktop.desktop`: L/Rで異なる。tokenの置換方法を揃えるだけではExec等の挙動は揃わない。
- `desktop/noctalia/{gpu-screen-recorder-auto-x,recording-to-x}.sh`: attodeskの録画変換用。共通Noctaliaをimportしただけで全hostへ実行させない。
- `system/limine/assets/*`, `plymouth-theme/*`: Lのboot policyに付随。kernel・performance policyとは切り分ける。
- `system/login-pin/{check-login-pin.py,set-login-pin.sh}`: 認証moduleと一体。credential/PAM/fallbackを保護する。
- `development/pi/{package,context-mode}.nix`: 同一overrideを分散させないが、各hostのbase packageとoverlayの参照先は維持する。
- Sの`tests/check-pi-settings.sh`: writable JSONを壊さない既存のrunnable check。共有化後に参照先を合わせて維持する。
- S/D/Rのbootstrap/コンテナ設定、L/Sのストレージ・hardware設定、全hostのstateVersionは共有アプリ設定ではない。

この一覧は**現在宣言されている設定の共通化判断**。実機の現在のgeneration、利用中の設定ファイルの手動変更、可変upstreamのversionまで一致していることは保証していない。
