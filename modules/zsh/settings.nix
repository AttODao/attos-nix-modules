{ lib, pkgs }:
# Upstream gruvbox-rainbow preset with the local NixOS symbol, language symbols and Conda segment.
lib.recursiveUpdate (lib.importTOML "${pkgs.starship}/share/starship/presets/gruvbox-rainbow.toml")
  {
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
