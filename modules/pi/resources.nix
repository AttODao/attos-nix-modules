# One catalog drives the public switches and Home Manager resource selection.
{
  pkgs,
  lib,
  attopkgs,
  piSessionsSource ? null,
}:
let
  mattSkills = pkgs.fetchFromGitHub {
    owner = "mattpocock";
    repo = "skills";
    rev = "006a52be23e0178375e083e30535fa8224471f3e";
    hash = "sha256-g32DrgTt1/6MXeuHnlGAcl7xb+kema5+9UVsiTbgYIs=";
  };
  vercelSkills = pkgs.fetchFromGitHub {
    owner = "vercel-labs";
    repo = "skills";
    rev = "18f96ea131dab3b0fcc9b27cf7c6f6cbb6174680";
    hash = "sha256-FJLz/HfqBWtsJUuKs0w/OmErdyUi5/fKdNiTBpDtT1A=";
  };
  contextMode = attopkgs.context-mode;
  piSessions =
    if piSessionsSource != null then
      piSessionsSource
    else
      pkgs.fetchFromGitHub {
        owner = "thurstonsand";
        repo = "pi-sessions";
        rev = "3f7cd305414e95f9350541a5f95cd286a06e3705";
        hash = "sha256-abHSnNpD0tOXObRfLDJPpZPapm3+kvMaVWED+jEhMO4=";
      };
  piReview = pkgs.fetchFromGitHub {
    owner = "bacnh85";
    repo = "pi-extensions";
    rev = "5388a5f1987873fe1355064f72021452c4347c72";
    hash = "sha256-8igRRDOEDIO0Nae7vzTSfnYg06i8KNiDM3XgkWT/CJY=";
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
    rev = "0c646fb606ddbf7e7bebaa379a43e29e9920a47a";
    hash = "sha256-8odkgve5sx3x52Vl+ICoeTcLJUD4Yrv802l60idu/mo=";
  };
  ponytail = pkgs.fetchFromGitHub {
    owner = "DietrichGebert";
    repo = "ponytail";
    rev = "v4.10.3";
    hash = "sha256-aypYnQf+zkKGj+dfs+qFKTFIvaick9p0XJNtPkSwIB0=";
  };
in
{
  plugins = {
    context-mode = {
      source = "${contextMode}/lib/context-mode";
      entry = "build/adapters/pi/extension.js";
    };
    pi-mcp-adapter.package = "npm:pi-mcp-adapter@5.3.0";
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
