# What HyperMonitor shows for this kind and the attos-deck-agent may run (modules.service-catalog).
{ ... }:
{
  modules.service-catalog.kinds.groupware = _: {
    title = "グループウェア";
    units = [
      "nginx.service"
      "phpfpm-roundcube.service"
      "radicale.service"
    ];
    order = 20;
  };
}
