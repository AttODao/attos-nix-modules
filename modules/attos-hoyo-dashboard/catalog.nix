# What HyperMonitor shows for this kind and the attos-deck-agent may run (modules.service-catalog).
{ ... }:
{
  modules.service-catalog.kinds.attos-hoyo-dashboard = _: {
    title = "AHD";
    kind = "ahd";
    units = [
      "docker-attos-hoyo-dashboard.service"
      "docker-attos-hoyo-dashboard-db.service"
    ];
    probe = "/health";
  };
}
