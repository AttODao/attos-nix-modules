# What HyperMonitor shows for this kind and the attos-deck-agent may run (modules.service-catalog).
{ ... }:
{
  modules.service-catalog.kinds.hermes = _: {
    title = "Hermes";
    units = [
      "hermes-agent.service"
    ];
  };
}
