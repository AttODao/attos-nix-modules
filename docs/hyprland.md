# Hyprland / greeter

NixOS側の `modules.hyprland.enable` で、Hyprland / UWSMと全HMユーザーのLua設定を有効化する。
Noctalia・Fcitx5・Foot・PCManFM・userDirsも依存として自動有効化する。
greeterを有効にするとHyprlandも有効になるが、Hyprlandだけならgreeterは導入しない。

## 独自option

| Option | 既定値 |
| --- | --- |
| `modules.hyprland.enable` | false |
| `modules.hyprland.monitors` | preferred / auto / scale 1の可搬用出力 |
| `modules.hyprland.neowall.enable` | false |
| `modules.hyprland.lidSwitch.enable` | false |
| `modules.greeter.enable` | false |
| `modules.greeter.output` | null |
| `modules.greeter.cursor` | greeter有効時必須 |

モニターの各要素はoutput、mode、position、scale、bitdepth、cm。
scaleは正数、bitdepthは8 / 10 / null。nullの項目はLuaに出力しない。
指定したモニターリストは既定リストを置換する。

```nix
{
  modules.home-manager.users = [ "attodao" ];
  modules.hyprland = {
    enable = true;
    neowall.enable = true;
    lidSwitch.enable = true;
    monitors = [
      { output = "eDP-1"; mode = "preferred"; position = "0x0"; scale = 1; }
    ];
  };
}
```

lidSwitchを有効にすると、NixOS側のlogind蓋イベント無視と、
HM側のNoctaliaによるmonitors on/off操作をまとめて適用する。
neowallはpackage・固定shader設定・起動hookを追加する。

## greeter / cursor

greeterの既定ログインユーザーはattodao、セッションはHyprland (uwsm-managed)。
ユーザー・権限・secretは利用側で作成する。

```nix
{ pkgs, ... }:
{
  modules.greeter = {
    enable = true;
    output = "DP-1";
    cursor = pkgs.fetchurl {
      name = "custom-cursors.zip";
      url = "https://example.invalid/cursor.zip";
      hash = "sha256-...";
    };
  };
}
```

実際のcursor URL・hashはconsumer側に置く。
アーカイブはルートにcursors/がある構造を想定し、XcursorからHyprcursorを生成する。
package・テーマ・メタデータはcustom-cursors / Custom-Cursorsへ統一する。
共有側がattopkgsを自動供給するため、specialArgsの手動設定は不要。

スクリーンショット先は各ユーザーの `xdg.userDirs.pictures` のScreenshots。
カーソルのユーザー側導入・機器固有の表示設定は利用側に残す。
HMの標準設定差分は `home-manager.users.<name>.wayland.windowManager.hyprland` へ書く。

```sh
nix-instantiate --eval --strict tests/hyprland.nix \
  --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
```

ログイン、蓋イベント、画面ロック、描画の実機確認はconsumer移行後に行う。
