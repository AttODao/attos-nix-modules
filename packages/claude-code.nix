{ callPackage }:
# sadjow/claude-code-nixのpackage.nixをrevision固定で使う。eval時取得のためIFDにしない。
callPackage "${
  builtins.fetchTarball {
    url = "https://github.com/sadjow/claude-code-nix/archive/69ea6acabd545898cd2764a12c293ead05fd7e84.tar.gz";
    sha256 = "sha256-h0ocvti7xZNzf6bhS1bvwr7L0fLTicWfvO11Xn1zR3s=";
  }
}/package.nix" { }
