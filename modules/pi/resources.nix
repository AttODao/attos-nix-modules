# One catalog drives the public switches and Home Manager resource selection.
{
  pkgs,
  lib,
  attopkgs,
}:
let
  mattSkills = pkgs.fetchFromGitHub {
    owner = "mattpocock";
    repo = "skills";
    rev = "49dd158d1076134a641b33efb035946536778336";
    hash = "sha256-NljCSZNI3sZ+vbCw7pRdrwR7try4BxOFp4gdjuWYtzs=";
  };
  vercelSkills = pkgs.fetchFromGitHub {
    owner = "vercel-labs";
    repo = "skills";
    rev = "13e4063a1cf913f5606d57d42ab83a86f5001e04";
    hash = "sha256-djzSciYX530uc1Xk4+Vdf2IHmNotC0bb6YU/peF0UK4=";
  };
  contextMode = attopkgs.context-mode;
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
  ponytail = pkgs.fetchFromGitHub {
    owner = "DietrichGebert";
    repo = "ponytail";
    rev = "v5.3.2";
    hash = "sha256-IJlhfkdXI6pMZZCZO7XBRg88LBiNfzc5Gnm4ofGybL8=";
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
  skills = {
    pi-mermaid-studio = "${attopkgs.pi-mermaid-studio}/lib/pi-mermaid-studio/skills/mermaid";
    find-skills = "${vercelSkills}/skills/find-skills";
    grilling = "${mattSkills}/skills/productivity/grilling";
    improve-codebase-architecture = "${mattSkills}/skills/engineering/improve-codebase-architecture";
  }
  // lib.genAttrs [
    "ponytail"
    "ponytail-audit"
    "ponytail-debt"
    "ponytail-gain"
    "ponytail-help"
    "ponytail-review"
  ] (name: "${ponytail}/skills/${name}")
  // lib.genAttrs [
    "context-mode"
    "ctx-doctor"
    "ctx-index"
    "ctx-insight"
    "ctx-purge"
    "ctx-search"
    "ctx-stats"
    "ctx-upgrade"
  ] (name: "${contextMode}/lib/context-mode/skills/${name}");
}
