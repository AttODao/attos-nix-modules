{ lib, options, ... }:
{
  imports = [ ./nixos.nix ];

  options.modules.ollama = {
    enable = lib.mkEnableOption "shared Ollama service configuration";
  }
  //
    lib.mapAttrs
      (
        _: option:
        lib.mkOption {
          inherit (option) type default description;
        }
      )
      (
        lib.getAttrs [
          "package"
          "home"
          "modelsDir"
          "host"
          "port"
          "loadModels"
          "environmentVariables"
        ] options.services.ollama
      );
}
