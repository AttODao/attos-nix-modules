# Package実装

共有設定に必要なcustom derivation / overrideだけを置く。現在は未実装。

予定する例:
- `pi.nix`: Piのversion override。
- `context-mode.nix`: Pi adapter / HTML dependenciesを含むoverride。
- `yanfei-cursors.nix`: XcursorからHyprcursorを生成するderivation。

原則として利用ホストのpkgsでcallPackageする。
Pi等のbase package供給元が違う場合は、移行時に現在の供給元を保持する。
単なるpkgs.git等の再exportや、ホストのpackage一覧は作らない。
