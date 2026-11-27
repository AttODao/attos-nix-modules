# What HyperMonitor shows for this kind and the attos-deck-agent may run (modules.service-catalog).
{ ... }:
{
  modules.service-catalog.kinds.hypermonitor = _: {
    title = "HyperMonitor";
    units = [ "hypermonitor.service" ];
    probe = "/api/v1/health";
  };
}
