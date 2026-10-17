# 共有moduleの作成・利用側の移行

利用側dotfilesの移行を依頼された場合は、まず[利用側dotfilesの移行手順](docs/migration.md)を読み、その手順で対象checkout・全構成（guest/image/HMを含む）・許可範囲を確定する。
[残作業台帳](docs/inventory.md)は次の作業を探すためのもので、稼働状態や採用revisionのAPIの根拠にはしない。
移行には共有入口と既存の公開APIを使い、共有実装の変更・他repo統合・pin更新・build・実機適用・commit/pushを無断で追加しない。

以下は、`attos-nix-modules`で機能moduleを追加・変更するときの手順。
共有repoの実装、利用側のコード移行・lock更新、build、実機適用は別の完了条件として扱う。

## 1. 既存実装と責務を確認する

- 最初に`git status --short`を確認し、既存のユーザー変更を保持する。
- `README.md`、`docs/inventory.md`、[Wiki](https://forgejo.attodao.cc/AttODao/attos-nix-modules/wiki)の対象moduleページを読む。
- `modules/default.nix`、対象・依存moduleを確認する。
- 既存設定を移す場合は、利用側のNixOS / HM設定、package供給元、依存、実行時の前提を両scopeで追う。比較・保護・検証は`docs/migration.md`、残作業は`docs/inventory.md`を参照し、現在の設計・APIは採用revisionのREADME・Wiki・実装を確認する。
- 類似実装や標準NixOS / Home Manager optionを再利用し、独自resolver、ホスト台帳、不要なwrapperを追加しない。

### 共有側と利用側の境界

共有側は機能設定、機能間の依存、HMの読み込み・共通設定・package引数を担当する。
hardware、ユーザー作成、ログインシェル、権限・linger、secrets、stateVersion、保存先、unfree許可、機器固有値は利用側に残す。

秘密の内容をNix式へ埋め込んだり、Nix storeへ取り込んだりしない。必要な場合は復号後のruntime pathを参照する。
認証・履歴・可変データを宣言的設定で上書きしない。

## 2. 最小の公開APIを決める

- 機能選択はNixOS側の`modules.<name>.enable`に集約し、`lib.mkEnableOption`で既定falseにする。公開サーバーは`modules.public-services.<FQDN>.<service>`、localhost単独利用は`modules.<service>`を使う。`public-services/lib.nix`の`moduleOptions`で同じtyped schemaを再利用し、単独利用を公開registryへ注入しない（既存Paseo bridge、SSH client/serverのscopeは維持）。
- 公開サービスは有効時に`host`で所有OSの`networking.hostName`を指定する。物理ホスト・guestが同じnamespaceを読み、所有OSだけで実体を起動する。`deploy`は全種既定true、falseは管理外endpoint登録専用。別ホストのrecordをfalseに書き換える実装はしない。
- HM専用の機能にもNixOS側のenableを設ける。HM側に別のenableやstandalone HM exportを追加しない。
- enable以外の独自optionは、利用側から渡す必要がある値だけに限定する。型、説明、妥当な既定値または有効時の必須条件を定義する。
- ユーザーごとの調整は標準`home-manager.users.<name>`へ書けるようにする。調整可能な既定値には`lib.mkDefault`を使い、安易に`mkForce`で固定しない。
- 必要な依存機能は、対象機能の有効時に`modules.<dependency>.enable = true;`で有効化する。通常代入のfalseとの競合を隠さない。

## 3. 機能ディレクトリを作る

```text
modules/<name>/
  default.nix   公開option・依存・両scopeへの接続
  home.nix      HM実設定（必要な場合のみ）
  nixos.nix     NixOS実設定（必要な場合のみ）
  <assets>      付随するscript・desktop entryなど
```

空のscopeファイルや将来用の抽象化は作らない。
HMのみなら`modules/foot/`、両scopeなら`modules/thunderbird/`、NixOSのみなら`modules/pipewire/`を参考にする。

両scopeを持つ機能の最小形（`example`は実際の機能名に置き換える）:

```nix
# modules/example/default.nix
{ config, lib, ... }:
{
  imports = [ ./nixos.nix ];

  options.modules.example.enable = lib.mkEnableOption "shared example configuration";

  config = lib.mkIf config.modules.example.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
```

- NixOSの`imports`は静的に宣言し、enableから組み立てない。依存moduleのimportも同様。
- `nixos.nix`の実設定は`lib.mkIf config.modules.<name>.enable`で囲む。公開サーバーと単独利用は`public-services/lib.nix`の`select`・`moduleOptions`・`common`・`pathOption`・`require`を再利用し、`select.enabled`で同じ実装を囲む。`select.standalone`の場合だけlocalhost bind/HTTP・通常Docker bridgeを使い、公開record・Swarm・gateway依存を作らない。singleton assertionも登録し、無効・`host`不一致・`deploy = false`でlocal依存・必須path・unitを作らない。
- 公開namespaceはtypeを拡張するだけにし、rootのdefault / descriptionを各サービスで重複宣言しない。DNS・CNAME・proxyはnamespaceから導出し、consumerの`public-hosts.nix`や別のhost台帳をimportしない。具体例・制約は[Wikiの公開サービスAPI](https://forgejo.attodao.cc/AttODao/attos-nix-modules/wiki/module-public-services)と各サービスページを参照。
- `home.nix`の実設定は`lib.mkIf osConfig.modules.<name>.enable`で囲む。
- HM設定は`home-manager.sharedModules`で接続する。特定ユーザーへの直書きや、ユーザー一覧を機能ごとに走査する実装はしない。
- 有効なHM設定は、標準`home-manager.users`に直接宣言したユーザーを含む全HMユーザーに適用される。固定アカウント・デバイス設定や複数ユーザーでの競合を確認する。

## 4. 登録とpackageの接続を行う

1. `modules/default.nix`の静的`imports`へ`./<name>`を追加する。
2. 通常のpackageは利用ホストの`pkgs`を使う。
3. custom derivation / overrideが必要な場合だけ、nixpkgsと同じ`packages/by-name/<先頭2文字>/<name>/package.nix`を作る。登録は自動で、`packages/default.nix`の編集は不要。consumer入力が必要なbuilderは`{ deps }: { args }: ...`のcurried形にし、nixpkgsの同名packageを上書きする場合は`pkgs.<name>`を参照する。
4. root直下に`package.nix`を持つ外部repoは、`flake.nix`へ`flake = false`のinputを追加し、`packages/default.nix`の外部input表へ1行追加する。
5. custom packageはmodule引数`attopkgs`から使う。機能module内で直接`callPackage`しない。供給は`flake.nix`の`nixosModules.default`に任せる。
6. 取得物はversion・hash、またはflake.lockで固定する。consumer固有のアーカイブURL・hashなどは利用側に残す。

通常の機能追加で`flake.nix`へ個別module exportや別のHM読み込みを追加する必要はない。
Home Manager revision・共有nixpkgs・利用側nixpkgsの更新を機能追加に混ぜない。

## 5. 評価する

このrepoはテストを持たない。リポジトリルートから次を実行する。

```sh
nix flake check --no-build 'path:.'
nix eval --raw 'path:.#packages.x86_64-linux.<name>.drvPath' # 変更したpackage
```

- 未有効時に機能設定・依存が勝手に有効にならないこと、enable一つで必要な設定が入ることは、利用側の`--override-input`付き評価で確認する。
- `path:`評価は未追跡ファイルも含む。既存のstage状態を検証のために変えない。
- 通常のflake評価には`--no-write-lock-file`を使う。依頼されていないlock更新・rebuild・switch・pushはしない。

評価成功はビルド成功・実機動作の保証ではない。boot、PAM、desktop起動、user service、外部機器などは利用側への移行後に別途確認する。

## 6. ドキュメントと差分を確認する

- `README.md`の機能一覧、scope、依存、独自option、利用側の前提を更新する。
- moduleのpackage/version・設定項目・設定例・運用上の制約はWikiの対応ページへ記載し、重複する機能別docsを増やさない。custom packageの実装・供給契約は`packages/README.md`へ、未完了の作業だけを`docs/inventory.md`へ記載する。完了した項目・成功ログは台帳から削除し、Git履歴/PR等へ残す。
- `git diff --check`と対象ファイルのdiffを確認し、無関係な変更やcredentialがないことを確認する。新規ファイルは未追跡の内容も確認する。
- 完了報告には、変更した機能・ファイル、実行した検証、未検証事項を短く記す。利用側の移行や実機適用を行っていない場合は明示する。
