{ lib }:
# Upstream gruvbox-rainbow preset with the local NixOS symbol, language symbols and Conda segment.
# gruvbox-rainbow.toml is a copy of share/starship/presets/gruvbox-rainbow.toml from starship 1.26.0
# (/nix/store/dncwf5jhs0w08y7kxv5k5msmnscsa557-starship-1.26.0); reading the package at
# evaluation time would be import-from-derivation.
lib.recursiveUpdate (lib.importTOML ./gruvbox-rainbow.toml) {
  os.symbols.NixOS = "󱄅";
  c.symbol = "";
  cpp = {
    disabled = false;
    symbol = "";
  };
  haskell.symbol = "";
  pixi.symbol = "󰏗";
  conda = {
    symbol = "";
    format = "[[ $symbol $environment ](fg:color_fg0 bg:color_bg3)]($style)";
  };
}
