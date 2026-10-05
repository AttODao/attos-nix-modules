{ pandora-launcher }:
pandora-launcher.overrideAttrs (_finalAttrs: prevAttrs: {
  # Pandora's wrapper expects UTF-8 English output and fails under Japanese locale.
  makeWrapperArgs = prevAttrs.makeWrapperArgs ++ [
    "--set" "LC_ALL" "en_US.UTF-8"
    "--set" "LANG" "en_US.UTF-8"
  ];
})
