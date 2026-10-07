# 残作業台帳

このファイルは未完了の作業だけを管理する。完了した項目は削除し、作業履歴・成功ログ・過去の調査commitはGit履歴/PR等へ残す。
現在のAPIは[README](../README.md)・[Wiki](https://forgejo.attodao.cc/AttODao/attos-nix-modules/wiki)・採用revisionの実装、移行手順は[利用側dotfilesの移行](migration.md)を参照する。
共有実装、利用側コード移行、build、実機適用は別の完了条件。以下は実機の最新状態を保証する台帳ではなく、着手時に現地checkout・稼働構成と照合する。

## 優先する残作業

| 優先度 | 対象 | 残る作業・完了条件 |
| --- | --- | --- |
| P0 | 次に移行する利用側repo | repo/branch/HEAD/lockと稼働構成を確認し、対象OS・guest・HM・image出力、許可範囲を確定。昔の調査checkoutを現在の構成と思い込まない |
| P1 | `server-dotfiles` / attofort・attoboxと対象guest | 旧設定の置換表を作り、共有入口・公開APIへ移行。全出力のソフト・生成設定・起動経路を比較して評価。実hostnameで所有OSを指定し、非所有OSに実体を作らない |
| P1 | 上記サービスのstate・秘密・接続 | mount/volume・UID/GID・両stateVersion・復号順序・Swarm role/network・DNS/gateway・mail/TLS/DKIM・VPN・Incus・HM/Paseoを照合。既存データ/guest/cluster/鍵とSSH復旧経路を保持 |
| P1 | 移行対象の全ホスト・guest | NixOS/HM・必要なpackage/imageをbuild。既存guestへの適用はimage生成/初回bootstrapと分けて手順を確認 |
| P1 | `.dotfiles` / attodesk・attolap | 両ホストの全体build、許可後の段階適用とboot/PIN/GUI/user service・HDR録画・音声/機器・rollbackを確認 |
| P1 | 各利用側の実機適用 | backupと復旧経路を確認し、明示許可後に一台ずつ適用。起動・認証・サービス・外部到達性・データとrollbackを検証し、未適用を完了扱いにしない |
| P2 | 各利用側の旧実装 | 全出力の参照置換と同等性確認後にresolver・featureMatrix・wrapper・二重HM経路を削除。ホスト固有設定・未移行機能は残す |

## 対象を決めてから進める作業

- `dev-dotfiles` / development（devcon）、`remote-dotfiles` / desktopの現行checkoutと、利用側guest構成との対応を確認する。別repoの統合が依頼範囲に入るかを先に判断し、サーバー移行へ無断で追加しない。
- 対象に含める場合、開発用のPi/Paseo・SSH・code-server・SDK/JDK・project資産・USB/sandbox、remote desktopのheadless/seatd/linger・Sunshine・仮想音声・認証/firewall・GUI起動・Zed/専用package setを保持して比較する。
- 旧Piのwritable settings merge、SSH clientのalias/鍵/policy、Fcitx5のlayout、DiscordのWayland/終了設定、OpenCloud clientのpackage/autostart、Thunderbirdの固定account等に差分がある対象は、必要な上書きと既存stateの扱いを判断する。設定例を全ユーザーへ機械的に配らない。

## 任意の別作業（移行の前提にしない）

- `nix-ld` / `obs-studio` の共有化は必要性が確認された場合だけ検討する。既存の標準option設定を維持すれば移行できる。
- package-only featureは標準package optionへ整理できるが、library/toolchain・暗黙依存は保持する。共有enableを作ること自体を目的にしない。
- floating image/tagや実行時latest取得の固定化、nixpkgs/HM更新、保存先/データ構造の変更は別の承認・検証を伴う作業とする。

## 台帳の更新ルール

- 着手時に対象repo/共有revision・対象構成・次の作業・停止条件を利用側の作業メモ/PR等へ記録する。
- コード比較・評価を終えたらその項目を削除し、未実施のbuild・適用・実機確認だけを残す。複数対象の一部完了なら行を分ける。
- 比較できない構成、未承認の契約変更、未供給の秘密・権限・guest更新手順は具体的なblockerとして残す。
- 完了したAPI追加・公開・過去のテスト件数・一時checkoutの探索記録を再び追記しない。現在の設計/契約はREADME・Wiki・実装へ記載する。
