{ config, lib, ... }:
let
  cfg = config.modules.ollama;
in
{
  config = lib.mkIf cfg.enable {
    services.ollama = {
      enable = true;
      package = lib.mkDefault cfg.package;
      home = lib.mkDefault cfg.home;
      modelsDir = lib.mkDefault cfg.modelsDir;
      host = lib.mkDefault cfg.host;
      port = lib.mkDefault cfg.port;
      loadModels = lib.mkDefault cfg.loadModels;
      openFirewall = lib.mkDefault true;
      syncModels = lib.mkDefault false;
      environmentVariables = lib.mapAttrs (_: lib.mkDefault) (
        {
          OLLAMA_NO_CLOUD = "1";
          OLLAMA_CONTEXT_LENGTH = "32768";
          OLLAMA_NUM_PARALLEL = "1";
          OLLAMA_KEEP_ALIVE = "10m";
        }
        // cfg.environmentVariables
      );
    };

    systemd.services.ollama = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      unitConfig.RequiresMountsFor = [
        config.services.ollama.home
        config.services.ollama.modelsDir
      ];
      serviceConfig = {
        Restart = lib.mkDefault "on-failure";
        RestartSec = lib.mkDefault "5s";
      };
    };
  };
}
