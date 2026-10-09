# 利用側dotfilesの移行手順

既存のNixOS / Home Manager（HM）設定を `attos-nix-modules` へ置き換えるエージェント向けの手順。
デスクトップ・サーバー・guestに共通で使う。新規ホストを作る手順ではなく、**既存のソフト・動作・永続データを保持する移行**を扱う。
input/importの例は[README](../README.md)、個別APIは[Wiki](https://forgejo.attodao.cc/AttODao/attos-nix-modules/wiki)、現在の未完了作業は[台帳](inventory.md)を参照する。

## 1. 編集前に対象と許可範囲を確定する

- 利用側・共有側の `AGENTS.md` と `git status --short` を確認し、既存変更・stage状態を保持する。
- 利用側のrepo path、branch、HEAD、remote、lockと全flake出力を確認する。古い調査commit・`/tmp`のcheckout・小さな別branchを稼働構成と思い込まない。構成が足りなければ対象を確認し、サービスが廃止済みと判断しない。
- 各 `nixosConfigurations` の出力名、実際の `networking.hostName`、物理ホスト/guestの別、HMユーザー、関連するimage/package/check出力を一覧にする。出力名・SSH alias・Incus instance名とhostnameは同じとは限らない。
- コード移行、共有側のAPI変更、他repoの統合、lock更新、build、適用、commit/pushのうち依頼された範囲を区別する。他repoの統合やnixpkgs/HM更新を移行に便乗させない。
- 稼働構成との対応と復旧経路を確認する。remote作業ではSSHのport・authorizedKeys・経路・firewall、sudoとconsole等の代替接続を保持する。既存ControlMasterに頼らない独立した新規接続も適用時に確認する。唯一のSSHを失った後では `--rollback` も実行できない。文書の例で実機のユーザー・NIC・保存先を置き換えない。

利用側ルートでの構成名確認例:

```sh
nix eval --no-write-lock-file --json '.#nixosConfigurations' --apply builtins.attrNames
```

稼働generationやguestの調査ができない場合は「コード確認のみ」と記録する。未確認の稼働状態を推測して移行・適用済みにしない。

## 2. 置換表と変更前の比較元を残す

旧resolver・feature定義の名前だけでなく、import先、暗黙依存、package供給元、NixOSと全HMユーザーの設定まで追う。
共有側は採用するrevisionの `modules/default.nix`、対象・依存module、関連 `tests/` を読み、Wikiの説明と実装が異なる場合は採用revisionの実装を確認する。

機能ごとに次を記録する（利用側の作業メモ/PR等で十分。秘密の内容は記録しない）:

| 旧設定 | 置換先 | 保持する入力・差分 | 比較方法 |
| --- | --- | --- | --- |
| 機能・依存・package供給元 | 公開 `modules.*` / 標準option / 維持する外部module | ユーザー、path、secret参照、起動条件等 | 評価値、生成設定、unit、package等 |

- package導入だけなら `environment.systemPackages` / `home.packages` へ残す。共有enableがないことを理由に削除しない。
- 旧featureから入っていたアプリ・library・toolchain・外部moduleも保持する。共有の自動依存が旧resolverと同じとは限らない。
- ホスト `pkgs` への切替で専用package setやoverrideが消えないか、version・patch・plugin・優先度・実行ファイルを比較する。全packageを名前だけで同一視しない。
- 意図的な変更は理由と影響を別記し、互換性判断を要するものは承認を得る。共有にAPIが足りない場合も、先に機能を消したり `mkForce` で競合を隠したりしない。

変更前の設定を評価できるうちに、非秘密の評価結果と生成設定を比較用に保存する。
暗号化secret・hardware設定は移動する場合も内容を保持する。秘密ファイルやPi等の認証・session・履歴を読む/ログ出力する必要はない。

## 3. 入口とHMを一本化する

1. 既存のnixpkgs pin・overlay・unfree方針と他inputのpinを維持し、共有inputを追加する。
   URLは `git+https://forgejo.attodao.cc/AttODao/attos-nix-modules.git?ref=main`。各NixOS構成で `nixosModules.default` を一度だけimportする。
2. 導入に必要なlock差分だけ作り、共有revisionと依存を確認する。更新時は該当input名だけを `nix flake update INPUT` へ渡す。
   `flake.lock` がignore/未管理なら既存pinの取得元・公開方針を確認し、勝手に最新版へ解決しない。
3. 共有flakeが固定したraw HM sourceを使う。別HM input/import・standalone HM経路・重複する `attopkgs` 供給を置換する。
   旧HM revisionと異なる場合は差分を確認し、共有HMやnixpkgsをその場で更新して解消しない。
4. HMが必要な既存NixOSユーザーだけを `modules.home-manager.users` または標準 `home-manager.users` で管理し、ユーザーごとの従来の `home.stateVersion` を明示する。
   ユーザー作成・home・UID/GID・shell・group/sudo・linger・`system.stateVersion` は利用側に保持する。HM既定値は既存値を上げる理由にならない。
5. 旧設定を公開APIへ置換する。共有featureのunit/script/program/activationの実装をconsumerから書き換えず、不足する型付き入力を共有側へ追加し、disabled/remote・既存state・生成設定を回帰検査する。
   identity/account/hardware/address/secret供給metadata、package-only・未対応外部program、API外のper-user差分は標準NixOS/HMへ残す。これらを減らすためだけのenableや汎用configuration passthroughは作らない。
   `mkDefault` は通常代入で上書きする。自動依存への通常のfalseは競合するので、依存の動作条件を確認する。

共通HM設定は**全HMユーザー**へ適用される。追加ユーザーに固定account/deviceを配ったり、Paseo等の固定portで複数daemonを競合させたりしない。
共有側の変更が必要なら[AGENTS.md](../AGENTS.md)のmodule作成手順を使う。検証用のlocal overrideを最終lockへ残さず、採用する公開revisionで再評価する。

## 4. 公開サービス・複数OSの配置を照合する

公開サービスの契約は[公開サービスAPI](https://forgejo.attodao.cc/AttODao/attos-nix-modules/wiki/module-public-services)と各サービスページを読む。

```nix
modules.public-services."vault.example.org".vaultwarden = {
  enable = true;
  host = "service-os"; # サービスが動くOSのnetworking.hostName
  dataDir = "/srv/vaultwarden"; # 既存保存先へ置換
  environmentFile = "/run/secrets/vaultwarden.env"; # 復号後のruntime文字列
};
```

- 物理ホスト・guestで同じnamespaceを読み、`enable && deploy && host一致` のOSだけが実体を起動する。
  `host` に親ホスト名・構成出力名を機械的に入れない。各所有OSにも必要な登録と共有入口を読み込ませる。
- `deploy` は既定true。別ホストのrecordをfalseにするのではなく、管理外endpointだけを `deploy = false` で登録する。
  有効recordの `host` は必要だが、remote/管理外recordのlocal secret・保存先・unitは要求しない。
- DNS・CNAME・gatewayは有効な全登録を参照する。旧 `public-hosts.nix` はこのnamespaceへ置換し、他用途の参照を確認してから削除する。別のホスト台帳/resolverを追加しない。
- local実体は同一host・サービス種別ごとに1件まで。内部Docker DNS名/portが固定のサービスを、FQDNを増やすだけで独立配備できると解釈しない。
- private proxyだけでbackend直通やUDPを保護できると思わない。DNS records、到達先、Swarm network/role、listen address、firewall/NAT、VPN内からの到達性も照合する。
- GroupwareのMailserver依存、Paseoの既存HMユーザー、code-serverのruntime認証、Sunshineのguest/GPU/audio/streaming条件は各APIに従う。公開登録だけでユーザー・秘密・deviceが用意されるわけではない。

## 5. 秘密・永続データ・既存guestを保護する

| 保持対象 | 必ず確認すること |
| --- | --- |
| secrets | 復号後の引用符付きruntime絶対パス、owner/group/mode、読取ユーザー、起動順、rotation時の再起動。秘密の内容をNix式・パスリテラル・`builtins.readFile`・storeへ入れない |
| storage / OCI / DB / mail | mount、volume、保存先、UID/GID、既存DB・mail/TLS/DKIM、stateVersion、image/versionと更新方針。新しい空directoryを同じデータだと扱わない |
| Swarm / VPN | 既存clusterのrole/address/network、join token供給、routing/DNS、鍵・client・firewall。移行のためのcluster再作成・鍵再生成をしない |
| Incus | image/instance/profile/device/storage/networkと作成時入力。既存instanceをdelete/recreateしない。image build/alias更新を既存guestのOS更新と混同しない |
| HM / Pi / Paseo | 既存ファイルとのcollision、全ユーザーの適用範囲・権限・linger・port。Piの旧writable settings mergeと共有HMの宣言的 `settings.json` は別契約。手編集設定の扱いを確認し、認証/session/履歴と可変stateを上書きしない |

サービスごとに次の非自明な契約も照合する（詳細は該当Wiki・実装）:

- mount条件・`ConditionPathExists`・`LoadCredential` は秘密を復号せず、rotation時の再起動も保証しない。producerからconsumerへの供給・順序を別に維持する。
- Swarmは既存clusterを作り直さず、公開OCI用encrypted `backend-<service>` overlaysをmanagerが作成しworkerが待機する。旧共有overlayの削除は別工程。既存workerにもruntime join tokenファイルの読取が必要。managerのport 2378はreadiness用で、token配布は明示tokenTransportを有効にした場合だけ。
- Incus preseedは指定poolが存在すると全体をskipする。欠けたprofile/networkを修復せず、`stateDir` はstamp用でguest/storageのbackupではない。`launchConfig` はstore内JSONへ入るため秘密を埋め込まない。image archiveにも秘密を同梱しない。
- Incusは既存instanceでもimage入力を要求し、宣言したStopped instanceを起動する。import判定はsource pathベースなので同じpathの内容変更は更新にならない場合がある。instance名変更を既存guestのrename/移行と扱わない。managed deviceの変更も別に確認する。
- Mailserverのnative保存先を上書きする場合、`dataDir` 由来のtmpfiles・mount条件も照合する。Groupwareの `dataDir` はRadicale用で、Roundcubeのdes_key・PostgreSQL・mailのstateは別。Groupwareの受信accountにはruntime bcrypt `hashedPasswordFile` が必要。
- MailserverのRspamdは既定 `127.0.0.1:53` / `kresd@1.service` に依存する。共有 `modules.dns` はdnsmasqで、enableしてもkresdは作られない。既存Knot Resolverを保持するか、Rspamdのresolver設定と依存unitを両方整合させる。ACME供給とSMTP/IMAP/DKIM等は実機で確認する。
- Piの手編集settings/provider/model/extensionはactivation前にbackup・引継ぎ方針を確認する。Paseoは毎起動 `~/paseo/config.json` を置換し、固定 `attopkgs.paseo` CLIを使う（実行時npm latest取得なし）。HMのbackup suffixで全可変stateが守られると思わない。
- SSH clientの生成configはactivationで手編集を置換する。標準HMへ追加設定を移し、`ssh -G` でalias/FQDN・port・user・鍵policyを比較する。code-serverの旧release/font/packageとデータ/実行ユーザー、Sunshineのheadless/device/audio/pairing/streaming条件も自動継承とは限らない。

SOPSの既定はactivation復号で、`sops-install-secrets.service` は `sops.useSystemdActivation = true` の場合だけ存在する。
存在しないunitへの依存を足したり、順序設定のためだけに復号方式を変えたりしない。共有optionへservice名を渡す場合も実在を確認する。

guest imageの構成も評価対象に含める。**新規guest用image・初回secret bootstrapと、既存guest内での設定適用は別工程**。
Incusのcreate-only処理や新imageだけでは既存rootfsは更新されない。既存guestの適用・秘密の供給方法が不明なら止めて確認する。
code-server/Sunshineを含め、認証状態・ユーザー・device・データ供給を移行の副作用で初期化しない。

## 6. 変更前後を比較し、評価・build・適用を分ける

全ホスト・guest・HMユーザーを対象に、最低限次を比較する:

- package/program・version/override/優先度、生成設定、activationと起動経路。
- ユーザー・両stateVersion・PAM/SSH・secret参照と権限・復号順序・再起動条件。
- mount/volume・OCI/Swarm・service unitの名前/実行ユーザー/依存・公開DNS/proxy/firewall/VPN。
- desktop/headlessならmonitor・入力・portal・GPU/audio・録画、開発用ならSDK/JDK・sandbox/device・project資産。

store hashや順序を正規化する場合も、実体のversion・内容・優先度・unit名・保存先の違いを消さない。
旧Pi設定方式、専用package set、headless起動等の差分は台帳の昔の結果ではなく、今回の対象revisionで判断する。

利用側ルートで、`HOST` / `USER` を対象へ置換する:

```sh
# 評価だけ。全構成・全HMユーザーで実行する
nix eval --no-write-lock-file --raw '.#nixosConfigurations.HOST.config.system.build.toplevel.drvPath'
nix eval --no-write-lock-file --raw '.#nixosConfigurations.HOST.config.home-manager.users.USER.home.activationPackage.drvPath'
# buildだけ。適用権限とは別に、依頼範囲で実行する
nix build --no-write-lock-file --no-link '.#nixosConfigurations.HOST.config.system.build.toplevel'
nix build --no-write-lock-file --no-link '.#nixosConfigurations.HOST.config.home-manager.users.USER.home.activationPackage'
```

HMユーザーなしのOSにはHMのコマンドは不要。利用側のchecks・image/package出力があればそれらも確認する。
新規NixファイルはGit flakeに含まれるよう必要なものだけstageし、既存stageを変更しない。
共有側の対象・依存・統合テストは[READMEの検証](../README.md#検証)に従い、利用側固定nixpkgs・共有固定HMで実行する。
共有側の `nix flake check` は `tests/*.nix` の実行に代わらない。

評価成功はbuild成功ではなく、image build成功は既存guest更新でも実機動作確認でもない。
適用は明示的な許可、データbackupと復旧経路を確保して一台ずつ行う。remoteの認証・networkを失う変更は特に分離する。
`switch`、reboot、service再起動、DB移行、DNS変更、Incus操作、データ移動をコード移行の確認として無断実行しない。
失敗時は前のinput/lock/設定とgenerationへ戻す。永続データはgeneration rollbackでは戻らないため別途backupから復旧する。

## 7. 旧実装の削除と完了報告

- 全参照の置換と比較後に旧resolver・featureMatrix・wrapper・重複HM importを削除する。guest/imageや別出力からの参照も確認する。
- `git diff --check` と差分を確認し、credential・暗号化secret/hardwareの意図しない変更・依頼外のpin更新がないことを確かめる。
- 利用側repo/commit・共有採用revision・対象OS/ユーザー、保持した入力、意図した差分、比較/評価/build結果を報告する。
- 未実施のbuild・適用・実機確認と確認できない対象を明記する。共有のテスト成功やcommit/pushだけで利用側移行・適用完了にしない。
- 完了した項目は[残作業台帳](inventory.md)から削除する。履歴・成功ログはGit履歴/PR等へ残し、台帳に完了済み一覧を増やさない。

## エージェントへの依頼例

次はコード移行のみを依頼する例。対象・許可範囲は依頼者が置換する。

> `/path/to/dotfiles` の指定したNixOS構成を attos-nix-modules へ移行してください。
> 利用側AGENTSと共有側README・docs/migration.md、対象moduleの実装/Wikiを先に読み、現地checkoutと全構成（guest/image/HMを含む）を確認してください。
> 既存inputのpin・ソフト・秘密参照・永続データ・ユーザー・stateVersion・ホスト差分を保持し、変更前後を比較してください。
> 共有入口と公開APIを使い、未移行機能は標準設定として残してください。共有側の変更や別repo統合が必要なら先に相談してください。
> 導入に必要な共有inputのlock差分と評価までを行い、build・実機適用・データ操作・commit/pushは行わず、残作業と意図した差分を報告してください。
