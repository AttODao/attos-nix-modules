# Module作成の作業手順

この文書は、`attos-nix-modules`で機能moduleを追加・変更するエージェント向けの手順です。
共有repoの実装と、利用側dotfilesの移行・lock更新・実機への適用は別作業として扱います。

## 1. 既存実装と責務を確認する

- 最初に`git status --short`を確認し、既存のユーザー変更を保持する。
- `README.md`、`docs/README.md`、対象機能に関連するdocsを読む。
- `modules/default.nix`、対象・依存module、`tests/`の関連テストを確認する。
- 既存設定を移す場合は、利用側のNixOS / HM設定、package供給元、依存、実行時の前提を両scopeで追う。旧設定との比較には`docs/inventory.md`を使えるが、現在の設計はREADMEと実装を優先する。
- 類似実装や標準NixOS / Home Manager optionを再利用し、独自resolver、ホスト台帳、不要なwrapperを追加しない。

### 共有側と利用側の境界

共有側は機能設定、機能間の依存、HMの読み込み・共通設定・package引数を担当する。
hardware、ユーザー作成、ログインシェル、権限・linger、secrets、stateVersion、保存先、unfree許可、機器固有値は利用側に残す。

秘密の内容をNix式へ埋め込んだり、Nix storeへ取り込んだりしない。必要な場合は復号後のruntime pathを参照する。
認証・履歴・可変データを宣言的設定で上書きしない。

## 2. 最小の公開APIを決める

- 機能選択はNixOS側の`modules.<name>.enable`に集約し、`lib.mkEnableOption`で既定falseにする。公開サーバーはenableを含む独自設定を`modules.public-services.<FQDN>.<service>`へ集約し、別のglobal enable aliasを追加しない（既存Paseo bridgeのみ維持）。
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
- `nixos.nix`の実設定は`lib.mkIf config.modules.<name>.enable`で囲む。公開サーバーは`public-services/lib.nix`の`select`・`option`・`common`・`pathOption`・`require`を再利用し、`select.enabled`でlocal設定を囲む。singleton assertionも登録し、`deploy = false`でlocal依存・必須path・unitを作らない。
- 公開namespaceはtypeを拡張するだけにし、rootのdefault / descriptionを各サービスで重複宣言しない。DNS・CNAME・proxyはnamespaceから導出し、consumerの`public-hosts.nix`や別のhost台帳をimportしない。具体例・制約は`docs/server-services.md`を参照。
- `home.nix`の実設定は`lib.mkIf osConfig.modules.<name>.enable`で囲む。
- HM設定は`home-manager.sharedModules`で接続する。特定ユーザーへの直書きや、ユーザー一覧を機能ごとに走査する実装はしない。
- 有効なHM設定は、標準`home-manager.users`に直接宣言したユーザーを含む全HMユーザーに適用される。固定アカウント・デバイス設定や複数ユーザーでの競合を確認する。

## 4. 登録とpackageの接続を行う

1. `modules/default.nix`の静的`imports`へ`./<name>`を追加する。
2. 通常のpackageは利用ホストの`pkgs`を使う。
3. custom derivation / overrideが必要な場合だけ`packages/<name>.nix`を作り、`packages/default.nix`へ登録する。
4. custom packageはmodule引数`attopkgs`から使う。機能module内で直接`callPackage`しない。供給は既存の`modules/home-manager/default.nix`に任せる。
5. 取得物はversion・hashを固定する。consumer固有のアーカイブURL・hashなどは利用側に残す。

通常の機能追加で`flake.nix`へ個別module exportや別のHM読み込みを追加する必要はない。
Home Manager revision更新や利用側nixpkgs更新を機能追加に混ぜない。

## 5. 評価テストを追加する

`tests/<name>.nix`を追加し、`tests/lib.nix`の`cfgFor`、`hm`、`hmFor`、`evalSystem`を再利用する。
既存の`tests/thunderbird.nix`や`tests/modules.nix`と同様に、`assert`で検証して最後に`true`を返す。

変更に応じて、次を確認する:

- 未有効時には機能設定・依存が勝手に有効にならない。
- enable一つで必要なNixOS / HM設定と依存が有効になる。
- package、生成設定、service、activationの評価が期待どおりになる。
- 公開optionの型・必須値・上書きが期待どおりに扱われる。
- ユーザー固有pathを導出でき、複数HMユーザーでも設定が適用される。

scriptに分岐・parser・外部状態の操作を追加した場合は、同じ機能ディレクトリに最小の実行可能テストを残す。既存のPIN・PipeASIOテストを参考にする。

## 6. 検証する

リポジトリルートから実行する。`/path/to/...`は、利用ホストで固定したnixpkgs sourceと、このflakeで固定したHome Manager sourceの実パスに置き換える。

```sh
nix-instantiate --eval --strict tests/<name>.nix \
  --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager

nix-instantiate --eval --strict tests/integrated.nix \
  --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
```

- 対象機能、依存・関連機能、統合テストを実行する。共通基盤を変えた場合は`tests/lib.nix`を除く全評価テストを確認する。
- sourceの取得・実体化が必要な評価だけ`--read-write-mode`を追加する。成功結果は`true`。
- このflakeは`checks`を公開していないため、`nix flake check`だけで`tests/*.nix`を実行したことにはならない。
- Flake経由で新規Nixファイルを参照する場合は、未追跡ファイルが含まれない点に注意する。必要なファイルだけ明示的に`git add`し、既存のstage状態を勝手に変えない。
- 通常のflake評価には`--no-write-lock-file`を使う。依頼されていないlock更新・rebuild・switch・pushはしない。

関連scriptを変更した場合は、対応するテストも実行する:

```sh
python3 modules/login-pin/test-check-login-pin.py
python3 modules/pipeasio/test-register-steam-prefixes.py
```

評価成功はビルド成功・実機動作の保証ではない。boot、PAM、desktop起動、user service、外部機器などは利用側への移行後に別途確認する。

## 7. ドキュメントと差分を確認する

- `README.md`の機能一覧、scope、依存、独自option、利用側の前提を更新する。
- 特殊な運用・制約は`docs/<name>.md`へ、custom packageは`packages/README.md`へ記載する。
- `git diff --check`と対象ファイルのdiffを確認し、無関係な変更やcredentialがないことを確認する。新規ファイルは未追跡の内容も確認する。
- 完了報告には、変更した機能・ファイル、実行した検証、未検証事項を短く記す。利用側の移行や実機適用を行っていない場合は明示する。
