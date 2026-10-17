# Package実装

共有設定に必要なcustom derivation / overrideだけを、nixpkgsと同じ `by-name/<先頭2文字>/<name>/package.nix` に置く。
`default.nix` がby-nameを `lib.makeScope` へ自動登録し、外部input表のpackageを加える。package名はディレクトリ名。

外部inputから供給:
- `claude-code`: `flake.nix` の `claude-code-nix`（github:sadjow/claude-code-nix、`flake = false`）root直下の `package.nix` を利用ホストのpkgsで `callPackage` する。versionは共有flake.lockで固定し、`nix flake update claude-code-nix` で更新する。

実装済み:
- `vm-bootstrap`: 宣言済みのRunning KVM VMへ、未設定のlogin passwordをTTYで設定、またはユーザーhome内へprivate runtime fileを配送するCLI。既存password/hash/fileは保持し、root/system account、container、停止VM、公開読取file、home外の配送は拒否。hostのprofile/image/storeへ秘密を入れず、service起動は明示指定時のみ行う。
- `vm-rebuild`: Incus moduleのruntime flake.nix pathと宣言済みVM名を受け取る `attopkgs.vm-rebuild` / `vm-rebuild` CLI。running VM/Incus agentを検査し、local buildとmissing closureのroot import後、guestの標準nixos-rebuildへstore-pathを渡す。local/default project限定、hostのprofileは変更しない。`vm-rebuild <action> <VM> --override-input NAME REFERENCE` で未commitの `path:` checkout/inputも評価/buildできる。
- `mcsmanager`: 公式10.19.0のself-contained releaseをhash固定し、単一derivationで `attopkgs.mcsmanager/share/mcsmanager/{web,daemon}` へ配置。npm fetch/node_modulesは不要。PTY等をNixOSへpatchし、upstream daemon keyログを除去する。install checkはtemp-only web/daemonの認証・assets・prefixを確認し、runtime secret/bootstrapはmoduleに残す。
- `paseo`: Paseo 0.11.1のsource/lock依存hash固定。`attopkgs.paseo` はstore Nodeとnative依存を使うCLIを供給し、起動時npx/npm fetchを行わない。
- `atcoder-cli`: atcoder-cli 2.2.0。source hash / npmDepsHash固定。
- `atcoder-oj`: ホストのonline-judge-tools/API clientへAtCoderのMiB表記対応patchを適用。
- `atcoder-aclogin`: aclogin 0.2.1、revision/hash固定。cookieを配布・宣言的管理しない。
  `atcoder-cli` と共に定義はproject scaffoldと共有する `modules/atcoder-go/assets/atcoder/nix/` にあり、by-name側はimportするだけ。
- `atcoder-commands`: 選択したGoとHMユーザーのHOMEを受け取る共通command package。initは既存go.mod/.envrcを保持し、syncは記録済み依存をdownloadするだけ。project固有assetsや未固定libraryの追加・更新は行わない。
- `code-server`: consumerが固定したx86_64 standalone releaseを包装し、JetBrainsMono Nerd Fontのwoff2/CSSをworkbenchへ組み込む。upstream HTML layoutの変更はreplace-failで検出する。通常は公開 `code-server.packageSource` で選択し、moduleが標準 `services.code-server.package` へ既定値として渡す。
- `pipeasio`: PipeASIO 1.10.0のWine / Proton用ASIO driverと設定・管理GUI。version・hash固定。
- `pandora-launcher`: 日本語localeでの起動失敗を避ける英語UTF-8 wrapper override。
- `pandoragh`: Pandora用GitHub mod管理CLIとPython coreを同梱。
- `open-deck-desktop`: Open-Deck Desktop 1.0.6のx86_64 AppImageをURL・hash固定で包装。アイコンとdesktop entryはAppImage内のものを使用。
- `pi`: Pi 1.0.2のversion override。base nixpkgsのinstall処理がcodemode/MCP workspaceを落とす場合だけ補完し、copy済みのworkspaceは保持する。install checkで両moduleのimportを確認する。固定nixpkgsがPi 1.0.2以上を提供したらoverrideを削除する。
- `pi-mermaid-studio`: Mermaid Studio 0.2.1（`42ce06fac0572e7e8672d5ef6c86c1d7a2a23fe1`）とproduction npm依存をhash固定し、`attopkgs.pi-mermaid-studio/lib/pi-mermaid-studio`へextension・skills・browser assetsを配置。dev-only lock entriesを除き、host供給のPi/typebox peerを同梱せず、runtime npm installを行わない。install checkはMermaid assets・linkedom import・peer非同梱を確認する。
- `context-mode`: context-mode 1.0.169のPi adapter / HTML dependenciesを含むoverride。
- `karakeep-monolith`: 利用ホストの `pkgsStatic.monolith` にSVG USE / archive内fragment navigation修正patchを適用するoverride。Karakeep containerへ静的binaryを渡す。fragment保持とarchive linkのinstall checkを含む。
- `custom-cursors`: consumerから取得済みアーカイブを受け取り、XcursorからHyprcursorを生成するderivation。package・テーマ・メタデータは汎用名 `Custom-Cursors` を使用。
- `centered-plymouth-theme`: consumer画像を受け取り、黒背景でlogoを中央配置する汎用Plymouth script theme `centered-logo` を構築。共有側にホスト名・ブランド画像を含めない。

`default.nix` に `{ pkgs, inputs }` を渡すと、利用ホストのpkgsで構築したscopeを返す。flakeは `attopkgs { pkgs }`・`overlays.default`（`pkgs.attopkgs`）・共有nixpkgsで構築した `legacyPackages.<system>`、そのうちderivationだけの `packages.<system>` を公開する（`nix shell attos-nix-modules#claude-code` 等）。
`atcoder-commands`・`code-server`・`custom-cursors`・`centered-plymouth-theme`・`vm-rebuild`・`vm-bootstrap` はconsumer/module引数を受けるcurried builderで、`packages` 出力には含まれない。
`atcoder-commands { go = <選択package>; homeDirectory = <HMのHOME>; aclogin = <選択package>; }` と
`code-server { src = <固定したstandalone release>; }` で使用する。
`centered-plymouth-theme { image = <consumer画像path>; }` も同じsetに含む関数。ImageMagickの `-resize '960x360>'` で縦横比を保ち最大960x360へ縮小し、拡大しない。出力は `share/plymouth/themes/centered-logo/` にdescriptor・script・logo.pngを置く。画像は公開可能なbuild入力としてstoreへ入るため、秘密・可変データを渡さない。
code-server releaseの取得URL/hash・versionはconsumer inputに固定し、共有側でlatest取得や新しい供給元へ切り替えない。

`flake.nix` の `nixosModules.default` が利用ホストのpkgsで構築した結果をNixOS / HMへ引数`attopkgs`として渡す。ホスト側の手動設定は不要で、各機能のmodule内ではpackage定義を直接callPackageしない。
カーソルは `attopkgs.custom-cursors { cursor = pkgs.fetchurl { name = "custom-cursors.zip"; url = "https://example.invalid/cursor.zip"; hash = "sha256-..."; }; }` で組み立てる。実際のURL・hashと取得処理はconsumer側に置き、共有repoへ書かない。
archiveは展開後のrootに `cursors/` が必要。通常は取得済みarchive packageを `modules.desktop-theme.cursor` へ渡し、共有側が `custom-cursors` を呼ぶ。ユーザーごとに別packageが必要な場合だけ標準HM `home.pointerCursor.package` へ生成結果を渡す。
Plymouthも通常は `modules.limine.splashImage = ./assets/boot-logo.png;` で選択する。画像のみconsumerに残し、descriptor/script・画像変換の実装は共有側が所有する。nullの場合にこのpackageを作らずupstream themeを維持するのはLimine moduleの契約で、package関数自体のimage引数は必須。
単なるpkgs.git等の再exportや、ホストのpackage一覧は作らない。
