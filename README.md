# attos-nix-modules

AttODaoの各dotfilesで共有するNixOS / Home Manager設定。

**現在は計画docsと雛形のみ。設定の抽出や `modules.*.enable` の実装はまだ行っていない。**

## docs

- [共有設定の設計・移行計画](docs/README.md)
- [モジュール別調査・ホスト差分・対象外一覧](docs/inventory.md)

## 今あるファイル

```text
flake.nix                公開するmoduleの入口
home/default.nix         HM用moduleを静的に読み込む
home/foot.nix            最初の実装場所の例（現在は空）
nixos/default.nix        NixOS用moduleを静的に読み込む（現在は空）
data/README.md           共通設定データの配置案
packages/README.md       custom package / overrideの配置案
docs/                    調査結果と移行計画
```

## 実装する場所

| 内容 | 配置先 |
| --- | --- |
| ユーザー側の設定 | `home/<name>.nix` |
| システム側の設定 | `nixos/<name>.nix` |
| 両方で使う設定値 | `data/<name>.nix` |
| 必要なpackage override / derivation | `packages/<name>.nix` |
| moduleに付随するscript / desktop entry等 | そのmoduleと同名のサブディレクトリ。例: `home/noctalia/` |

例えばFoot/Floorp/pcmanfmは`home/`、PipeWire/Fonts/Paseoは`nixos/`へ置く。
Zsh・Starship・Pi・SSH・Hyprland・Steam等は、必要な設定をNixOS用とHM用に分ける。
OpenCloudはclientを`opencloud-client`として扱い、serverとは混ぜない。

## 完成後の使い方

構成を組み立てるflakeで`nixosModules.default` / `homeModules.default`を一度だけ読み込み、
各ホストでは以下のように導入と差分を書く。

```nix
{
  modules.foot.enable = true;
  modules.foot.font = "Inconsolata Nerd Font Mono:size=13";
}
```

各moduleで型付きoptionを宣言し、実設定全体を`lib.mkIf config.modules.<name>.enable`で囲む。
enableは既定false。defaultを読み込んだだけでは導入しない。
HMとNixOSのoption範囲は別であり、このFootの例はHM側。

パッケージの列挙だけのfeature、host名、hardware、ユーザー権限、stateVersion、secretは共有しない。
まずは移行計画のPhase 1から実装し、現在のdotfilesのresolverを刷新する作業とは分ける。
