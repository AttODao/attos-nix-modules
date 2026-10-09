# Package実装

共有設定に必要なcustom derivation / overrideだけを置く。

実装済み:
- `vm-rebuild.nix`: Incus moduleのruntime flake.nix pathと宣言済みVM名を受け取る `attopkgs.vm-rebuild` / `vm-rebuild` CLI。running VM/Incus agentを検査し、local buildとmissing closureのroot import後、guestの標準nixos-rebuildへstore-pathを渡す。local/default project限定、hostのprofileは変更しない。`vm-rebuild <action> <VM> --override-input NAME REFERENCE` で未commitの `path:` checkout/inputも評価/buildできる。
- `mcsmanager.nix`: 公式10.19.0のself-contained releaseをhash固定し、単一derivationで `attopkgs.mcsmanager/share/mcsmanager/{web,daemon}` へ配置。npm fetch/node_modulesは不要。PTY等をNixOSへpatchし、upstream daemon keyログを除去する。install checkはtemp-only web/daemonの認証・assets・prefixを確認し、runtime secret/bootstrapはmoduleに残す。
- `paseo.nix`: Paseo 0.11.1のsource/lock依存hash固定。`attopkgs.paseo` はstore Nodeとnative依存を使うCLIを供給し、起動時npx/npm fetchを行わない。
- `atcoder-cli.nix`: atcoder-cli 2.2.0。旧consumerのsource hash / npmDepsHashを維持。
- `atcoder-oj.nix`: ホストのonline-judge-tools/API clientへAtCoderのMiB表記対応patchを適用。
- `atcoder-aclogin.nix`: aclogin 0.2.1、旧revision/hashを維持。cookieを配布・宣言的管理しない。
- `atcoder-commands.nix`: 選択したGoとHMユーザーのHOMEを受け取る共通command package。initは既存go.mod/.envrcを保持し、syncは記録済み依存をdownloadするだけ。project固有assetsや未固定libraryの追加・更新は行わない。
- `code-server.nix` / `code-server/`: consumerが固定したx86_64 standalone releaseを包装し、JetBrainsMono Nerd Fontのwoff2/CSSをworkbenchへ組み込む。upstream HTML layoutの変更はreplace-failで検出する。実行packageの選択は標準 `services.code-server.package`。
- `pipeasio.nix`: PipeASIO 1.10.0のWine / Proton用ASIO driverと設定・管理GUI。version・hash固定。
- `pandora-launcher.nix`: 日本語localeでの起動失敗を避ける英語UTF-8 wrapper override。
- `pandoragh.nix`: Pandora用GitHub mod管理CLIとPython coreを同梱。
- `open-deck-desktop.nix`: Open-Deck Desktop 1.0.6のx86_64 AppImageをURL・hash固定で包装。アイコンとdesktop entryはAppImage内のものを使用。
- `pi.nix`: Pi 1.0.2のversion override。
- `context-mode.nix`: context-mode 1.0.169のPi adapter / HTML dependenciesを含むoverride。
- `karakeep-monolith.nix`: 利用ホストの `pkgsStatic.monolith` に既存のSVG USE / archive内fragment navigation修正を適用するoverride。Karakeep containerへ静的binaryを渡す。fragment保持とarchive linkのinstall checkを含む。

- `custom-cursors.nix`: consumerから取得済みアーカイブを受け取り、XcursorからHyprcursorを生成するderivation。package・テーマ・メタデータは汎用名 `Custom-Cursors` を使用。
- `centered-plymouth-theme.nix`: consumer画像を受け取り、黒背景でlogoを中央配置する汎用Plymouth script theme `centered-logo` を構築。共有側にホスト名・ブランド画像を含めない。

`default.nix` に `{ pkgs }` を渡すと、利用ホストのpkgsでcallPackageした `pi`・`context-mode`・`open-deck-desktop`・`pandora-launcher`・`pandoragh`・`pipeasio`・`karakeep-monolith` のpackage setと、取得済みアーカイブを受け取る `custom-cursors` 関数を返す。flakeではこの関数を `attopkgs` として公開する。
追加の `atcoder-cli`・`atcoder-oj`・`atcoder-aclogin` はpackage値、`atcoder-commands` と `code-server` はconsumer/module引数を受ける関数として同じsetに含む。
`atcoder-commands { go = <選択package>; homeDirectory = <HMのHOME>; aclogin = <選択package>; }` と
`code-server { src = <固定したstandalone release>; }` で使用する。
`centered-plymouth-theme { image = <consumer画像path>; }` も同じsetに含む関数。ImageMagickの `-resize '960x360>'` で縦横比を保ち最大960x360へ縮小し、拡大しない。出力は `share/plymouth/themes/centered-logo/` にdescriptor・script・logo.pngを置く。画像は公開可能なbuild入力としてstoreへ入るため、秘密・可変データを渡さない。
code-server releaseの取得URL/hash・versionはconsumer inputに固定し、共有側でlatest取得や新しい供給元へ切り替えない。

共有側の`modules/home-manager/default.nix`がその結果をNixOS / HMへ引数`attopkgs`として渡す。ホスト側の手動設定は不要で、各機能のmodule内ではpackage定義を直接callPackageしない。
カーソルは `attopkgs.custom-cursors { cursor = pkgs.fetchurl { name = "custom-cursors.zip"; url = "https://example.invalid/cursor.zip"; hash = "sha256-..."; }; }` で組み立てる。実際のURL・hashと取得処理はconsumer側に置き、共有repoへ書かない。
archiveは展開後のrootに `cursors/` が必要。通常は取得済みarchive packageを `modules.desktop-theme.cursor` へ渡し、共有側が `custom-cursors` を呼ぶ。ユーザーごとに別packageが必要な場合だけ標準HM `home.pointerCursor.package` へ生成結果を渡す。
Plymouthも通常は `modules.limine.splashImage = ./assets/boot-logo.png;` で選択する。画像のみconsumerに残し、descriptor/script・画像変換の実装は共有側が所有する。nullの場合にこのpackageを作らずupstream themeを維持するのはLimine moduleの契約で、package関数自体のimage引数は必須。
Pi等のbase package供給元が違う場合は、利用側でpackage setを組み立てる際に現在の供給元を保持する。
単なるpkgs.git等の再exportや、ホストのpackage一覧は作らない。

実行可能check:

```sh
NIXPKGS=/path/to/pinned/nixpkgs python3 modules/atcoder-go/test-commands.py
python3 packages/code-server/test-install.py
```

これらはmock tools/assetsだけを使う。実際のAtCoder packageやstandalone release全体のbuild検証とは別。
