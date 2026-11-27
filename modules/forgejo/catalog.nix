# What HyperMonitor shows for this kind and the attos-deck-agent may run (modules.service-catalog).
{ ... }:
{
  modules.service-catalog.kinds.forgejo = _: {
    title = "Forgejo";
    units = [
      "forgejo.service"
    ];
    probe = "/api/v1/version";
  };
}
