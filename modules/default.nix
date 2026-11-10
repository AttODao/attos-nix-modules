let
  entries = builtins.readDir ./.;
  dirs = builtins.filter (name: entries.${name} == "directory") (builtins.attrNames entries);
  # Import order of the former hand-written list. Module order decides the order of list
  # definitions (environment.systemPackages, home.packages), so keeping it keeps the consumers'
  # derivations unchanged. New directories need no entry here: they follow in alphabetical order,
  # and removed ones are skipped. Dropping this list only reorders those lists once (same contents).
  legacyOrder = [
    "home-manager"
    "public-services"
    "attos-deck"
    "attos-hoyo-dashboard"
    "attos-mouse"
    "bot-screen-host"
    "code-server"
    "skills"
    "cloudflare-ddns"
    "cloudflare-public-cnames"
    "dns"
    "docker"
    "forgejo"
    "forgejo-actions-runner"
    "groupware"
    "headscale"
    "hermes"
    "heavy"
    "attos-jobs"
    "host-report"
    "immich"
    "incus"
    "jellyfin"
    "karakeep"
    "mailserver"
    "mcsmanager"
    "ollama"
    "open-terminal"
    "opencloud"
    "openssh"
    "searxng"
    "shutdown-hold"
    "strata"
    "traefik"
    "vaultwarden"
    "ytdl-sub"
    "zed"
    "atcoder-go"
    "ccpocket"
    "claude-code"
    "desktop-theme"
    "discord"
    "fcitx5"
    "floorp"
    "fonts"
    "foot"
    "greeter"
    "hermes-desktop"
    "hyprland"
    "immich-client"
    "linux-wallpaperengine"
    "login-pin"
    "limine"
    "noctalia"
    "amazon-music"
    "open-deck-desktop"
    "opencloud-client"
    "pandora-launcher"
    "paseo"
    "pcmanfm"
    "pi"
    "pipeasio"
    "pipewire"
    "scarlett-driver"
    "solaar"
    "ssh"
    "steam"
    "thunderbird"
    "userDirs"
    "vscode"
    "yazi"
    "zsh"
  ];
in
{
  # Keep imports static; feature defaults decide activation and dependencies.
  # Every directory here is a feature module and is imported from the directory listing alone:
  # imports must never depend on option values (that recurses), so enabling stays with each
  # feature's `modules.<name>.enable`.
  imports = map (name: ./. + "/${name}") (
    builtins.filter (name: builtins.elem name dirs) legacyOrder
    ++ builtins.filter (name: !builtins.elem name legacyOrder) dirs
  );
}
