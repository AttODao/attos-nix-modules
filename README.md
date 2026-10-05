# attos-nix-modules

AttODaoの共通NixOS設定。全ホストでHome Managerを組み込み、機能ごとのenableでシステム設定と全HMユーザーの設定をまとめて有効化する。

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
| discord | HM | Fcitx5 |
| foot | HM | Fonts |
| paseo | HM | Pi |
| fcitx5 / floorp / noctalia / open-deck-desktop / pandora-launcher / pcmanfm / pi / userDirs / vscode / linux-wallpaperengine | HM | Open-DeckはNixOS AppImage supportも有効化 |

依存先を通常代入でfalseにすると競合する。依存を切る変更は、動作条件を確認した上で行う。

### enable以外の独自option

すべてNixOS側の `modules.<feature>` に指定する。

- `hyprland.{monitors,neowall.enable,lidSwitch.enable}`: モニター・壁紙shader起動・蓋イベント。詳細は[Hyprland](docs/hyprland.md)。
- `greeter.{cursor,output}`: cursor archiveは有効時必須。outputは既定null。
- `noctalia.{dock.pinned,screenRecorder.enable,calendar.account,location}`: 詳細は[Noctalia](docs/noctalia.md)。
- `paseo.hostname`: 有効時必須。runtime env fileは各ユーザーの `~/paseo/daemon.env`。既存の固定ポート127.0.0.1:6767を維持するため、複数ユーザーでのdaemon同時起動は競合する。
- `userDirs.{homeDirectory,dataDirectory}`: 既定null。ユーザーごとのHOMEを使用し、dataDirectory未指定はhomeDirectoryへ追従する。指定時は `"/mnt/data"` のような引用符付きの絶対パス文字列を使う。実データをstoreへ取り込まないようNixのパスリテラルは拒否する。
- `linux-wallpaperengine.wallpapers`: monitor / wallpaper / scalingのリスト。assetsは各ユーザーのSteamディレクトリを参照する。

その他の独自optionはenableのみ。詳細の変更は標準NixOS / HM optionへ書く。

## ホスト側に残すもの

hardware、ユーザー作成・権限・linger、secrets、stateVersion、保存先、機器固有の音声設定、
Steamの有効化、Wallpaper Engine assets、unfree licenseの許可は利用側で管理する。
greeterのカーソルアーカイブも利用側で取得する。login-pinは従来どおりattodaoのgreetd / TTYに限定する。
Pi等の認証・履歴・可変データは管理しない。
Open-Deckのupstream desktop entryは `--no-sandbox` を使うため、Electron sandboxは無効。

## 検証

利用ホストで固定したnixpkgs sourceと、このflakeで固定したHM sourceを渡す。

```sh
nix-instantiate --eval --strict tests/integrated.nix \
  --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
```

各機能の `tests/*.nix` も同じ引数で評価する。`tests/lib.nix` は共通helperのため単独評価の対象外。
sourceの取得・実体化が必要な評価には `--read-write-mode` を追加する。成功時は `true`。

```sh
python3 modules/login-pin/test-check-login-pin.py
python3 modules/pipeasio/test-register-steam-prefixes.py
```

共有側の実装のみ変更しており、各dotfilesへの移行・lock更新・rebuildは別作業。
[移行方針](docs/README.md)と[調査時点の差分](docs/inventory.md)も参照。
