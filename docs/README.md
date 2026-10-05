# 共有設定の設計・移行方針

現在のAPIと機能一覧は[root README](../README.md)、module別の設定リファレンスは[Wiki](https://forgejo.attodao.cc/AttODao/attos-nix-modules/wiki)を参照。
[調査台帳](inventory.md)は旧構成の調査記録であり、現在のmodule配置・依存方針とは異なる。
公開namespace・remote登録・サーバーstateの境界は[サーバーサービス](server-services.md)を参照。

## 構成

全ホストでNixOS組み込みHome Managerを使用する。
共有flakeの `nixosModules.default` を一度importし、利用側は
`modules.home-manager.users = [ "attodao" ];` と機能のenableを指定する。

HMのrevision固定、HM読み込み、共通設定、package引数は共有側の責務。
機能のenableはNixOS側に集約し、有効なHM設定を全HMユーザーへ適用する。
standalone HMや独立したhome exportは提供しない。

各機能は `modules/<name>/` に置く。

- `default.nix`: 公開option、他moduleの依存、有効化と両scopeへの接続。
- `home.nix`: HM実設定。必要な場合のみ。
- `nixos.nix`: NixOS実設定。必要な場合のみ。
- 付随する資産は同じディレクトリに置く。

importは静的に宣言する。依存はenableで表現し、独自resolver・ホスト台帳は作らない。
ユーザー固有の差分は標準 `home-manager.users.<name>` に書く。

## ホストに残す責務

ユーザー作成、ログインシェル、権限・linger、hardware、保存先、secrets、
stateVersion、unfree許可、機器固有設定は利用側に残す。
共有moduleはログインユーザーを作成しない。daemon用system userはサービスの標準module等で管理する。

既存のHM stateVersionは保持する。共有既定値26.05を移行済みホストへ無条件に採用しない。
秘密の内容をNix storeへ読まず、必要な設定には復号後のruntime pathを渡す。
全ユーザーへ固定メールアカウントなども適用される点を移行時に確認する。

## 移行手順

1. 利用側の既存NixOS / HM設定、stateVersion、package供給元を記録する。
2. このflakeをinputとして追加し、`nixosModules.default` をimportする。
3. 利用側のHM module importと共通引数設定を削除し、`modules.home-manager.users` に対象ユーザーを指定する。
4. 各機能の旧設定本文と両scopeのenableを、NixOS側の一つのenableへ置き換える。
5. HM固有の差分だけを標準 `home-manager.users.<name>` に残す。
6. NixOS全体と全HMユーザーのactivationを評価・buildし、生成設定を比較する。
7. 既存feature resolverの全参照を置き換えてから、resolver・feature wrapper・featureMatrixを削除する。

共有抽出・ホスト移行・nixpkgs更新を一つの変更に混ぜない。
今回の実装は共有repoだけで、consumerのdotfilesや実機は変更しない。

## 更新・検証・ロールバック

HMのrevision更新はこのrepoのinputとlockを更新して検証する。
各dotfilesでは共有inputのlock更新と各ホストのrebuildが必要。
共有repoへのpushだけで全ホストへ反映されるわけではない。

評価テストは `tests/*.nix`。PIN照合・PipeASIO登録に加え、サーバーruntimeの
scriptテストは各機能ディレクトリにあり、[一覧](server-services.md#検証)から実行できる。
NixOSのboot・PAM・user service・desktop起動はconsumer移行後に実機確認する。
失敗時は共有input更新を戻し、前のlock / NixOS generationへ戻す。

## 調査対象と確認できた範囲

旧調査の比較元（2026-10-04）:

| repo | 対象 | 調査commit |
| --- | --- | --- |
| .dotfiles | attodesk / attolap | b552a413f7ae6362da0720880fa0ec0bebac55a5 |
| server-dotfiles | attofort / attobox | 492d18d88ec56135be1d9d5e9e50bd9e04d6b258 |
| dev-dotfiles | development / devcon | 762ffd11dd150f591a6a0583348e96175398d45e |
| remote-dotfiles | desktop | 12b4cc92408e641c17d9cb954c831ffcbc9e8e2e |

この比較元を記録した[調査台帳](inventory.md)には、当時のHMなしサーバーや
両scope独立の方針が残る。それらは現在の設計ではなく、移行時の差分確認用の記録。
