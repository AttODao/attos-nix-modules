# What HyperMonitor shows for this kind and the attos-deck-agent may run (modules.service-catalog).
{ ... }:
{
  modules.service-catalog.kinds.mcsmanager = _: {
    title = "MCSManager";
    units = [
      "mcsmanager-web.service"
      "mcsmanager-daemon.service"
    ];
  };
}
