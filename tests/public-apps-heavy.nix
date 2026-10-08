# nix-instantiate --eval --strict tests/public-apps-heavy.nix \
#   --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix { inherit nixpkgs homeManager system; };
  inherit (t) lib;
  ps = import ../modules/public-services/lib.nix { inherit lib; };
  routeUrl =
    cfg: service:
    (builtins.head (lib.filter (route: route.service == service) (ps.routes cfg))).cfg.backendUrl;
  services = [
    "forgejo"
    "immich"
    "karakeep"
  ];
  containers = [
    "forgejo-db"
    "forgejo"
    "immich-database"
    "immich-machine-learning"
    "immich-redis"
    "immich-server"
    "karakeep-meilisearch"
    "karakeep-chrome"
    "karakeep"
  ];
  swarm = {
    modules.swarm = {
      enable = true;
      role = "manager";
      advertiseAddress = "10.1.0.1";
      networkSubnet = "10.2.0.0/24";
      networkGateway = "10.2.0.1";
    };
  };
  activeModule.modules.public-services = {
    "forge.example.org".forgejo = {
      enable = true;
      host = "nixos";
      dataDir = "/srv/forgejo";
      environmentFile = "/run/private/forgejo.env";
      userUid = 1201;
      userGid = 1202;
      mailAddress = "forge@example.org";
      mailHost = "mail.example.org";
      sshHost = "git.example.org";
      sshBindAddress = "10.1.0.2";
    };
    "photos.example.org".immich = {
      enable = true;
      host = "nixos";
      dataDir = "/srv/immich";
      environmentFile = "/run/private/immich.env";
    };
    "keep.example.org".karakeep = {
      enable = true;
      host = "nixos";
      dataDir = "/srv/karakeep";
      environmentFile = "/run/private/karakeep.env";
      dataUid = 1301;
      dataGid = 1302;
    };
  };
  base = t.cfgFor [ ];
  disabled = t.cfgFor [
    {
      modules.public-services."unused.example.org" = lib.genAttrs services (_: {
        enable = false;
      });
    }
  ];
  active = t.cfgFor [
    swarm
    activeModule
  ];
  activeHeadless =
    (t.evalSystem {
      users = [ ];
      modules = [
        swarm
        activeModule
      ];
    }).config;
  headless = (t.evalSystem { users = [ ]; }).config;
  remote = t.cfgFor [
    {
      modules.public-services = builtins.listToAttrs (
        map (service: {
          name = "${service}.remote.example.org";
          value.${service} = {
            enable = true;
            host = "remote";
            deploy = false;
            private = true;
          };
        }) services
      );
    }
  ];
  overridden = t.cfgFor [
    swarm
    activeModule
    {
      virtualisation.oci-containers.containers = {
        forgejo = {
          image = "forgejo:test";
          environment.FORGEJO__mailer__SMTP_PORT = "2525";
          environmentFiles = [ "/run/other/forgejo.env" ];
          ports = [ "127.0.0.1:2222:22" ];
        };
        immich-server.image = "immich:test";
        immich-redis.extraOptions = [ "--restart=on-failure" ];
        karakeep = {
          image = "karakeep:test";
          environment.LOG_LEVEL = "debug";
        };
      };
      systemd.tmpfiles.rules = [ "d /srv/unrelated 0700 root root -" ];
      systemd.tmpfiles.settings."10-karakeep"."/srv/karakeep/data".d.mode = "0700";
    }
  ];
  allAssertions = cfg: lib.all (a: a.assertion) cfg.assertions;
  isolated =
    cfg:
    !cfg.modules.docker.enable
    && !cfg.modules.swarm.enable
    && lib.all (name: !(builtins.hasAttr name cfg.virtualisation.oci-containers.containers)) containers
    && lib.all (
      service:
      !(builtins.hasAttr "docker-network-${service}" cfg.systemd.services)
      && !(builtins.hasAttr "10-${service}" cfg.systemd.tmpfiles.settings)
    ) services;
  c = active.virtualisation.oci-containers.containers;
  o = overridden.virtualisation.oci-containers.containers;
  mounts = name: active.systemd.services."docker-${name}".unitConfig.RequiresMountsFor;
  networkDeps =
    service: name:
    let
      unit = active.systemd.services."docker-${name}";
    in
    lib.elem "docker-network-${service}.service" unit.requires
    && lib.elem "docker-network-${service}.service" unit.after
    && lib.hasInfix "network inspect" unit.preStart;
  traefikDeps =
    name:
    let
      unit = active.systemd.services."docker-${name}";
    in
    lib.elem "docker-network-traefik.service" unit.wants
    && lib.elem "docker-network-traefik.service" unit.after;
  duplicate =
    service:
    t.cfgFor [
      swarm
      activeModule
      {
        modules.public-services."second.example.org".${service} =
          activeModule.modules.public-services.${
            if service == "forgejo" then
              "forge.example.org"
            else if service == "immich" then
              "photos.example.org"
            else
              "keep.example.org"
          }.${service};
      }
    ];
  duplicateRejected =
    service:
    lib.any (a: !a.assertion && lib.hasInfix "only one local ${service}" a.message)
      (duplicate service).assertions;
  localAndRemote = t.cfgFor [
    swarm
    activeModule
    {
      modules.public-services = builtins.listToAttrs (
        map (service: {
          name = "${service}.elsewhere.example.org";
          value.${service} = {
            enable = true;
            host = "remote";
            deploy = false;
          };
        }) services
      );
    }
  ];
  invalid =
    value:
    builtins.tryEval
      (t.cfgFor [ { modules.public-services."invalid.example.org".immich.dataDir = value; } ])
      .modules.public-services."invalid.example.org".immich.dataDir;
  missingData = builtins.tryEval (
    builtins.deepSeq
      (t.cfgFor [
        swarm
        {
          modules.public-services."missing.example.org".immich = {
            enable = true;
            host = "nixos";
          };
        }
      ]).virtualisation.oci-containers.containers
      true
  );
  dependencyRejected =
    dependency:
    !(builtins.tryEval
      (t.cfgFor [
        swarm
        activeModule
        { modules.${dependency}.enable = false; }
      ]).modules.${dependency}.enable
    ).success;
  monolith = t.attopkgs.karakeep-monolith;
in
assert isolated base && isolated disabled && isolated remote && isolated headless;
assert
  allAssertions base && allAssertions disabled && allAssertions remote && allAssertions headless;
assert base.modules.public-services == { };
assert lib.all (service: !base.modules.${service}.enable) services;
assert headless.home-manager.users == { } && activeHeadless.home-manager.users == { };
assert (t.hm active "test").programs.home-manager.enable;
assert
  (t.hmFor [
    swarm
    activeModule
  ]).programs.home-manager.enable;
assert active.modules.docker.enable && active.modules.swarm.enable;
assert active.virtualisation.oci-containers.backend == "docker";
assert allAssertions active && allAssertions activeHeadless && allAssertions overridden;
assert lib.all (
  service: remote.modules.public-services."${service}.remote.example.org".${service}.private
) services;
assert routeUrl active "forgejo" == "http://forgejo:3000";
assert routeUrl active "immich" == "http://immich-server:2283";
assert routeUrl active "karakeep" == "http://karakeep:3000";
assert
  c.forgejo.image
  == "codeberg.org/forgejo/forgejo:16.0.5@sha256:cf5f5ae6acf2ababca0ee3d255705b83a47f35b25e07fc931d694d60664053fe";
assert
  c.forgejo-db.image
  == "postgres:14.24@sha256:c2427de38f998489d36de7ca3553db2134872c400f2b08be4b824e5c50e4d619";
assert
  c.immich-database.image
  == "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23";
assert
  c.immich-machine-learning.image
  == "ghcr.io/immich-app/immich-machine-learning:v3.2.4@sha256:e16c2f166a8174901959fdf85e2e4c7bd1ebc4b37e0b6655de97c41408a260c4";
assert
  c.immich-redis.image
  == "docker.io/valkey/valkey:9.1.2@sha256:418652cfb58ef879d4978c33553735d7147016032d5aefaa14c828e611eb9dfd";
assert
  c.immich-server.image
  == "ghcr.io/immich-app/immich-server:v3.2.4@sha256:d317916b28090c33eb36b308464ea391f8b7df1d850fcfea227a39ec879718c2";
assert
  c.karakeep-meilisearch.image
  == "getmeili/meilisearch:v1.54.3@sha256:e68913ab7d6f5b159529e472cfd362ce3c741fafd3c127961b2142abbe41b3c9";
assert c.karakeep-chrome.image == "ghcr.io/karakeep-app/karakeep-chrome:release";
assert c.karakeep.image == "ghcr.io/karakeep-app/karakeep:0.33.2";
assert lib.all (name: !c.${name}.autoRemoveOnStop) containers;
assert c.forgejo.extraOptions == [ "--restart=always" ];
assert c.forgejo-db.extraOptions == [ "--restart=always" ];
assert lib.all (name: lib.elem "--restart=unless-stopped" c.${name}.extraOptions) (
  lib.subtractLists [ "forgejo" "forgejo-db" ] containers
);
assert c.forgejo.environmentFiles == [ "/run/private/forgejo.env" ];
assert c.forgejo-db.environmentFiles == c.forgejo.environmentFiles;
assert lib.all (name: c.${name}.environmentFiles == [ "/run/private/immich.env" ]) [
  "immich-database"
  "immich-machine-learning"
  "immich-server"
];
assert c.karakeep.environmentFiles == [ "/run/private/karakeep.env" ];
assert c.karakeep-meilisearch.environmentFiles == c.karakeep.environmentFiles;
assert c.forgejo.environment.USER_UID == "1201" && c.forgejo.environment.USER_GID == "1202";
assert c.forgejo.environment.FORGEJO__server__DOMAIN == "forge.example.org";
assert c.forgejo.environment.FORGEJO__server__ROOT_URL == "https://forge.example.org/";
assert c.forgejo.environment.FORGEJO__server__SSH_DOMAIN == "git.example.org";
assert c.forgejo.environment.FORGEJO__mailer__FROM == "forge@example.org";
assert c.forgejo.environment.FORGEJO__mailer__SMTP_ADDR == "mail.example.org";
assert c.forgejo.ports == [ "10.1.0.2:22:22" ];
assert
  c.forgejo.volumes == [
    "/srv/forgejo/forgejo:/data"
    "/etc/localtime:/etc/localtime:ro"
  ];
assert c.forgejo-db.volumes == [ "/srv/forgejo/postgres:/var/lib/postgresql/data" ];
assert
  c.immich-server.volumes == [
    "/etc/localtime:/etc/localtime:ro"
    "/srv/immich/library:/data"
  ];
assert c.immich-database.volumes == [ "/srv/immich/postgres:/var/lib/postgresql/data" ];
assert c.immich-redis.volumes == [ "/srv/immich/redis:/data" ];
assert c.immich-machine-learning.volumes == [ "/srv/immich/model-cache:/cache" ];
assert c.karakeep-meilisearch.volumes == [ "/srv/karakeep/meilisearch:/meili_data" ];
assert lib.elem "/srv/karakeep/data:/data" c.karakeep.volumes;
assert lib.elem "${monolith}/bin/monolith:/usr/local/bin/monolith:ro" c.karakeep.volumes;
assert lib.elem "--ip=172.20.0.3" c.karakeep-chrome.extraOptions;
assert c.karakeep.environment.NEXTAUTH_URL == "https://keep.example.org";
assert c.karakeep.environment.BROWSER_WEB_URL == "http://172.20.0.3:9222";
assert
  c.karakeep.environment.MONOLITH_FRAGMENT_NAVIGATION_PREFIX
  == "https://keep.example.org/api/assets/";
assert !(c.karakeep.environment ? OPENAI_API_KEY) && !(c.karakeep.environment ? OPENAI_BASE_URL);
assert
  !(c.karakeep.environment ? EMBEDDING_OPENAI_API_KEY)
  && !(c.karakeep.environment ? EMBEDDING_OPENAI_BASE_URL);
assert !(c.karakeep.environment ? INFERENCE_TEXT_MODEL);
assert c.forgejo.dependsOn == [ "forgejo-db" ];
assert
  c.immich-server.dependsOn == [
    "immich-database"
    "immich-redis"
  ];
assert
  c.karakeep.dependsOn == [
    "karakeep-meilisearch"
    "karakeep-chrome"
  ];
assert lib.all
  (
    name:
    mounts name == [
      "/srv/forgejo"
      "/run/private/forgejo.env"
    ]
    && networkDeps "forgejo" name
  )
  [
    "forgejo-db"
    "forgejo"
  ];
assert lib.all (name: mounts name == [ "/srv/immich" ] && networkDeps "immich" name) [
  "immich-database"
  "immich-machine-learning"
  "immich-redis"
  "immich-server"
];
assert lib.all (name: mounts name == [ "/srv/karakeep" ] && networkDeps "karakeep" name) [
  "karakeep-meilisearch"
  "karakeep-chrome"
  "karakeep"
];
assert lib.all traefikDeps [
  "forgejo"
  "immich-server"
  "karakeep"
];
assert lib.elem "--network-alias=database" c.immich-database.extraOptions;
assert lib.elem "--network-alias=redis" c.immich-redis.extraOptions;
assert lib.elem "--network-alias=meilisearch" c.karakeep-meilisearch.extraOptions;
assert lib.elem "--network-alias=chrome" c.karakeep-chrome.extraOptions;
assert lib.all (name: c.${name}.networks == [ "forgejo" ]) [ "forgejo-db" ];
assert
  c.forgejo.networks == [
    "forgejo"
    "traefik"
  ];
assert
  c.immich-server.networks == [
    "immich"
    "traefik"
  ];
assert
  c.karakeep.networks == [
    "karakeep"
    "traefik"
  ];
assert active.systemd.tmpfiles.settings."10-forgejo"."/srv/forgejo/postgres".d.mode == "0700";
assert active.systemd.tmpfiles.settings."10-immich"."/srv/immich/redis".d.mode == "0700";
assert active.systemd.tmpfiles.settings."10-karakeep"."/srv/karakeep/data".d.user == "1301";
assert active.systemd.tmpfiles.settings."10-karakeep"."/srv/karakeep/meilisearch".d.group == "1302";
assert lib.hasInfix "172.20.0.0/24" active.systemd.services.docker-network-karakeep.script;
assert lib.hasInfix "172.20.0.1" active.systemd.services.docker-network-karakeep.script;
assert
  o.forgejo.image == "forgejo:test"
  && o.immich-server.image == "immich:test"
  && o.karakeep.image == "karakeep:test";
assert o.forgejo.environment.FORGEJO__mailer__SMTP_PORT == "2525";
assert o.forgejo.environment.FORGEJO__server__DOMAIN == "forge.example.org";
assert o.forgejo.environmentFiles == [ "/run/other/forgejo.env" ];
assert o.forgejo.ports == [ "127.0.0.1:2222:22" ];
assert o.immich-redis.extraOptions == [ "--restart=on-failure" ];
assert o.karakeep.environment.LOG_LEVEL == "debug" && o.karakeep.environment.DATA_DIR == "/data";
assert overridden.systemd.tmpfiles.settings."10-karakeep"."/srv/karakeep/data".d.mode == "0700";
assert overridden.systemd.tmpfiles.settings."10-immich"."/srv/immich/library".d.mode == "0755";
assert lib.all duplicateRejected services;
assert allAssertions localAndRemote;
assert !(invalid "relative/path").success && !(invalid /tmp).success;
assert !missingData.success;
assert dependencyRejected "docker" && dependencyRejected "swarm";
assert monolith.doInstallCheck && monolith.version == t.pkgs.pkgsStatic.monolith.version;
assert lib.elem ../packages/karakeep-monolith.patch monolith.patches;
true
