# What HyperMonitor shows for this kind and the attos-deck-agent may run (modules.service-catalog).
{ ... }:
{
  modules.service-catalog.kinds.vaultwarden = _: {
    title = "Vaultwarden";
    units = [
      "vaultwarden.service"
    ];
    probe = "/alive";
  };
}
