{ osConfig, lib, ... }:
{
  config = lib.mkIf osConfig.modules.zed.enable {
    programs.zed-editor = {
      enable = true;
      userSettings = lib.mkDefault osConfig.modules.zed.userSettings;
    };

    home.file.".local/share/zed/external_agents/registry/npx/codex-acp/.npmrc" =
      lib.mkIf (osConfig.modules.zed.codexAcp.npmPolicy == "bounded-offline")
        {
          text = ''
            audit=false
            fetch-retries=1
            fetch-retry-maxtimeout=5000
            fetch-retry-mintimeout=1000
            fetch-timeout=10000
            prefer-offline=true
          '';
        };
  };
}
