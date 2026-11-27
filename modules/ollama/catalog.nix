# What HyperMonitor shows for this kind and the attos-deck-agent may run (modules.service-catalog).
{ ... }:
{
  # Without the web UI the hostname has no HTTP route, so no probe (ps.catalog drops it).
  modules.service-catalog.kinds.ollama =
    { cfg, ... }:
    {
      title = "Ollama";
      units = [
        "ollama.service"
      ]
      ++ (if cfg.webui or false then [ "docker-open-webui.service" ] else [ ]);
    };
}
