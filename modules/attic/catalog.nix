# What HyperMonitor shows for this kind and the attos-deck-agent may run (modules.service-catalog).
{ ... }:
{
  modules.service-catalog.kinds.attic = _: {
    title = "Attic";
    units = [
      "atticd.service"
    ];
  };
}
