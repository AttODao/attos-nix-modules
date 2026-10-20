# 共有moduleの作成・利用側への導入

新しい利用側環境の作成は[Wikiの新しい環境の作成手順](https://git.attodao.cc/AttODao/attos-nix-modules/wiki/getting-started)に従う。
利用側への導入には共有入口と既存の公開APIを使い、共有実装の変更・他repo統合・pin更新・build・実機適用・commit/pushを無断で追加しない。

以下は、`attos-nix-modules`で機能moduleを追加・変更するときの手順。
共有repoの実装、利用側のコード移行・lock更新、build、実機適用は別の完了条件として扱う。

## 1. 既存実装と責務を確認する

- 最初に`git status --short`を確認し、既存のユーザー変更を保持する。
- `README.md`、[Wiki](https://git.attodao.cc/AttODao/attos-nix-modules/wiki)の対象moduleページを読む。
- `modules/default.nix`、対象・依存moduleを確認する。
- 既存設定を移す場合は、利用側のNixOS / HM設定、package供給元、依存、実行時の前提を両scopeで追う。現在の設計・APIは採用revisionのREADME・Wiki・実装を確認する。
- 類似実装や標準NixOS / Home Manager optionを再利用し、独自resolver、ホスト台帳、不要なwrapperを追加しない。

### 共有側と利用側の境界

共有側は機能設定、機能間の依存、HMの読み込み・共通設定・package引数を担当する。
hardware、ユーザー作成、ログインシェル、権限・linger、secrets、stateVersion、保存先、unfree許可、機器固有値は利用側に残す。
機器固有値には、ユーザー名・アカウント・メールアドレスなどの個人識別情報、利用側が運用するサービスのFQDN・URL、デバイスのserial・IDを含む。共有側が既定値として持つのはpackageと機能設定だけで、これらは型付きoptionで利用側から受け取る。

秘密の内容をNix式へ埋め込んだり、Nix storeへ取り込んだりしない。必要な場合は復号後のruntime pathを参照する。
共有moduleはsecrets backend（`sops`・`agenix`等）の名前を知らない。`config.sops.secrets`などを直接参照せず、pathは必ず自moduleのoption経由で受け取る。
認証・履歴・可変データを宣言的設定で上書きしない。

## 2. 最小の公開APIを決める

- 機能選択はNixOS側の`modules.<name>.enable`に集約し、`lib.mkEnableOption`で既定falseにする。公開サーバーは`modules.public-services.<FQDN>.<service>`、localhost単独利用は`modules.<service>`を使う。`public-services/lib.nix`の`moduleOptions`で同じtyped schemaを再利用し、単独利用を公開registryへ注入しない（既存Paseo bridge、SSH client/serverのscopeは維持）。
- 公開サービスは有効時に`host`で所有OSの`networking.hostName`を指定する。物理ホスト・guestが同じnamespaceを読み、所有OSだけで実体を起動する。`deploy`は全種既定true、falseは管理外endpoint登録専用。別ホストのrecordをfalseに書き換える実装はしない。
- HM専用の機能にもNixOS側のenableを設ける。HM側に別のenableやstandalone HM exportを追加しない。
- enable以外の独自optionは、利用側から渡す必要がある値だけに限定する。型、説明、妥当な既定値または有効時の必須条件を定義する。
- ユーザーごとの調整は標準`home-manager.users.<name>`へ書けるようにする。調整可能な既定値には`lib.mkDefault`を使い、安易に`mkForce`で固定しない。大きな設定ツリー（shell・browser・barの設定など）は`lib.mapAttrsRecursive (_: lib.mkDefault)`で各leafを`mkDefault`にし、利用側が`mkForce`なしで一部だけ上書きできるようにする。
- 外部到達性・特権・信頼範囲を広げる値（relay・外部公開・socketマウント・信頼するproxy範囲・rate limit無効化など）は既定で無効にし、利用側が明示して有効化する。公開サービスの既定は単独利用より緩くしない。
- 同じ利用側option（既定アプリ・MIME関連付け・環境変数など）に既定値を主張するmoduleは1つにする。複数moduleが候補になるときは、`default.nix`の依存宣言や`mkIf (!config.modules.<other>.enable)`で排他にし、同優先度の値を並べて評価順に任せない。
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
- `nixos.nix`の実設定は`lib.mkIf config.modules.<name>.enable`で囲む。公開サーバーと単独利用は`public-services/lib.nix`の`select`・`moduleOptions`・`common`・`pathOption`・`require`を再利用し、`select.enabled`で同じ実装を囲む。`select.standalone`の場合だけlocalhost bind/HTTP・通常Docker bridgeを使い、公開record・gateway依存を作らない。公開時はnative serviceを`backendEndpoint`のaddress:portにbindし、`0.0.0.0`など全interfaceにbindしない。singleton assertionも登録し、無効・`host`不一致・`deploy = false`でlocal依存・必須path・unitを作らない。
- `public-services/lib.nix`はmodule引数`ps`（`_module.args.ps`）から使い、各moduleで`import ../public-services/lib.nix`しない。同じ導出（listen address、`network-online.target`依存、bracket除去など）が3 module以上に現れたら、各moduleへ写す前に`lib.nix`へ入れる。
- 公開namespaceはtypeを拡張するだけにし、rootのdefault / descriptionを各サービスで重複宣言しない。DNS・CNAME・proxyはnamespaceから導出し、consumerの`public-hosts.nix`や別のhost台帳をimportしない。具体例・制約は[Wikiの公開サービスAPI](https://git.attodao.cc/AttODao/attos-nix-modules/wiki/module-public-services)と各サービスページを参照。
- `home.nix`の実設定は`lib.mkIf osConfig.modules.<name>.enable`で囲む。
- HM設定は`home-manager.sharedModules`で接続する。特定ユーザーへの直書きや、ユーザー一覧を機能ごとに走査する実装はしない。
- 有効なHM設定は、標準`home-manager.users`に直接宣言したユーザーを含む全HMユーザーに適用される。固定アカウント・デバイス設定や複数ユーザーでの競合を確認する。

## 4. 登録とpackageの接続を行う

1. `modules/default.nix`の静的`imports`へ`./<name>`を追加する。
2. 通常のpackageは利用ホストの`pkgs`を使う。
3. custom derivation / overrideが必要な場合だけ、nixpkgsと同じ`packages/by-name/<先頭2文字>/<name>/package.nix`を作る。登録は自動で、`packages/default.nix`の編集は不要。consumer入力が必要なbuilderは`{ deps }: { args }: ...`のcurried形にし、nixpkgsの同名packageを上書きする場合は`pkgs.<name>`を参照する。
4. root直下に`package.nix`を持つ外部repoは、`flake.nix`へ`flake = false`のinputを追加し、`packages/default.nix`の外部input表へ1行追加する。
5. custom packageはmodule引数`attopkgs`から使う。機能module内で直接`callPackage`しない。供給は`flake.nix`の`nixosModules.default`に任せる。
6. 取得物はflake inputかpackage内のversion・hashで固定する。module・package内で`builtins.fetchTarball`・`fetchGit`など評価時にネットワークへ出る取得を使わない。外部repoはhash付きでも`flake = false`のinputにする。consumer固有のアーカイブURL・hashなどは利用側に残す。
7. 評価はpackageの中身に依存させない（IFD禁止）。`lib.importTOML "${pkgs.<x>}/..."`や`builtins.readFile`でstoreのpackageを読まず、必要な設定ファイルの元はrepoへコピーして`./`で参照し、更新は`update-packages`で扱う。packageはすべて`flake check --no-build`の対象に残す。

通常の機能追加で`flake.nix`へ個別module exportや別のHM読み込みを追加する必要はない。
Home Manager revision・共有nixpkgs・利用側nixpkgsの更新を機能追加に混ぜない。

## 5. 評価する

Nix moduleのテストは持たない。Goのcustom packageは各packageのtestと`go vet`をbuild内で実行する。リポジトリルートから次を実行する。

```sh
nix flake check --no-build 'path:.'
nix eval --raw 'path:.#packages.x86_64-linux.<name>.drvPath' # 変更したpackage
```

- `nix flake check --no-build`は、packageがstoreに無い状態でも通ること（§4-7）。
- 未有効時に機能設定・依存が勝手に有効にならないこと、enable一つで必要な設定が入ることは、利用側の`--override-input`付き評価で確認する。
- `path:`評価は未追跡ファイルも含む。既存のstage状態を検証のために変えない。
- 通常のflake評価には`--no-write-lock-file`を使う。依頼されていないlock更新・rebuild・switch・pushはしない。

評価成功はビルド成功・実機動作の保証ではない。boot、PAM、desktop起動、user service、外部機器などは利用側への移行後に別途確認する。

## 6. ドキュメントと差分を確認する

- `README.md`の機能一覧、scope、依存、独自option、利用側の前提を更新する。
- moduleのpackage/version・設定項目・設定例・運用上の制約はWikiの対応ページへ記載し、重複する機能別docsを増やさない。custom packageの実装・供給契約は`packages/README.md`へ記載する。作業履歴・成功ログはdocsへ残さない。
- version・revision・hashは1箇所（`flake.nix`のinput、`package.nix`、または`packages/default.nix`の外部input表）だけに書く。README・docsには「`flake.lock`／`package.nix`を参照」と書き、具体値を写さない。
- 利用側が`mkForce`なしで既定値を上書きできるか（§2）、権限・露出を広げる既定がopt-inか（§2）を確認する。
- `git diff --check`と対象ファイルのdiffを確認し、無関係な変更やcredentialがないことを確認する。新規ファイルは未追跡の内容も確認する。
- 完了報告には、変更した機能・ファイル、実行した検証、未検証事項を短く記す。利用側の移行や実機適用を行っていない場合は明示する。

## 7. CI workflowとCI用script

`.forgejo/workflows/`と`packages/by-name/at/attos-ci/`を変えるときに守る。

- `nix run`・`nix shell`はすべて`--inputs-from .`で`flake.lock`のnixpkgsに固定し、registry経由の未固定inputを使わない。CIが`nix run`する他repoのtool（`CI_TOOL`等）はrevで固定し、週次更新PRで上げる。
- tokenは使うstepの`env:`にだけ渡し、workflow全体やjob全体のenvに置かない。URLへ埋め込まず（`https://bot:$TOKEN@...`）、`git -c http.extraHeader=...`や`GIT_ASKPASS`で渡す。ログのマスク済み出力（`***`）をコードへ写さない。
- 全jobに`timeout-minutes`を付ける。複数ホストの評価を行うjobは`needs:`か`concurrency`で直列にし、共有runnerで同時に走らせない。
- 利用側のホスト一覧をCIに固定で持つ場合は、`workflow_dispatch`入力で上書きできるようにする。
