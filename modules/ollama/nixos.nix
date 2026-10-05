{ config, lib, ... }:
{
  config = lib.mkIf config.modules.ollama.enable {
    # Storage, bind address, models, package and GPU settings use the native
    # services.ollama options and remain consumer-owned.
    services.ollama = {
      enable = true;
      openFirewall = lib.mkDefault true;
      syncModels = lib.mkDefault false;
      environmentVariables = {
        OLLAMA_NO_CLOUD = lib.mkDefault "1";
        OLLAMA_CONTEXT_LENGTH = lib.mkDefault "32768";
        OLLAMA_NUM_PARALLEL = lib.mkDefault "1";
        OLLAMA_KEEP_ALIVE = lib.mkDefault "10m";
      };
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
