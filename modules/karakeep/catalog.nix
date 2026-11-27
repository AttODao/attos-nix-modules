# What HyperMonitor shows for this kind and the attos-deck-agent may run (modules.service-catalog).
{ ... }:
{
  modules.service-catalog.kinds.karakeep = _: {
    title = "Karakeep";
    units = [
      "karakeep-web.service"
      "karakeep-workers.service"
      "karakeep-browser.service"
      "meilisearch.service"
    ];
  };
}
