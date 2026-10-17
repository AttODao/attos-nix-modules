# scope内の同名attrでなく、利用ホストのbase packageを上書きする。
{ pkgs }:
pkgs.pandora-launcher.overrideAttrs (
  _finalAttrs: prevAttrs: {
    # Pandora's wrapper expects UTF-8 English output and fails under Japanese locale.
    makeWrapperArgs = prevAttrs.makeWrapperArgs ++ [
      "--set"
      "LC_ALL"
      "en_US.UTF-8"
      "--set"
      "LANG"
      "en_US.UTF-8"
    ];
  }
)
