# What HyperMonitor shows for this kind and the attos-deck-agent may run (modules.service-catalog).
{ ... }:
{
  modules.service-catalog.kinds.opencloud = _: {
    title = "OpenCloud";
    units = [
      "opencloud.service"
    ];
  };
}
