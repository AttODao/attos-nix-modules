# Noctalia

`nixosModules.default`を読み込み、NixOS側で`modules.noctalia.enable = true;`を指定する。
共有側で固定したHome Managerのnativeな`programs.noctalia` moduleを使用し、全HMユーザーへ設定する。
独自optionは次の5項目のみ。

| Option (`modules.noctalia.`) | 既定値 | 内容 |
| --- | --- | --- |
| `enable` | `false` | 共有設定を有効化 |
| `dock.pinned` | `[]` | desktop entry IDのリスト。指定したリストで置換 |
| `screenRecorder.enable` | `false` | 録画plugin・widget・gpu-screen-recorder・保存先の作成を一括有効化 |
| `calendar.account` | `{}` | IDをキーにしたNoctaliaのaccount設定 |
| `location` | `{}` | Noctaliaのlocation設定 |

```nix
{
  modules.noctalia = {
    enable = true;
    dock.pinned = [ "footclient" "floorp" ];
    screenRecorder.enable = true;
    calendar.account.sogo = {
      type = "caldav";
      name = "My Calendar";
      provider = "custom";
      server_url = "https://calendar.example.com/";
      username = "user@example.com";
      calendars = [ ];
      credential_source = "file";
      password_file = "/run/secrets/calendar-password";
    };
    location.address = "Toyoake, Japan";
  };
}
```

account・locationの内部フィールドはupstreamのTOML形式に従う。
secretの作成・権限はconsumer側の責任。平文パスワードを書かず、
復号済みファイルへのruntime pathを渡す（共有moduleでは読み込まない）。
個人のaccount・所在地やホスト名は共有側で固定しない。

bar・dockの見た目、Everforest、時刻・日付形式、weather、nightlightは移行元の設定を維持。
録画先は`xdg.userDirs.videos + "/Recordings"`、方式はportal / h264。
HDR変換wrapper・codec/sourceのホスト差・NixOS側のGPU権限設定は移さない。
起動はconsumerに任せ、systemd serviceは自動有効化しない。
pinned appの導入もconsumer側で行う。独自optionにない差分は`home-manager.users.<name>`の標準HM optionで指定する。

Everforestは`modules/noctalia/Everforest.json`に同梱。
出典: [noctalia-dev/community-palettes](https://github.com/noctalia-dev/community-palettes/blob/0132bda247fb305e6d4829917563f4505a64a9a0/Everforest/Everforest.json)
（移行元のlockと同じrevision）。palette専用のflake inputは不要。

```sh
nix-instantiate --eval --strict tests/noctalia.nix \
  --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
```

未指定・false時の副作用、5項目のAPI・型、dock置換、account・location転送、
録画の有効/無効、保存先追従、palette、NixOS組み込みHM評価を確認する。
consumerの.dotfilesには未適用。
