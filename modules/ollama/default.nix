{ lib, ... }:
{
  imports = [ ./nixos.nix ];

  options.modules.ollama.enable = lib.mkEnableOption "shared Ollama service configuration";
}
