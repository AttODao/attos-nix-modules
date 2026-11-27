# What HyperMonitor shows for this kind and the attos-deck-agent may run (modules.service-catalog).
{ ... }:
{
  modules.service-catalog.kinds.searxng = _: {
    title = "SearXNG";
    units = [
      "searx.service"
    ];
  };
}
