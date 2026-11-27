# What HyperMonitor shows for this kind and the attos-deck-agent may run (modules.service-catalog).
{ ... }:
{
  modules.service-catalog.kinds.immich = _: {
    title = "Immich";
    units = [
      "immich-server.service"
      "immich-machine-learning.service"
    ];
  };
}
