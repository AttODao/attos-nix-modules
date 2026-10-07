# 共通化・移行の作業台帳

更新: 2026-10-06。commit済み共有実装の基準は `f7a38da`。以下は追加実装と共有側の検証記録。利用側移行・実機適用は未実施。
現在のAPIは[root README](../README.md)と[Wiki](https://forgejo.attodao.cc/AttODao/attos-nix-modules/wiki)、実装は[modules](../modules)を参照する。
この台帳は残作業と移行時の差分を管理し、moduleの設定リファレンスはWikiへ集約する。

**共有側の実装・公開は完了。次は移行対象repo/revisionを確定し、各dotfilesの移行と実機検証を進める。**
共有moduleがあること、利用側のコードを移行したこと、実機へ適用したことは別の状態として扱う。
以下の未実装候補をすべて作るまで移行を待つ必要はない。

## 1. 完了済み: 共有リポジトリ

- [x] `modules/default.nix`へ50 moduleを登録し、NixOS側のenableに機能選択を集約。
- [x] NixOS組み込みHome Manager、全HMユーザーへの共通設定、`attopkgs`の自動供給を実装。
- [x] デスクトップ・クライアント・音声・開発ツールと、公開/非公開サーバー機能を実装。
- [x] 公開サービスを `modules.public-services.<FQDN>.<service>` へ集約し、DNS・CNAME・gatewayを導出。remote登録とlocal deploymentを分離。
- [x] custom package、付随script、評価テスト・runtimeテストを本体へcommit・push。
- [x] 全50 moduleのWikiページとカテゴリ別sidebarを公開。
- [x] desktop側の固定nixpkgsで全27評価テスト、server側で関連8評価テスト、Pythonテスト12件、Nix構文133件が成功。

上記の公開・検証は2026-10-05時点の記録。**package/imageの全体ビルド、各ホストへの移行・rebuild・実機動作は未検証。**

### 2026-10-06: 作業ツリーの追加実装

- `desktop-theme`、`steam`、`wireguard-client`、`limine`、`atcoder`、`code-server`、`sunshine` の7 moduleを追加。静的importは57件。
- 公開サービスに所有OSを指定する `host` を追加。有効時は必須で、`networking.hostName` に一致するOSだけをlocal deploymentする。DNS/CNAME/gatewayは全ホストの登録を参照する。未公開draftの `machine` / null時の全ホスト配備は廃止。
- code-server/Sunshine/SSHも含め `deploy` の既定をtrueに統一。通常はnamespaceの `enable` と `host` だけでnative実体・依存を制御し、`deploy = false` は管理外endpoint登録に限る。
- custom AtCoder tools/commands、consumer供給standalone release用code-server/Nerd Font packageを追加。プロジェクト資産、秘密・可変データ、hardware、保存先・firewallはconsumerに残す。
- Piの旧server writable-mergeと現行HM宣言的settingsの差は、依頼によりそのまま維持する。Piの実装変更は行わない。

現作業ツリーの検証: desktop/serverの固定nixpkgs 2 sourceで全37評価テストがそれぞれ `true`、Nix構文164件が成功。WireGuard clientのruntimeテスト5件、AtCoder mock command build/runtime、code-server mock installも成功。本体/Wikiの `git diff --check` が成功。実package/imageの全体build・利用側評価・rebuild・実機動作は未検証。Wikiへ追加機能のAPIと運用条件を反映する。
機能一覧・依存は[root README](../README.md#機能と依存)、検証コマンドは[検証](../README.md#検証)を参照する。

### 2026-10-07: 公開API整理とnative上書き

- server `492d18d88ec5`・desktop `68c1ab04de84`の非秘密snapshotと全moduleの独自optionを照合。namespaceは既存の`modules.*`を維持し、固定値・標準設定との重複aliasを削減。秘密path・保存先・所有権・物理endpoint・identity等の必須consumer入力は残す。
- OCI backend/内部port、SunshineだけのTLS検証例外、Swarm readiness 2378、共通cron、wg0とIncus image aliasを実装側へ固定。WireGuard server keyはnative `wg0.privateKeyFile`、Incus初期化poolはnative preseedから導出する。
- GUI/OCIの調整可能な既定値を通常代入で変更可能にし、Wallpaper launcher・録画保存先activation・selected package/cursorを有効なnative設定へ追従させる。Noctalia個人account/locationと追加SSH設定はユーザーごとの標準HMへ移す。
- 固定nixpkgs `c59305bab2065cfecc4944690d9eedbb56f3a9fa`と`733f5a0e05eb015f1dc29c65da2839505750c785`の両source、固定HMで全37評価がそれぞれ`true`、15 runtimeスクリプトsuiteが成功。Nix構文164件・Python構文25件が成功。AtCoderは小さなmock toolのderivationのみbuildし、実package/image・NixOS全体のbuild、実機startup、consumer移行は未検証。
- WireGuard clientはnative libnmで自動接続false・最終interface名を設定してからIN_MEMORY | BLOCK_AUTOCONNECTで登録する。従来のnmcli import後に無効化する競合を排除し、作成時点のregressionを追加。実NetworkManagerへの登録・routing/DNSは未検証。
- attodesk/attolap相当の評価はmonitor/HDR/lid/録画・選択の分離、通常のper-user override、activation/toplevel drvPathを確認する。実機同等性の保証ではない。利用側lock更新・rebuild・switchは行っていない。

## 2. 優先して進める残作業

| 優先度 | 作業 | 完了条件 |
| --- | --- | --- |
| P0 | 移行対象のrepo/revisionを確定 | サービスを含むserver側の対象ツリーとdev/remote repoを確認。旧調査と現在のcheckoutを取り違えない |
| P1 | 各dotfilesを共有inputへ移行 | 対象を確認できたホストが共有入口を読み込み、旧設定との重複がない |
| P1 | 利用側の入力・差分を確認 | stateVersion、package供給元、秘密、保存先、権限、機器・公開設定を保持し、下記の差分を判断済み |
| P1 | ホスト構成・package/imageを検証 | NixOS/HMの評価・buildと生成設定の比較が成功。共有側の評価成功だけで完了にしない |
| P1 | 実機へ段階適用 | バックアップ後に一台ずつ適用し、起動・認証・user service・外部サービスとrollbackを確認 |
| P2 | 旧resolver・wrapperを整理 | 全参照を置換した後に削除。ホスト固有設定や未移行機能を先に消さない |
| 任意 | 未実装候補・package-only featureの整理 | 必要性を確認したものだけ別作業で実施。移行の必須条件にはしない |

### 利用側の移行対象

対象ホストは旧調査の構成名。実機の現在のgeneration・手編集・データ状態は未確認のため、コード移行と別に確認する。

| repo / 対象 | コード移行 | 主な確認事項 |
| --- | --- | --- |
| `.dotfiles` / attodesk・attolap | **未移行（確認済み）** | 一般ユーザー・shell・stateVersion、モニター/HDR、蓋・電源、PIN、録画、保存先。attodeskだけの機能をattolapへ広げない |
| `server-dotfiles` / attofort・attobox | **未移行（サービス構成のcheckoutを確認済み）** | 対象確認後にstate/ownership・secret順序、Swarm role、DNS/gateway、mail/TLS/DKIM、VPN、Incus、Paseo用HMユーザーを照合 |
| `dev-dotfiles` → `server-dotfiles` / development（devcon） | **統合未実施（移植元確認済み）** | devユーザー、Pi/Paseo、SSH、code-server、SDK/JDK、containerのsandbox/device設定を保持 |
| `remote-dotfiles` → `server-dotfiles` / desktop | **統合未実施（移植元確認済み）** | headless/seatd/linger、Sunshine/仮想音声、認証/firewall、Noctalia起動、Zed、専用package setを保持 |

2026-10-05のローカルコード確認:

- `.dotfiles` のHEADは `68c1ab04de84c0dd4975e60a246b6834bef5a204`。`flake.nix` / `flake-inputs/flake.nix` に共有inputはなく、`lib/features.nix`・手動HM import・standalone HM出力・featureMatrixが残る。共有側とHM revisionが同じでも、移行済みではない。
- `server-dotfiles` のHEADは `950b502fa073ca24b8d0644d705f7427ffc11ae4`（2026-06-27）。共有input/HMはなく、Zsh/Starship・Docker/OpenSSH等の小さな構成。旧調査のサービス群・resolver・`public-hosts.nix` はこのcheckoutにはなく、旧server調査commitもローカルで参照できない。サービスの移行・削除が済んだという証拠にはしない。ローカル `flake.lock` はignoreされているため、利用側のpin公開方針も確認する。
- dev/remoteはローカル探索で見つからず、現在のHEAD・設定・移行状態を確認できていない。表のhost/output名は旧調査に基づく。

2026-10-06の追加確認（上記2026-10-05の探索記録とは区別する）:

- `/tmp/dotfiles-sharing-audit/` にサービス構成を含むserver、dev、remoteのcheckoutを発見した。server=`492d18d88ec56135be1d9d5e9e50bd9e04d6b258`、dev=`762ffd11dd150f591a6a0583348e96175398d45e`、remote=`12b4cc92408e641c17d9cb954c831ffcbc9e8e2e`。
- `.dotfiles` は引き続き `68c1ab04de84c0dd4975e60a246b6834bef5a204`。全4 checkoutはcleanで、調査時のremote HEADと一致した。
- 4 repoとも共有inputへの移行は未実施。実機のgeneration・データ・動作は未確認。

共有側のpushだけで移行完了にはせず、完了時は確認した利用側commitと適用ホストを追記する。

### 各repoで行う手順・完了チェック

まず一台・低リスクの機能から進め、共有抽出やnixpkgs/HM更新を同時に混ぜない。

- [ ] 既存設定、package供給元、stateVersion、生成設定を記録し、永続データ・認証情報をバックアップする。
- [ ] 共有inputを固定して `nixosModules.default` を一度importし、利用側の手動HM読み込み・共通package引数供給の二重化を解消する。
- [ ] HM対象の既存ユーザーを指定し、従来の `home.stateVersion` を明示する。ユーザー作成・shell・権限・lingerは利用側に残す。
- [ ] 旧設定を機能enableへ置換し、旧featureと共有moduleの依存を比較して必要なアプリを明示的に選択する。ユーザー差分は標準 `home-manager.users.<name>`、ホスト差分は標準NixOS optionへ残す。旧Zsh featureにあるログインshell指定も利用側へ移す。
- [ ] サーバー/guestでは公開登録を共通namespaceへ移し、所有OSを `host` に実hostnameで指定する。管理外endpointは `deploy = false` にする。ホスト台帳の他用途も確認してから旧 `public-hosts.nix` 参照を整理する。
- [ ] 必須のruntime secret/path、保存先・UID/GID、Swarm role/network等を指定し、既存stateを上書きしないこととsecretの供給順・rotation時の再起動を確認する。
- [ ] ホスト全体と全HMユーザーのactivationを評価・buildし、旧生成設定・起動経路と比較する。
- [ ] 一台ずつ適用し、boot/PAM/desktop/user serviceとサービス固有の動作を確認する。失敗時は共有inputの更新を戻し、前のlock・NixOS generationへ戻す。データ変更の復旧は別にバックアップを使う。
- [ ] 全参照を置換した後に旧feature resolver・wrapper・featureMatrix・不要なstandalone HM経路を削除し、利用側commit・実機確認結果をこの台帳へ記録する。

## 3. 移行時に判断・検証する差分

旧repoを単純に最新の一つへ統一せず、共有実装との差を比較する。設定例・標準optionでの調整方法は各Wikiページを参照する。

| 対象 | 旧構成との主な差・残る確認 |
| --- | --- |
| Pi / Paseo | 旧S/Dの専用Pi package setと、共有側のホスト `pkgs` 供給を照合する。旧Sのpi-sessions revisionはL/Dと異なる。認証・履歴・可変JSONを壊さず、Paseoのenvと固定port、公開local配置のHMユーザー1名制約を確認 |
| SSH client / sshd | 旧repoごとにalias/FQDN、`IdentitiesOnly`、鍵指定が異なる。生成後の `ssh -G` を比較し、600のユーザー所有config・owner-check回避を維持。認証policy・server port・鍵配布はclient共有とは別 |
| Fcitx5 / SKK | 旧remoteのkeyboard-us Layoutは `us`、共有側は空文字。実ファイル配置と `ExitType=cgroup` による後発修正、GUI再起動、日本語入力を確認 |
| Noctalia / Hyprland | 旧localのNoctalia依存で入っていた各アプリは、共有側の依存に含まれるとは限らないため選択を保持。旧remoteの外部HM module・systemd/headless待ちはnative moduleと起動hookへ照合し、二重起動を避ける。dockのeditor差・calendar secret・HDR録画変換・portal/GPU権限も保持 |
| PCManFM / userDirs | attodeskの `/mnt/hdd1` と各ユーザーの保存先、attolapの `Pictures/Screenshots/.keep` を保持。共有userDirsを有効にするだけでホスト固有directory資産がすべて移ると思わない |
| Discord | 旧remoteだけのWayland package override・`KillMode=mixed` は共有実装にはない。必要な差分を標準optionで残して起動・終了・入力を検証 |
| Open-Deck | 旧localのactivation時latest取得、旧remoteの固定AppImageから、共有の固定packageへ移行。旧更新scriptを二重実行しない。x86_64制約・upstreamの `--no-sandbox` を確認 |
| OpenCloud client | 旧remoteの専用package setと共有のホスト `pkgs` を照合。二重autostartを避け、選択packageの起動・接続先を確認。serverとは別機能 |
| Thunderbird | 共有側は既定client確認を無効化し、固定account設定を全HMユーザーへ配布する。ユーザーごとのaccount・既存profile・credentialを確認 |
| server state / 公開範囲 | volumeレイアウト、floating image、Swarm既存cluster、mailのstateVersion、VPN key/client、Incusのcreate-only挙動を維持。private proxyだけでbackend直通/UDPを保護できると思わない |

旧repo名: L=`.dotfiles`、S=`server-dotfiles`、D=`dev-dotfiles`、R=`remote-dotfiles`。
これらの差分は移行時の確認項目であり、共有側の未実装機能や適用済みの保証を表すものではない。

## 4. 未実装候補: 必要なら別作業

旧調査で重複があったが、現在の共有moduleにはないもの。利用側に既存設定を残して移行できる。

| 候補 | 現状・範囲 | 追加するなら確認すること |
| --- | --- | --- |
| `nix-ld` | S/D/Rの標準 `programs.nix-ld` 設定は未抽出 | enableと本当に共通のlibraryだけ。Sの既定library、DのNode、RのGL/Wayland/audioを無条件に和集合にしない |
| `obs-studio` | L/Rの標準 `programs.obs-studio.enable` は未抽出 | 標準optionの直接設定で十分か判断し、PipeWireの依存と録画動作を保持 |

以下は追加moduleを作る必須作業ではない。

- package導入だけのfeature（旧調査ではL 27 / S 9 / D 7 / R 16、計59定義）は、利用側の `home.packages` / `environment.systemPackages` へ整理する候補。`python3.withPackages` やMoonlightのVPN依存は消さない。
- locale、Nix基本設定、NetworkManager/networkd等は標準optionを使う。共通化する必要が出るまではホスト側に残す。unfree・trusted-users・sandbox・NIC/IP/NAT/firewallを共有baseへ押し込まない。
- Plymouthの独自素材、Bluetooth/thermal/firmware、service-storage、container baseはconsumer側の保留項目。Limineの共通loader設定は今回追加済み。複数consumerで同じ契約が必要になるまでは残りの共有APIを作らない。
- floating tag・実行時latest取得の固定化は任意の別変更。移行中に更新policyまで同時変更しない。

## 5. 意図してホスト側に残すもの

これは「未実装だから追加する」一覧ではない。

- hardware・GPU/device割当、disk UUID/mount、ユーザー・group・authorizedKeys・sudo、shell、linger、stateVersion。
- secret集合・復号方法・owner/group/restartUnits・Age鍵path。秘密の内容をNix式やstoreへ入れない。
- 保存先、hostname/NIC/IP/route/NAT/firewall、公開FQDN、Swarm role/address、WireGuard clients、Incus image/instance/device定義。
- attodeskの音声loopback/Scarlett、HDR録画変換、Steam/Wallpaper Engine assets、AAGL、attolapの電源管理。旧調査のMIDI bridgeは現在のlocalから削除済みであり、残作業として復活させない。
- developmentのAndroid SDK/USB・AtCoder/project固有資産・JDK固定、desktopのZed・headless出力・仮想音声。code-server/Sunshineの共通実体は追加済みだが、保存先・実行ユーザー・runtime認証・devices・firewallはconsumer。
- guest image生成と既存guestへの適用の区別。code-server/Sunshineも `enable` と `host` で所有OSに起動するが、ユーザー・device・秘密の初期供給は自動化しない。Incusのimage更新で既存rootfsを再作成しない。

## 6. 旧調査の比較元

2026-10-04の調査commitを、移行時に旧設定を比較するため残す。**現在の適用状態や最新の利用側HEADを表す表ではない。**
旧配置の `modules/features/<category>/<name>/` を探す際は、各repoのこのcommitを参照する。

| repo | 対象 | 調査commit |
| --- | --- | --- |
| `.dotfiles` | attodesk / attolap | `b552a413f7ae6362da0720880fa0ec0bebac55a5` |
| `server-dotfiles` | attofort / attobox | `492d18d88ec56135be1d9d5e9e50bd9e04d6b258` |
| `dev-dotfiles` | development / devcon | `762ffd11dd150f591a6a0583348e96175398d45e` |
| `remote-dotfiles` | desktop | `12b4cc92408e641c17d9cb954c831ffcbc9e8e2e` |

詳細な旧調査表はこのファイルのGit履歴に残る。旧 `home/`・`nixos/` 配置、scope独立、HMなしサーバー、未実装だったサービスを、現在の作業指示として復活させない。
