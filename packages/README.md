# Package実装

共有設定に必要なcustom derivation / overrideだけを置く。

実装済み:
- `pipeasio.nix`: PipeASIO 1.10.0のWine / Proton用ASIO driverと設定・管理GUI。version・hash固定。
- `pandora-launcher.nix`: 日本語localeでの起動失敗を避ける英語UTF-8 wrapper override。
- `pandoragh.nix`: Pandora用GitHub mod管理CLIとPython coreを同梱。
- `open-deck-desktop.nix`: Open-Deck Desktop 1.0.6のx86_64 AppImageをURL・hash固定で包装。アイコンとdesktop entryはAppImage内のものを使用。
- `pi.nix`: Pi 1.0.2のversion override。
- `context-mode.nix`: context-mode 1.0.169のPi adapter / HTML dependenciesを含むoverride。
- `karakeep-monolith.nix`: 利用ホストの `pkgsStatic.monolith` に既存のSVG USE / archive内fragment navigation修正を適用するoverride。Karakeep containerへ静的binaryを渡す。fragment保持とarchive linkのinstall checkを含む。

- `custom-cursors.nix`: consumerから取得済みアーカイブを受け取り、XcursorからHyprcursorを生成するderivation。package・テーマ・メタデータは汎用名を使用。

`default.nix` に `{ pkgs }` を渡すと、利用ホストのpkgsでcallPackageした `pi`・`context-mode`・`open-deck-desktop`・`pandora-launcher`・`pandoragh`・`pipeasio`・`karakeep-monolith` のpackage setと、取得済みアーカイブを受け取る `custom-cursors` 関数を返す。flakeではこの関数を `attopkgs` として公開する。
共有側の`modules/home-manager/default.nix`がその結果をNixOS / HMへ引数`attopkgs`として渡す。ホスト側の手動設定は不要で、各機能のmodule内ではpackage定義を直接callPackageしない。
カーソルは `attopkgs.custom-cursors { cursor = pkgs.fetchurl { name = "custom-cursors.zip"; url = "https://example.invalid/cursor.zip"; hash = "sha256-..."; }; }` で組み立てる。実際のURL・hashと取得処理はconsumer側に置き、共有repoへ書かない。
Pi等のbase package供給元が違う場合は、利用側でpackage setを組み立てる際に現在の供給元を保持する。
単なるpkgs.git等の再exportや、ホストのpackage一覧は作らない。
