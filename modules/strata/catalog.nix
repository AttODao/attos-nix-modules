# What HyperMonitor shows for this kind and the attos-deck-agent may run (modules.service-catalog).
{ lib, ... }:
{
  # One headless unit per model (nixos.nix); starting picks the model, at most one runs.
  modules.service-catalog.kinds.strata =
    { cfg, ... }:
    let
      name = model: "strata-headless-${lib.toLower (lib.replaceStrings [ "_" "." ] [ "-" "-" ] model)}";
    in
    {
      title = "Strata";
      ops = [
        "start"
        "stop"
        "restart"
      ];
      probe = "/health";
      variants = map (model: {
        id = lib.toLower model;
        label = lib.toLower model;
        unit = "${name model}.service";
      }) cfg.models;
    };
}
