# 共通設定データ

NixOSとHome Managerの両方で使う設定値を置く。現在は未実装。

予定する例:
- `starship.nix`: palette、format、表示設定。
- `pi-settings.nix`: defaultTools、context-mode登録、autoTitle等。
- `ssh-hosts.nix`: 接続先の共通データ。serverのインフラ台帳全体は移さない。

ここは設定値の置き場であり、moduleのenable宣言やhost選択を管理しない。
認証情報や復号済みsecretは置かない。
