# Package実装

共有設定に必要なcustom derivation / overrideだけを、nixpkgsと同じ `by-name/<先頭2文字>/<name>/package.nix` に置く。
`default.nix` がby-nameを `lib.makeScope` へ自動登録し、外部input表のpackageを加える。package名はディレクトリ名。
登録時に `package.nix` の無いディレクトリ、shard名とpackage名先頭2文字の不一致、外部input表との名前衝突を評価エラーにする。
`nix flake check --no-build` で評価できないpackageは `passthru.skipFlakeCheck = true` を宣言する（`flake.nix` が `packages` 出力から除外し、`legacyPackages` と `attopkgs` には残る）。

外部inputから供給:
- `claude-code`: `flake.nix` の `claude-code-nix`（github:sadjow/claude-code-nix、`flake = false`）root直下の `package.nix` を利用ホストのpkgsで `callPackage` する。versionは共有flake.lockで固定し、`nix flake update claude-code-nix` で更新する。
- `hermes-desktop`: `flake.nix` の `hermes-agent`（github:NousResearch/hermes-agent、release tag固定。hermes moduleのupstream NixOS moduleと共用）の `nix/desktop.nix` を利用ホストのpkgsで呼ぶremote専用build。scopeの `hermes-agent-src` でsourceと、`default.nix` が `flake.lock` の `original.ref`（release tag）から取った `version` を受け取り（packageにversionを書かない）、install stampを `payload = "light"` にして、agent（Python venv）の代わりに失敗するだけのstubを渡し、起動時に `HERMES_DESKTOP_HERMES` を外す。`extraRun`（既定[]）は起動前に実行するshell行。

実装済み:
- `build-go-program`: repo内script用のGo builder。`{ build-go-program }: build-go-program { pname = "<name>"; src = ./.; }` で、`src`直下の`.go`（単一 `package main`、標準libraryのみ、go.modなし）を1つの実行ファイル `bin/<pname>` にする。Goは利用ホストの `pkgs.go` をビルド時だけ使い、runtime closureへ入らない。buildで `go vet`、`*_test.go` があればcheckPhaseで `go test` を実行する。srcは`.go`だけをfilesetで取り込むため、package.nixや文書の変更では再ビルドしない。host設定はderivationへ含めず、JSON pathや引数を実行時に渡す。外部moduleが必要になったpackageはgo.mod + `buildGoModule` へ切り替える。
- `attos-docker`: 共有Docker bridge networkの作成・検査（`network ensure`）を行う標準libraryのみのGo program。既存networkは再作成せず、不一致は失敗する。
- `wireguard-runtime`: wireguard-server moduleのruntime client設定生成（`configs`）とQR表示（`qr`、`wg-qr` wrapper経由）を行うGo program。key fileはruntimeで検査し、file単位でatomic交換する。
- `cloudflare-cnames`: cloudflare-public-cnames moduleのCNAME同期Go program。ownership commentを持つ記録だけをpruneし、認証情報・response内容を出力しない。
- `login-pin`: login-pin moduleの`set-login-pin`（`login-pin set`）。mkpasswd（yescrypt）・db_loadでpam_userdb用DBを0600で原子的に置換する。testは実DBを`db_dump`で検査する。
- `mcsmanager-init`: mcsmanagerのExecStartPreで既存JSONへのruntime設定mergeと初期管理者作成を行うGo program。asset symlinkはmoduleのtmpfilesが作る。testで同梱releaseを一時state・偽credentialで起動するsmoke testを行う（`mcsmanager`をcheck入力に持つ）。
- `guest`: Incus guest（KVM VM・system container）用のGo CLI（`build-go-program`、標準libraryのみ、`go vet`/`go test`）。host設定は含まず、Incus moduleがbinary wrapperで `--config <JSON>`（runtime flake.nix path・宣言済みguestのtype・launch設定・managed device名・credential配送unit/file）とPATH（incus client・nix）を渡す。`guest <name> boot` は不足guestをflakeのmetadataとVMならqcow2、containerならsquashfsから作成して作成用imageを削除し、managed deviceをupsertして起動、`incus exec` が通るまで待ってcredential配送unitを再起動する。flake構成の `boot.isContainer`（VMはIncus agentも）と、既存instanceのtypeが宣言と一致しなければ拒否する。`stop`、TTY確認付きの `delete`（Stopped限定）、`rebuild [action]`（既定switch。適用actionは先にbootし、local buildとmissing closureのroot import後、guestの標準nixos-rebuildへstore-pathを渡す）を持つ。`passwd <user>` / `push-file <user> <source> <dest> [--system-unit|--user-unit]` は宣言済みRunning guestへ未設定のlogin passwordをTTYで設定、またはユーザーhome内へprivate fileをuser権限・hard linkで非上書き配置する（既存password/hash/file保持、root/system account・公開読取file・home外は拒否、unit起動は新規配置時のみ）。`deliver-credentials` はcredential配送unit用、`guest preseed-condition <pool>` はcreate-only preseedのExecCondition。local/default project限定、hostのprofileは変更しない。`--override-input NAME REFERENCE` で未commitの `path:` checkout/inputも評価/buildできる。
- `attos-ci`: このrepoと利用側のForgejo Actionsが共有するshell tool（`nix run <attos-nix-modules>#attos-ci -- <command>`）。`update-shared`（HM revision・hermes-agent release tag・flake.lock）、`update-packages`（対象を列挙した`nix-update`。`ccpocket-bridge`はmonorepoの他アプリのtagでreleases feedが埋まるため、`git ls-remote`で最新の`bridge/v*`を求めて`--version`に渡す。registryのtag一覧から全flavorが揃う最新の数値版を選び、`modules/strata/nixos.nix`のimage tag・digestをまとめて更新する。取得失敗や揃う版がない場合はfileを変えず、`strata-images`のwarningを出す。`modules/pi/resources.nix`・`modules/skills/sources.nix`への`update-nix-fetchgit`。失敗したpackageはwarningにして続行）、`check-consumers owner/repo:host,...`（flake checkと利用側hostの `--override-input` 評価。buildはしない）、`pr BRANCH TITLE`（bot名義でcommitしてbranchへforce push、PRを作成・更新。本文には `flake.lock` の変更前後と、`update-packages` が記録したpackage version・取得元revisionの変更前後を表で書く）を持つ。用途は更新PRのみで、buildやcacheへのpushは行わない。`nix` はjob環境（`nixos/nix` container）のものを使うため同梱しない。入力はActionsの `GITHUB_SERVER_URL`・`GITHUB_REPOSITORY` と `FORGEJO_TOKEN`。
- `mcsmanager`: 公式10.21.2のself-contained releaseをhash固定し、単一derivationで `attopkgs.mcsmanager/share/mcsmanager/{web,daemon}` へ配置。npm fetch/node_modulesは不要。PTY等をNixOSへpatchし、upstream daemon keyログを除去する。install checkはtemp-only web/daemonの認証・assets・prefixを確認し、runtime secret/bootstrapはmoduleに残す。
- `paseo`: Paseo 0.12.0のsource/lock依存hash固定。`attopkgs.paseo` はstore Nodeとnative依存を使うCLIを供給し、起動時npx/npm fetchを行わない。
- `ccpocket-bridge`: CC Pocket BridgeのGitHub tag `bridge/v<version>`（versionは`by-name/cc/ccpocket-bridge/package.nix`を参照）を`fetchFromGitHub`で取得し、sourceとupstream root lockの依存をhash固定し、tscでbuildしたproduction依存だけを `lib/ccpocket` へ配置する。起動時npx/npm fetchを行わない。Claude Agent SDK同梱のClaude Code binaryはinterpreterだけpatchする。sharpの同梱libvipsはautoPatchelfすると落ちるためpatchしない。install checkでversion・sharp・Claude Code binaryの起動を確認する。
- `atcoder-cli`: atcoder-cli 2.2.0。source hash / npmDepsHash固定。
- `atcoder-oj`: ホストのonline-judge-tools/API clientへAtCoderのMiB表記対応patchを適用。
- `atcoder-aclogin`: aclogin 0.2.1、revision/hash固定。cookieを配布・宣言的管理しない。
  `atcoder-cli`・`atcoder-oj`・`atcoder-go` の定義はproject scaffoldと共有する `modules/atcoder-go/assets/atcoder/nix/` にあり、by-name側はimportするだけ。
- `atcoder-go`: `modules/atcoder-go/assets/atcoder/cli/` のGo source（標準libraryのみ）を`buildGoModule`で構築するAtCoder CLI。project scaffoldのdevenvと同じ定義を使う。toolchainとscaffold assetsはmoduleがbinary wrapperの`ATCODER_GO_BIN_DIR`・`ATCODER_PROJECT_ASSETS`で渡す。
- `pipeasio-steam-prefixes`: `pipeasio-manage list`のSteam targetへ、各ゲームのrunner（umu）でPipeASIOを登録するGo helper。`pipeasio-register-steam-prefixes`と、`pipeasio-register`用WINE `pipeasio-proton-run`を提供する。pipeasio・umuのPATHとdriver DLL pathはwrapperで固定する。
- `code-server`: consumerが固定したx86_64 standalone releaseを包装し、JetBrainsMono Nerd Fontのwoff2/CSSをworkbenchへ組み込む。upstream HTML layoutの変更はreplace-failで検出する。通常は公開 `code-server.packageSource` で選択し、moduleが標準 `services.code-server.package` へ既定値として渡す。
- `pipeasio`: PipeASIO 1.10.0のWine / Proton用ASIO driverと設定・管理GUI。version・hash固定。
- `pandora-launcher`: 日本語localeでの起動失敗を避ける英語UTF-8 wrapper override。
- `file-manager-icon`: Papirusの`system-file-manager` SVGを256x256 PNGへ変換した単一file。pcmanfm・yaziのdesktop entryが共用する。
- `strata-headless-session`: `{ sessionConfig }`を受けるcurried builder。`modules/strata/{session.py,prepare.py}`とPython/evdevを包装し、`strata-headless {session,start,status,stop}`・`strata-headless-session`・`Strata (API only)`のsession entryを供給する。checkPhaseで両Python sourceを`py_compile`する。unit・secret・Docker image管理はmodule側。`sessionConfig`（systemctl/settermの絶対path、endpoint/healthUrl、model/unit/logのlist）はstoreのJSONになるため秘密を含めない。
- `open-deck-desktop`: Open-Deck Desktopのx86_64 AppImageをURL・hash固定で包装（versionは`by-name/op/open-deck-desktop/package.nix`を参照）。アイコンとdesktop entryはAppImage内のものを使用。
- `pi`: Pi 1.3.0のversion override。base nixpkgsのworkspace一覧はそのPi releaseに従うため、このversionのruntime workspaceをcopyするinstall処理で置き換える。install checkでcodemode/MCP moduleのimportを確認する。固定nixpkgsがPi 1.3.0以上を提供したらoverrideを削除する。
- `pi-mermaid-studio`: Mermaid Studio 0.2.1（`42ce06fac0572e7e8672d5ef6c86c1d7a2a23fe1`）とproduction npm依存をhash固定し、`attopkgs.pi-mermaid-studio/lib/pi-mermaid-studio`へextension・skills・browser assetsを配置。dev-only lock entriesを除き、host供給のPi/typebox peerを同梱せず、runtime npm installを行わない。install checkはMermaid assets・linkedom import・peer非同梱を確認する。
- `context-mode`: context-mode 1.0.169のPi adapter / HTML dependenciesを含むoverride。
- `karakeep-monolith`: 利用ホストの `pkgsStatic.monolith` にSVG USE / archive内fragment navigation修正patchを適用するoverride。Karakeep containerへ静的binaryを渡す。fragment保持とarchive linkのinstall checkを含む。
- `custom-cursors`: consumerから取得済みアーカイブを受け取り、XcursorからHyprcursorを生成するderivation。package・テーマ・メタデータは汎用名 `Custom-Cursors` を使用。
- `centered-plymouth-theme`: consumer画像を受け取り、黒背景でlogoを中央配置する汎用Plymouth script theme `centered-logo` を構築。共有側にホスト名・ブランド画像を含めない。

`default.nix` に `{ pkgs, inputs }` を渡すと、利用ホストのpkgsで構築したscopeを返す。flakeは `attopkgs { pkgs }`・`overlays.default`（`pkgs.attopkgs`）・共有nixpkgsで構築した `legacyPackages.<system>`、そのうちderivationだけの `packages.<system>` を公開する（`nix shell attos-nix-modules#claude-code` 等）。
`code-server`・`custom-cursors`・`centered-plymouth-theme`・`strata-headless-session` はconsumer/module引数を受けるcurried builderで、`packages` 出力には含まれない。
`hermes-desktop` はupstreamの `nix/lib.nix` がeval中にlockfile用sourceを読み、`nix flake check --no-build` で失敗するため `passthru.skipFlakeCheck = true` で `packages` 出力から外す。`legacyPackages` とmodule引数 `attopkgs` には残り、評価は `nix eval --raw 'path:.#legacyPackages.x86_64-linux.hermes-desktop.drvPath'`（IFDのsource生成を伴う）で行う。
`code-server { src = <固定したstandalone release>; }` で使用する。
`centered-plymouth-theme { image = <consumer画像path>; }` も同じsetに含む関数。ImageMagickの `-resize '960x360>'` で縦横比を保ち最大960x360へ縮小し、拡大しない。出力は `share/plymouth/themes/centered-logo/` にdescriptor・script・logo.pngを置く。画像は公開可能なbuild入力としてstoreへ入るため、秘密・可変データを渡さない。
code-server releaseの取得URL/hash・versionはconsumer inputに固定し、共有側でlatest取得や新しい供給元へ切り替えない。

`flake.nix` の `nixosModules.default` が利用ホストのpkgsで構築した結果をNixOS / HMへ引数`attopkgs`として渡す。ホスト側の手動設定は不要で、各機能のmodule内ではpackage定義を直接callPackageしない。
カーソルは `attopkgs.custom-cursors { cursor = pkgs.fetchurl { name = "custom-cursors.zip"; url = "https://example.invalid/cursor.zip"; hash = "sha256-..."; }; }` で組み立てる。実際のURL・hashと取得処理はconsumer側に置き、共有repoへ書かない。
archiveは展開後のrootに `cursors/` が必要。通常は取得済みarchive packageを `modules.desktop-theme.cursor` へ渡し、共有側が `custom-cursors` を呼ぶ。ユーザーごとに別packageが必要な場合だけ標準HM `home.pointerCursor.package` へ生成結果を渡す。
Plymouthも通常は `modules.limine.splashImage = ./assets/boot-logo.png;` で選択する。画像のみconsumerに残し、descriptor/script・画像変換の実装は共有側が所有する。nullの場合にこのpackageを作らずupstream themeを維持するのはLimine moduleの契約で、package関数自体のimage引数は必須。
単なるpkgs.git等の再exportや、ホストのpackage一覧は作らない。
