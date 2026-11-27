# What HyperMonitor shows for this kind and the attos-deck-agent may run (modules.service-catalog).
{ ... }:
{
  modules.service-catalog.kinds.jellyfin = _: {
    title = "Jellyfin";
    units = [
      "jellyfin.service"
    ];
    probe = "/health";
  };
}
