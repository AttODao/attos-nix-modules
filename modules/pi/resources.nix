# Pi plugin catalog; it drives the public switches and Home Manager resource selection.
# Skills live in modules/skills.
{
  pkgs,
  lib,
  attopkgs,
}:
let
  contextMode = attopkgs.context-mode;
  inherit (import ../skills/sources.nix { inherit pkgs; }) ponytail;
  piSessions = pkgs.fetchFromGitHub {
    owner = "thurstonsand";
    repo = "pi-sessions";
    rev = "0c47c01978f1f8aaa21a9499d724c886f1c34d42";
    hash = "sha256-RWYLI11xW2IVtGpbFLo5EPwxUO6h9sy74tML34LXJb4=";
  };
  piReview = pkgs.fetchFromGitHub {
    owner = "bacnh85";
    repo = "pi-extensions";
    rev = "85233b0ea14aa62104593140f9788bcb083e10e4";
    hash = "sha256-ZWBavlbjWEounxhCs3YVuhWHvDFYwB2ZZ0wbvzN70RE=";
  };
  piUsage = pkgs.fetchFromGitHub {
    owner = "mtrojnar";
    repo = "pi-usage";
    rev = "bab49aed024f76b60877bc08f6854a8ffcb6d4b1";
    hash = "sha256-e+AOcwQSPxYAaMg2y+crbEh/6QKw9oDkHLF4NRQzwv8=";
  };
  piKeepGoing = pkgs.fetchFromGitHub {
    owner = "ohlulu";
    repo = "pi-keep-going";
    rev = "0ae1d40870af9ebfb9debc806196c84d8657fca0";
    hash = "sha256-udpBIxaceQv78HoUp3VPI7wTBUgE0ASXiTAGNyb0Wrc=";
  };
in
{
  plugins = {
    context-mode = {
      source = "${contextMode}/lib/context-mode";
      entry = "build/adapters/pi/extension.js";
    };
    pi-mcp-adapter.package = "npm:pi-mcp-adapter@5.3.2";
    pi-sessions = {
      source = piSessions;
      entry = "extensions/pi-sessions.ts";
    };
    pi-mermaid-studio = {
      source = "${attopkgs.pi-mermaid-studio}/lib/pi-mermaid-studio";
      entry = "extensions/index.ts";
    };
    pi-review = {
      source = "${piReview}/pi-review";
      entry = "extensions/index.ts";
    };
    pi-usage = {
      source = piUsage;
      entry = "index.ts";
    };
    pi-keep-going = {
      source = piKeepGoing;
      entry = "src/index.ts";
    };
    ponytail = {
      source = ponytail;
      entry = "pi-extension/index.js";
    };
  };
}
