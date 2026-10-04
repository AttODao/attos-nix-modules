# dotfiles共通設定の抽出計画

移行元`.dotfiles`から移した、共有作成専用の調査・計画文書。**現在はdocsと雛形のみで、設定本体はまだ抽出していない。**

- [モジュール別の調査結果・対象外一覧](./inventory.md)
- 作業リポジトリ: [AttODao/attos-nix-modules](https://forgejo.attodao.cc/AttODao/attos-nix-modules)
- 調査日: 2026-10-04

## 結論

共有リポジトリ名は**`attos-nix-modules`**。flakeとして公開し、構成を組み立てる箇所で`nixosModules.default`/`homeModules.default`を一度だけ読み込む。各ホストは**`modules.foot.enable = true;`で導入を選択**し、`modules.foot.font = ...;`のような短い型付きoptionで差分を書く。未指定のmoduleは無効とし、詳細設定にはNixOS/Home Manager標準optionも利用できる形にする。

共有するのは**設定の中身と、それに必要な資産・実装**。ホスト名、導入するソフトウェアの選択、ハードウェア、保存先、ユーザー権限、secretの配置は各dotfilesに残す。パッケージを列挙するだけのfeatureは対象外。

現在の`hosts`・`requires`・自動探索resolverを共有リポジトリへ移植しない。後の簡素化では、ホスト側を普通の`configuration.nix`・`home.nix`・パッケージリストにできる。NixOS/Home Manager自身のmodule機構は使い、**移行元dotfiles独自のfeature管理をなくす**、という区別になる。

## 1. 調査対象と確認できた範囲

| 記号 | リポジトリ | 調査したcommit | ホスト / Nix出力名 |
| --- | --- | --- | --- |
| L | 移行元`.dotfiles` | `b552a413f7ae6362da0720880fa0ec0bebac55a5` | `attodesk`, `attolap` |
| S | [server-dotfiles](https://forgejo.attodao.cc/AttODao/server-dotfiles) | `492d18d88ec56135be1d9d5e9e50bd9e04d6b258` | `attofort`, `attobox` |
| D | [dev-dotfiles](https://forgejo.attodao.cc/AttODao/dev-dotfiles) | `762ffd11dd150f591a6a0583348e96175398d45e` | 通称`devcon` / `nixosConfigurations.development`、ユーザー`dev` |
| R | [remote-dotfiles](https://forgejo.attodao.cc/AttODao/remote-dotfiles) | `12b4cc92408e641c17d9cb954c831ffcbc9e8e2e` | `desktop`、Incus内のヘッドレスデスクトップ |

S/D/RはForgejoの`main`を取得して比較した。手元の`/home/attodao/server-dotfiles`は`950b502`で古かったため、比較元には使っていない。Lは`ca9e133`から調査を開始し、調査中に追加された`b552a41`のforgejo-cliも確認した。この追加はpackage導入のみで、対象外一覧へ反映した。

調査対象は`flake.nix`、lock、`lib/features.nix`、全feature定義と設定本体、関連資産、NixOS core/hardware、home、hosts、SのIncusイメージ設定。暗号化secretの内容は共通化対象として扱わない。

全4リポジトリで、以下の**評価のみ**を実行できた。

```sh
nix eval --offline --no-write-lock-file --json .#featureMatrix
```

| repo | feature定義数 | パッケージのみ / 設定あり | 評価した有効feature数 |
| --- | ---: | ---: | --- |
| L | 58 | 27 / 31 | attodesk: 57、attolap: 45 |
| S | 39 | 9 / 30 | attofort: 30、attobox: 27 |
| D | 18 | 7 / 11 | development: 18 |
| R | 37 | 16 / 21 | desktop: 37 |

これはresolverの選択結果の確認であり、全NixOS/HM設定の評価・build・実機動作確認ではない。全ホストへのSSH接続、rebuild、サービス再起動は行っていない。

## 2. 共有リポジトリの最小構成

最初は、共有できる設定だけを明示的にexportする。`default`はそれらのoption定義をまとめて読み込む入口とし、ソフトウェアの有効化は各`modules.<name>.enable`に任せる。以下は実装が進んだ後の配置案。現在の雛形はrootの[README](../README.md)を参照。

```text
attos-nix-modules/
  flake.nix
  nixos/
    default.nix          # NixOS用moduleの静的なimports
    nix.nix
    openssh.nix
    pipewire.nix
    fonts.nix
  home/
    default.nix          # HM用moduleの静的なimports
    zsh.nix
    starship.nix
    foot.nix
    floorp.nix
  data/                  # NixOS/HMの両方で使うStarship/Pi設定など
  packages/              # Pi/context-mode等の実際に必要なoverrideだけ
```

これは完成形の必須ディレクトリ一覧ではない。移動する設定に合わせて増やす。`packages/`は、普通の`pkgs.git`等を再exportする場所にはしない。

公開APIの例:

```nix
{
  outputs = { ... }: {
    nixosModules = {
      default = ./nixos/default.nix;
      nix = ./nixos/nix.nix;
      openssh = ./nixos/openssh.nix;
      pipewire = ./nixos/pipewire.nix;
      fonts = ./nixos/fonts.nix;
    };
    homeModules = {
      default = ./home/default.nix;
      zsh = ./home/zsh.nix;
      starship = ./home/starship.nix;
      foot = ./home/foot.nix;
      floorp = ./home/floorp.nix;
    };
  };
}
```

設定moduleは、原則として**利用するホストの`pkgs`・`lib`・`config`**を使う。このようなmoduleのexportだけなら、共有flake自身にnixpkgs/Home Manager inputを置く必要はない。

- NixOS設定とHM設定は別export。同じ名前でも別のmodule評価系である。
- 各共有moduleは`modules.<name>.enable = lib.mkEnableOption ...`（既定false）を宣言し、実設定を`lib.mkIf config.modules.<name>.enable`で囲む。importだけでは導入しない。`default`は静的な`imports`一覧であり、独自のfeature resolverではない。
- Starship/Piの設定値は一箇所へ置き、HM用とNixOS用の薄いmoduleから利用する。Sに共有のためだけにHome Managerを導入しない。
- assetはそれを使うmoduleと一緒に移す。`.desktop`、cursor derivation、必要なshell scriptの参照を置き去りにしない。
- `../../../secrets`や`../../../nixos/core/public-hosts.nix`のような、元dotfilesの配置を前提とする参照は共有先へ持ち込まない。
- palettes等の外部資産が必要なら、共有flake内でその依存だけを閉じるか、明示的な設定として受け取る。ホストの`inputs`全体を必須の公開APIにしない。
- `default`から読み込むmoduleは明示的に列挙する。`config.modules.*.enable`から`imports`を組み立てる方式は循環評価の原因になるので使わない。新しいresolver/依存グラフ/ホスト台帳は作らない。

利用側では、例えばroot flakeに次を追加する。`shared`はこの文書内で使うinputの短縮名であり、リポジトリ名とは別である。

```nix
inputs.shared.url =
  "git+https://forgejo.attodao.cc/AttODao/attos-nix-modules.git";
```

S/Dではrootのinputsを、L/Rでは現在の`deps.inputs`との違いを意識して受け取る。上の例は**rootに`shared`を追加する案**であり、既存の`inputs = deps.inputs`へ自動的に含まれるわけではない。root outputsでも`shared`を受け取り、使う場所へ渡す。

## 3. ホスト固有設定の記述方法

### 基本: `modules.<name>.enable`で導入し、短いoptionで差分を書く

Nix標準の`mkEnableOption`・`mkOption`・`mkIf`だけで実現できる。独自の設定parserやresolverは不要。Footのfontには、サイズ指定まで含む文字列を受け取る。

```nix
# 共有側: home/foot.nix
{ config, lib, ... }: {
  options.modules.foot = {
    enable = lib.mkEnableOption "shared Foot configuration";
    font = lib.mkOption {
      type = lib.types.str;
      default = "Inconsolata Nerd Font Mono:size=11";
      description = "Foot font specification, including its size.";
    };
  };

  config = lib.mkIf config.modules.foot.enable {
    programs.foot = {
      enable = true;
      server.enable = true;
      settings.main.font = lib.mkDefault config.modules.foot.font;
      settings.colors-dark.alpha = lib.mkDefault 0.65;
    };
  };
}
```

共有側の`home/default.nix`では、optionを宣言するmoduleを静的に読み込む。これだけではソフトウェアは有効化されない。

```nix
# 共有側: home/default.nix
{
  imports = [ ./zsh.nix ./starship.nix ./foot.nix ./floorp.nix ];
}
```

flakeでHM構成を組み立てる箇所の`modules`リストに、`shared.homeModules.default`とローカルの`home.nix`を一度だけ追加する。NixOSにHMを組み込む場合も、そのユーザーのHM側moduleリストへ追加する。`shared.nixosModules.default`は別途NixOS側moduleリストへ追加する。

ホスト側は個別の`imports`や`shared`引数を持たずに書ける。以下は将来の簡素化後の例で、今回設定本体を変更するものではない。

```nix
# ホスト側: home.nix
{
  modules.zsh.enable = true;
  modules.starship.enable = true;
  modules.floorp.enable = true;
  modules.foot.enable = true;
  modules.foot.font = "Inconsolata Nerd Font Mono:size=13";
}
```

`enable`未指定はfalse。font等の差分optionを省略すれば共通の既定値を使い、fontを指定しただけでは導入しない。型違いや未定義optionはNixの評価時に検出する。`modules.foot`全体を型なしの自由なattrsetにして、typoを黙って無視する方式にはしない。

`modules.foot.enable = false;`はこの共有moduleによる設定を止める指定であり、別のmoduleが直接`programs.foot.enable = true;`と書いた場合まで強制的に禁止するものではない。

`programs.foot.settings.main.font = ...;`も詳細設定の逃げ道として残す。この例は実設定への代入が`mkDefault`なので、短いoptionと標準optionの両方を指定した場合は**標準optionの通常代入を優先する**。同じfontを二つの場所に書くことは推奨しない。

### NixOSとHome Managerの設定範囲

このFootの例の`modules.foot.font`は**Home Manager側**のoptionである。NixOS側の`modules.*`とHM側の`modules.*`は、同じ綴りでも別の設定範囲なので、自動的に値が渡るわけではない。

- `home.nix`では上の形で直接書ける。NixOSのHM連携設定からなら`home-manager.users.attodao.modules.foot.font = ...;`になる。
- NixOSのトップレベルでも`modules.foot.font = ...;`と統一したい場合は、対象HMユーザーへ転送する薄いNixOS adapterを追加する。転送先ユーザーを明示し、全ユーザーへ適用しない。
- standalone HMでも使えるよう、HM module自身にはNixOS側の`osConfig`を必須にしない。

最初はHM設定は`home.nix`、system設定は`configuration.nix`で`modules.<name>.enable`と短いoptionを使う。トップレベルを一つに統一するadapterは、その運用を採用するときに追加し、設定値だけでなくenableも転送する。

### 標準optionによる詳細設定・上書き

**import順で「後勝ち」にはならない。** 異なる同優先度のscalarは衝突し、通常のlist定義は結合される。

| 用途 | 書き方 |
| --- | --- |
| 共通のscalarをホストが変更できるようにする | 共有側`lib.mkDefault`、ホスト側通常代入 |
| listに追加する | 通常のlist定義。必要なら`lib.mkBefore` / `lib.mkAfter` |
| 共通listを丸ごと既定値とし、ホストのlistに置き換える | 共有側でlist全体を`lib.mkDefault`にする |
| 既存の強い定義を意図的に置換する | ホスト側`lib.mkForce`。常用しない |
| モニター、lid、保存先、firewall、secret | ホスト固有ファイルに普通のNixOS/HM optionを書く |

Hyprlandのmonitor listを通常優先度で共有側・ホスト側の両方に置くと、default monitorが余分に結合される。SSH許可ユーザーやfirewallも、list結合による意図しない許可拡大を検証する。`mkDefault`は全値へ機械的に付けず、**上書きを認める設定だけ**に使う。

### 短いoptionを公開する範囲

Footのfont、モニター、保存先、Paseoの実行ユーザー/hostname、Piの供給元等、実際にホスト差がある値に短い型付きoptionを用意する。標準option全体を`modules.*`へ複製しない。共有module内部では`xdg.userDirs`、`config.home.homeDirectory`、`systemd.services.*`等の標準設定へ接続し、一つの値を複数箇所へ手動で書かせない。

- pcmanfm: 共有側はhome配下を既定値にし、attodeskの`/mnt/hdd1`指定をローカルの`xdg.userDirs`へ移す。
- Noctalia: dockの追加、録画codec/source、headlessのservice依存をローカルへ。保存先は`xdg.userDirs`から導く。
- Paseo: 生成JSON内部とunitの複数箇所で使うユーザー等だけ、少数の型付きoptionにする候補。`hostName == "attofort"`等の分岐は不要。
- login-pin: 既存`attodao.loginPin` optionを使う。secret名/参照先の固定と実行ユーザーの対応を切り離す。

秘密情報は各ホストのSOPS定義に残し、共有側には必要に応じて**復号後のruntime path**を渡す。パス文字列は扱っても、`builtins.readFile`で復号済み秘密をNix storeへ入れない。Age鍵・暗号化secret・stateVersionは共有リポジトリへ移さない。

## 4. 互換性と更新遅れの扱い

同じ`nixos-unstable`指定でもlockは異なる。

| repo | nixpkgs lock | Home Manager / 特殊依存 |
| --- | --- | --- |
| L | `c59305b…` | HM `acd21c5…`。Noctaliaはnative moduleを利用 |
| S | `c59305b…` | HMなし。`pi-nixpkgs`も`c59305b…` |
| D | `e2587ca…` | HM `a1645f4…`。Pi供給元だけ`20b1ddd…` |
| R | `8ce4ef6…` | HM `cd1c9e5…`。Noctalia flake `9f35ead…`、OpenCloud供給元だけ`20b1ddd…` |

抽出とパッケージ更新を同じ変更にしない。とくにDもLより古いlockを使っているので、Rだけを互換性問題の対象にしない。

- RのNoctalia外部HM module importは、最初はローカルadapterに残す。共有設定は共通の設定本体に限定し、Lのnative moduleと旧外部moduleを同時importしない。
- Pi/context-modeのoverrideは同一だが、元packageの供給元とpi-sessions revisionは違う。全体をL版へ揃えるとSのpi-sessionsを巻き戻すことになる。
- Rのheadless Hyprland、seatd、linger、Sunshine sink、GPU/uinputの権限は更新遅れではなく用途固有。
- RのDiscord Wayland指定・KillMode、OpenDeckの固定AppImageは、古いから削除してよいとは判断できない。
- Fcitxの実ファイル化等の後発修正は共有候補だが、「抽出」と「Rへ修正を適用」を別の変更にする。

共有flakeに検証用等のnixpkgs/HM inputを追加した場合、同じpackage setを使いたいconsumerは`follows`を指定できる。S/Dの参照先は`nixpkgs`、L/Rの現構成では`deps/nixpkgs`。**共有flakeがこれらのinputを持たない段階では`follows`も不要。** 既存lockを一斉更新する代わりにはならない。

## 5. 移行手順

### Phase 0: 差分を固定し、移行前の結果を保存する

1. この文書のcommitを基準にする。実装着手時に各repoのHEADを再確認する。
2. [inventory](./inventory.md)の「共有内容」と「残す差分」を移動単位にする。
3. 6ホストのNixOSと4系統のHM実設定（および互換alias）を評価し、関連option、生成設定、service unit、パッケージ供給元を記録する。
4. 共有repoと公開exportの雛形は作成済み。実装対象を追加する際も、既存dotfilesの`lib/features.nix`は変更しない。

完了条件: 移行前に失敗する評価があれば、抽出による失敗と区別できる。意図不明な差分を勝手に統一しない。

### Phase 1: そのまま共有できる部分から移す

- Starshipの`settings`、ZshのHM設定。
- Foot、Fonts、Floorp、OBS Studioの設定本体。
- Piの`package.nix`・`context-mode.nix`、一致する設定値。供給元・pi-sessions・配置方式は既存adapterに残す。
- localeの共通設定。Dへ新規に導入するかは別判断。

flakeのNixOS/HM側moduleリストへそれぞれ共有の`default`を追加する。既存featureの`hosts`・`requires`とmodule参照は維持し、移行した参照先の`home.nix`/`nixos.nix`を`modules.<name>.enable = true;`と固有設定だけの数行adapterへ置き換える。この方法なら**`lib/features.nix`を変更せずに移行できる**。後の簡素化時にenable宣言をホスト側へ移し、adapterとfeature wrapperをまとめて削除する。共有側の全moduleが未指定なら無効なので、移行していないソフトウェアや他hostへ導入が広がらないことを確認する。

完了条件: 元のホスト選択と設定内容を維持し、別repoに同じ設定本文を残さない。

### Phase 2: 小さな意味的差分のある設定を分離する

- SSH client / OpenSSH serverを分ける。alias、Git向け`IdentitiesOnly`、鍵指定、認証・firewallを保持する。
- Nix共通設定、nix-ld、OpenCloud client、Thunderbird、Steam。
- pcmanfmの保存先、desktop-themeの環境変数差、Discordのpackage/service差。
- Paseoのユーザー/hostname/依存package差。

完了条件: host差分が各dotfilesへ明示され、通常のNix optionで上書きできる。共通化のためだけの認証変更・新しいport開放・package更新がない。

### Phase 3: デスクトップの起動経路と関連設定を移す

1. Hyprlandの表示・keybind設定と、モニター/電源/lid/startupを分ける。
2. Noctaliaの見た目・bar・calendar設定と、起動方式/録画/HDR処理/dock差を分ける。
3. SKKの共通設定と、後発の永続化・service修正を分ける。
4. OpenDeckの設定とpackage供給方式を分ける。最初は固定AppImageと更新式AppImageを両方保持する。
5. 同repo内だけで共有されているB候補は、別repoへ移す価値があるものだけ追加する。

完了条件: desktopのheadless出力が作られた後にNoctalia/Sunshineが起動し、実機ではgreeter・通常ログイン・画面ロック・lid動作を維持する。

### Phase 4: 共通設定の変更を配布する運用を確立する

1. 共有repoを変更・検証し、commitを固定する。
2. 各dotfilesで`shared` inputだけを更新する。
3. **4 repoで同じ共有revisionを採用したか確認する。** 1 repoの更新で、そのrepoが管理する2ホストをそれぞれ適用する必要もある。
4. 全consumerを評価・buildし、変更対象ソフトウェアの動作を確認する。
5. 非本番側で確認後、attofort/attoboxへ一台ずつ適用する。SSHの既存接続を残し、新規接続の成功を確認する。

```sh
# sharedをroot inputとして追加する案の場合。各dotfilesで実行する。
nix flake update shared
# lockのshared revisionと、無関係なinputが変わっていないか確認する。
```

**共有repoへpushしただけでは全ホストへ反映されない。** 各flake.lockの更新と各ホストのrebuild/HM activationが必要。`fetchTarball`で常に最新を読む方式や、自動switchの仕組みは初回作業に入れない。更新漏れが問題になった時に、4 repoへ同じrevisionのlock更新PRを出す小さなCI処理を追加する。

なお、現状のOpenDeck更新script、Paseoの`npx @latest`、Dockerの`:latest`にはlock以外で変わる部分がある。今回その運用を変えず、同じlockならそれらまで同じversionになるとは保証しない。

### Phase 5: 各dotfilesの独自feature管理をなくす（今回の後）

- hostごとの`configuration.nix`・`home.nix`には`modules.<name>.enable`と固有optionを書く。共有`default`の読み込みはflakeの構成組み立て箇所に一度だけ置く。
- packageのみのfeatureは`environment.systemPackages` / `home.packages`へ直接まとめる。
- 共通の`requires`が担っていたpackage/serviceは、共有moduleのenable内で必要なpackageを追加するか、前提となる別moduleのenableとassertionに置き換える。NixOS/HMをまたぐ依存はそれぞれのenableを確認する。外部moduleのoption定義を提供するための`imports`は静的に扱い、enableによって動的に読み込まない。
- 全featureと両module系の移行を確認してから`lib/features.nix`、feature wrapper、`featureMatrix`を削除する。
- host、ユーザー、stateVersion、secrets、生成済みhardware設定はローカルに残す。

抽出と簡素化を同時に実施しない。共有exportが固まった後なら、ホスト側は「選ぶ・上書きする・packageを並べる」だけになる。

## 6. 検証とロールバック

### 評価・buildの対象

| repo | NixOS | HM |
| --- | --- | --- |
| L | `attodesk`, `attolap` | `attodao-attodesk`, `attodao-attolap`（`attodao`は互換alias） |
| S | `attofort`, `attobox` | なし。必要ならbootstrap imageの`incus-development`, `incus-desktop`も回帰確認 |
| D | `development` | `dev` |
| R | `desktop` | `attodao` |

各repoで、該当する全出力を明示的に確認する。S/DにもL/Rと同じ`checks`があるとは仮定しない。

```sh
# HOSTとUSER_OUTPUTを上表から置き換えて実行する。
nix eval --no-write-lock-file --raw \
  .#nixosConfigurations.HOST.config.system.build.toplevel.drvPath
nix build --no-write-lock-file --no-link \
  .#nixosConfigurations.HOST.config.system.build.toplevel
nix build --no-write-lock-file --no-link \
  .#homeConfigurations.USER_OUTPUT.activationPackage
```

- 移行中は`featureMatrix`が変わらないこと、対象外packageが落ちないことを確認。
- 共有`default`を読み込んだだけではpackage/service/activationが追加されないことを確認。Foot等のenable未指定・false・true、fontだけの指定、型違い、標準optionによる上書きを評価する。外部providerのoption定義やimport互換性は、enable=falseだけで解決できるとは仮定しない。
- NixOSに組み込んだHMとstandalone HMの両方を確認。Noctaliaの`osConfig ? null`時にsecretやNixOS専用optionを無条件参照しない。
- Starship設定、Floorp policy、SSH生成設定、Paseo JSON、Noctalia設定とsystemd依存を移行前後で比較。store pathの変化と挙動の変化は区別。
- SSHは`ssh -G`でalias/User/Port/IdentityFile/IdentitiesOnly/ControlPathを比較し、実接続も確認。
- Fcitxは再起動・GUI設定保存、OpenCloud/Discordは二重起動の有無、Hyprland/Noctalia/Sunshineはログインとstreamingを確認。
- PiはCLIとPaseoの両方から同じ意図したversion・tools・拡張が使えること、可変settingsを消さないことを確認。Sの既存`tests/check-pi-settings.sh`は新規/既存/不正JSONの保護を検証しており、移動後も維持する。
- boot/login-pinは実機で確認し、通常パスワードfallback、secretのowner/mode、PAM順序を保持。特にserver/remoteへPINや`mitigations=off`を配布しない。
- 新規import対象はGitへ追加してからflakeを評価する。暗号化secretと秘密鍵を誤ってstageしない。

失敗時は共有input更新commitを戻し、前のlockで再buildする。すでに適用したホストは既存のNixOS/Home Manager generationへ戻す。既存データ、Paseo/Piの可変設定、サービス保存先を削除・移動しないことを、各移行の前提条件にする。
