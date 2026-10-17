# 利用側dotfilesの移行手順

デスクトップ・サーバー・guestに共通で使う。新規ホストを作る手順ではなく、**既存のソフト・動作・永続データを保持する移行**を扱う。
input/importの例は[README](../README.md)、個別APIは[Wiki](https://forgejo.attodao.cc/AttODao/attos-nix-modules/wiki)、現在の未完了作業は[台帳](inventory.md)を参照する。

## 1. 編集前に対象と許可範囲を確定する

- 利用側のrepo path、branch、HEAD、remote、lockと全flake出力を確認する。古い調査commit・`/tmp`のcheckout・小さな別branchを稼働構成と思い込まない。構成が足りなければ対象を確認し、サービスが廃止済みと判断しない。
- 各 `nixosConfigurations` の出力名、実際の `networking.hostName`、物理ホスト/guestの別、HMユーザー、関連するimage/package/check出力を一覧にする。出力名・SSH alias・Incus instance名とhostnameは同じとは限らない。
- remote作業ではSSHのport・authorizedKeys・経路・firewall、sudoとconsole等の代替接続を保持する。既存ControlMasterに頼らない独立した新規接続も適用時に確認する。

## 2. 置換表と変更前の比較元を残す

共有側は採用するrevisionの `modules/default.nix`、対象・依存moduleを読み、Wikiの説明と実装が異なる場合は採用revisionの実装を確認する。

- package導入だけなら `environment.systemPackages` / `home.packages` へ残す。共有enableがないことを理由に削除しない。
- 旧featureから入っていたアプリ・library・toolchain・外部moduleも保持する。共有の自動依存が旧resolverと同じとは限らない。
- ホスト `pkgs` への切替で専用package setやoverrideが消えないか、version・patch・plugin・優先度・実行ファイルを比較する。全packageを名前だけで同一視しない。
- 共有にAPIが足りない場合も、先に機能を消したり `mkForce` で競合を隠したりしない。

## 3. 入口とHMを一本化する

1. 共有flakeが固定したraw HM sourceを使う。別HM input/import・standalone HM経路・重複する `attopkgs` 供給を置換する。
   旧HM revisionと異なる場合は差分を確認し、共有HMやnixpkgsをその場で更新して解消しない。
2. HMが必要な既存NixOSユーザーだけを `modules.home-manager.users` または標準 `home-manager.users` で管理し、ユーザーごとの従来の `home.stateVersion` を明示する。
3. 旧設定を公開APIへ置換する。共有featureのunit/script/program/activationの実装をconsumerから書き換えず、不足する型付き入力を共有側へ追加し、disabled/remote・既存state・生成設定を回帰検査する。
   identity/account/hardware/address/secret供給metadata、package-only・未対応外部program、API外のper-user差分は標準NixOS/HMへ残す。これらを減らすためだけのenableや汎用configuration passthroughは作らない。

共通HM設定は**全HMユーザー**へ適用される。追加ユーザーに固定account/deviceを配ったり、Paseo等の固定portで複数daemonを競合させたりしない。
共有側の変更が必要なら[AGENTS.md](../AGENTS.md)のmodule作成手順を使う。

## 4. 公開サービス・複数OSの配置を照合する

公開サービスの契約は[公開サービスAPI](https://forgejo.attodao.cc/AttODao/attos-nix-modules/wiki/module-public-services)と各サービスページを読む。

- `host` に親ホスト名・構成出力名を機械的に入れない。各所有OSにも必要な登録と共有入口を読み込ませる。
- 別ホストのrecordをfalseにするのではなく、管理外endpointだけを `deploy = false` で登録する。
- 旧 `public-hosts.nix` はこのnamespaceへ置換し、他用途の参照を確認してから削除する。別のホスト台帳/resolverを追加しない。
- private proxyだけでbackend直通やUDPを保護できると思わない。
- GroupwareのMailserver依存、Paseoの既存HMユーザー、code-serverのruntime認証、Sunshineのguest/GPU/audio/streaming条件は各APIに従う。公開登録だけでユーザー・秘密・deviceが用意されるわけではない。

## 5. 秘密・永続データ・既存guestを保護する

| 保持対象 | 必ず確認すること |
| --- | --- |
| Incus | image/instance/profile/device/storage/networkと作成時入力。既存instanceをdelete/recreateしない。image build/alias更新を既存guestのOS更新と混同しない |
| HM / Pi / Paseo | 既存ファイルとのcollision、全ユーザーの適用範囲・権限・linger・port。Piの旧writable settings mergeと共有HMの宣言的 `settings.json` は別契約。手編集設定の扱いを確認し、認証/session/履歴と可変stateを上書きしない |

サービスごとに次の非自明な契約も照合する（詳細は該当Wiki・実装）:

- mount条件・`ConditionPathExists`・`LoadCredential` は秘密を復号せず、rotation時の再起動も保証しない。producerからconsumerへの供給・順序を別に維持する。
- Swarmは既存clusterを作り直さず、公開OCI用encrypted `backend-<service>` overlaysをmanagerが作成しworkerが待機する。旧共有overlayの削除は別工程。既存workerにもruntime join tokenファイルの読取が必要。managerのport 2378はreadiness用で、token配布は明示tokenTransportを有効にした場合だけ。
- Incus preseedは指定poolが存在すると全体をskipする。欠けたprofile/networkを修復せず、`stateDir` はstamp用でguest/storageのbackupではない。`launchConfig` はstore内JSONへ入るため秘密を埋め込まない。image archiveにも秘密を同梱しない。
- Incusは既存instanceでもimage入力を要求し、宣言したStopped instanceを起動する。import判定はsource pathベースなので同じpathの内容変更は更新にならない場合がある。instance名変更を既存guestのrename/移行と扱わない。managed deviceの変更も別に確認する。
- Mailserverのnative保存先を上書きする場合、`dataDir` 由来のtmpfiles・mount条件も照合する。Groupwareの `dataDir` はRadicale用で、Roundcubeのdes_key・PostgreSQL・mailのstateは別。Groupwareの受信accountにはruntime bcrypt `hashedPasswordFile` が必要。
- MailserverのRspamdは既定 `127.0.0.1:53` / `kresd@1.service` に依存する。共有 `modules.dns` はdnsmasqで、enableしてもkresdは作られない。既存Knot Resolverを保持するか、Rspamdのresolver設定と依存unitを両方整合させる。
- Piの手編集settings/provider/model/extensionはactivation前にbackup・引継ぎ方針を確認する。Paseoは毎起動 `~/paseo/config.json` を置換し、固定 `attopkgs.paseo` CLIを使う（実行時npm latest取得なし）。HMのbackup suffixで全可変stateが守られると思わない。
- SSH clientの生成configはactivationで手編集を置換する。標準HMへ追加設定を移し、`ssh -G` でalias/FQDN・port・user・鍵policyを比較する。code-serverの旧release/font/packageとデータ/実行ユーザー、Sunshineのheadless/device/audio/pairing/streaming条件も自動継承とは限らない。

SOPSの既定はactivation復号で、`sops-install-secrets.service` は `sops.useSystemdActivation = true` の場合だけ存在する。
存在しないunitへの依存を足したり、順序設定のためだけに復号方式を変えたりしない。共有optionへservice名を渡す場合も実在を確認する。

guest imageの構成も評価対象に含める。**新規guest用image・初回secret bootstrapと、既存guest内での設定適用は別工程**。
Incusのcreate-only処理や新imageだけでは既存rootfsは更新されない。

## 6. 変更前後を比較する

全ホスト・guest・HMユーザーを対象に、最低限次を比較する:

- package/program・version/override/優先度、生成設定、activationと起動経路。
- ユーザー・両stateVersion・PAM/SSH・secret参照と権限・復号順序・再起動条件。
- mount/volume・OCI/Swarm・service unitの名前/実行ユーザー/依存・公開DNS/proxy/firewall/VPN。
- desktop/headlessならmonitor・入力・portal・GPU/audio・録画、開発用ならSDK/JDK・sandbox/device・project資産。

共有側は[READMEの検証](../README.md#検証)の評価を行う（テストはない）。

## 7. 旧実装の削除と完了報告

- 全参照の置換と比較後に旧resolver・featureMatrix・wrapper・重複HM importを削除する。guest/imageや別出力からの参照も確認する。
- 完了した項目は[残作業台帳](inventory.md)から削除する。履歴・成功ログはGit履歴/PR等へ残し、台帳に完了済み一覧を増やさない。
