# What HyperMonitor shows for this kind and the attos-deck-agent may run (modules.service-catalog).
{ ... }:
{
  modules.service-catalog.kinds.headscale = _: {
    title = "Headscale";
    units = [
      "headscale.service"
    ];
    probe = "/health";
  };
}
