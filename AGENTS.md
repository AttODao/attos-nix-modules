# Creating shared modules and adopting them on the consumer side

To create a new consumer environment, follow [the Wiki's guide to creating a new environment](https://git.attodao.cc/AttODao/attos-nix-modules/wiki/getting-started).
To adopt modules on the consumer side, use the shared entry point and the existing public API; do not add, without permission, changes to the shared implementation, integration into other repos, pin updates, builds, applying to real machines, or commit/push.

The following is the procedure for adding or changing a feature module in `attos-nix-modules`.
Treat the shared repo implementation, the consumer's code migration and lock update, the build, and applying to real machines as separate completion criteria.

## 1. Check the existing implementation and responsibilities

- First check `git status --short` and preserve existing user changes.
- Read `README.md` and the [Wiki](https://git.attodao.cc/AttODao/attos-nix-modules/wiki) page for the target module.
- Check `modules/default.nix` and the target and dependency modules.
- When moving existing configuration, trace the consumer's NixOS / HM configuration, package source, dependencies and runtime assumptions in both scopes. For the current design and API, check the README, Wiki and implementation of the adopted revision.
- Reuse similar implementations and standard NixOS / Home Manager options; do not add custom resolvers, host registries or unnecessary wrappers.

### Boundary between the shared side and the consumer side

The shared side is responsible for feature settings, dependencies between features, and HM loading, common settings and package arguments.
Hardware, user creation, login shell, permissions/linger, secrets, stateVersion, storage locations, unfree allowance and device-specific values stay on the consumer side.
Device-specific values include personally identifying information such as user names, accounts and email addresses, FQDNs/URLs of services the consumer operates, and device serials/IDs. The shared side holds only packages and feature settings as defaults; it receives these values from the consumer through typed options.

Do not embed secret contents in Nix expressions or import them into the Nix store. When needed, reference the runtime path after decryption.
Shared modules do not know the name of the secrets backend (`sops`, `agenix`, etc.). Do not reference `config.sops.secrets` or similar directly; always receive paths through the module's own options.
Do not overwrite authentication, history or mutable data with declarative configuration.

## 2. Decide the minimal public API

- Consolidate feature selection into `modules.<name>.enable` on the NixOS side, defaulting to false with `lib.mkEnableOption`. Public servers use `modules.public-services.<FQDN>.<service>`, and localhost-only standalone use uses `modules.<service>`. Reuse the same typed schema via `moduleOptions` in `public-services/lib.nix`, and do not inject standalone use into the public registry (keep the scope of the existing Paseo bridge and SSH client/server).
- When enabled, a public service sets `host` to the owning OS's `networking.hostName`. Physical hosts and guests read the same namespace, and only the owning OS starts the actual service. `deploy` defaults to true for all kinds; false is only for registering unmanaged endpoints. Do not implement rewriting another host's record to false.
- Give HM-only features an enable on the NixOS side as well. `home.nix` reads its settings only through `osConfig.modules.<name>`; do not declare options or a second enable in `home.nix`. The standalone Home Manager export (`flake.modules.homeManager.default` / `.<name>`, built by `modules/home-manager/standalone.nix` from the same modules) evaluates the NixOS-side modules without NixOS and passes the result as `osConfig`, so it needs no per-feature code. A `home.nix` that reads NixOS options other than `osConfig.modules.*` (e.g. `osConfig.programs.hyprland`) makes the feature unusable standalone: list it in `hmSkip` in `tests/default.nix` with the reason and in the README.
- Renaming or removing a public option is a breaking change for consumers. Keep the old path in the feature's `default.nix` with `(lib.mkRenamedOptionModule [ "modules" "<name>" "<old>" ] [ "modules" "<name>" "<new>" ])` or `(lib.mkRemovedOptionModule [ "modules" "<name>" "<old>" ] "<what to use instead>")` in `imports`, so consumers get a warning or an error naming the replacement instead of "option does not exist". Remove the alias only in a later, separate change after the consumers have migrated.
- Limit custom options other than enable to values the consumer must pass. Define the type, the description, and a reasonable default or the requirement when enabled.
- Make per-user adjustments writable in the standard `home-manager.users.<name>`. Use `lib.mkDefault` for adjustable defaults, and do not casually pin them with `mkForce`. For large settings trees (shell, browser, bar settings, etc.), make each leaf `mkDefault` with `lib.mapAttrsRecursive (_: lib.mkDefault)` so the consumer can override only part of it without `mkForce`.
- Values that widen external reachability, privilege or trust scope (relay, external exposure, socket mounts, trusted proxy ranges, disabling rate limits, etc.) are disabled by default, and the consumer enables them explicitly. Defaults for public services must not be looser than for standalone use.
- Only one module may claim a default for the same consumer option (default apps, MIME associations, environment variables, etc.). When multiple modules are candidates, make them mutually exclusive with dependency declarations in `default.nix` or `mkIf (!config.modules.<other>.enable)`; do not line up values of equal priority and leave it to evaluation order.
- Enable required dependency features with `modules.<dependency>.enable = true;` when the target feature is enabled. Do not hide conflicts with a plainly assigned false.

## 3. Create the feature directory

```text
modules/<name>/
  default.nix   public options, dependencies, wiring into both scopes
  home.nix      actual HM settings (only when needed)
  nixos.nix     actual NixOS settings (only when needed)
  <assets>      accompanying scripts, desktop entries, etc.
```

Do not create empty scope files or abstractions for future use.
For HM only, use `modules/foot/` as a reference; for both scopes, `modules/thunderbird/`; for NixOS only, `modules/pipewire/`.

Minimal form of a feature with both scopes (replace `example` with the actual feature name):

```nix
# modules/example/default.nix
{ config, lib, ... }:
{
  imports = [ ./nixos.nix ];

  options.modules.example.enable = lib.mkEnableOption "shared example configuration";

  config = lib.mkIf config.modules.example.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
```

- Declare NixOS `imports` statically; do not build them from enable. The same applies to imports of dependency modules.
- Wrap the actual configuration in `nixos.nix` in `lib.mkIf config.modules.<name>.enable`. For public servers and standalone use, reuse `select`, `moduleOptions`, `common`, `pathOption` and `require` from `public-services/lib.nix`, and wrap the same implementation in `select.enabled`. Only in the `select.standalone` case use localhost bind/HTTP and the normal Docker bridge, and do not create public records or gateway dependencies. When public, bind the native service to the address:port of `backendEndpoint`; do not bind to all interfaces such as `0.0.0.0`. Also register the singleton assertion, and when disabled, on a `host` mismatch, or with `deploy = false`, do not create local dependencies, required paths or units.
- Use `public-services/lib.nix` through the module argument `ps` (`_module.args.ps`); do not `import ../public-services/lib.nix` in each module. When the same derivation logic (listen address, `network-online.target` dependency, bracket stripping, etc.) appears in 3 or more modules, put it into `lib.nix` before copying it into each module.
- Public namespaces only extend the type; do not redeclare the root default / description in each service. Derive DNS, CNAME and proxy from the namespace; do not import the consumer's `public-hosts.nix` or a separate host registry. For concrete examples and constraints, see [the Wiki's public service API](https://git.attodao.cc/AttODao/attos-nix-modules/wiki/module-public-services) and each service page.
- Wrap the actual configuration in `home.nix` in `lib.mkIf osConfig.modules.<name>.enable`. The standalone export imports every `home.nix` unconditionally, so nothing outside this `mkIf` may take effect (unconditional `imports`/`disabledModules` must keep a disabled feature's result unchanged, as in `modules/fcitx5/home.nix`).
- Connect HM configuration via `home-manager.sharedModules`. Do not hard-code it for specific users or implement per-feature iteration over the user list.
- Enabled HM configuration applies to all HM users, including users declared directly in the standard `home-manager.users`. Check for fixed account/device settings and conflicts between multiple users.

## 4. Register and connect packages

1. No registration is needed: `modules/default.nix` imports every directory under `modules/` from the directory listing (static, independent of config). Do not put non-module directories there. Its `legacyOrder` only keeps the import order of the existing modules (module order decides the order of list definitions and thus the consumers' drvPaths); new modules need no entry.
2. For normal packages, use the consuming host's `pkgs`.
3. Only when a custom derivation / override is needed, create `packages/by-name/<first-2-letters>/<name>/package.nix`, as in nixpkgs. Registration is automatic, and editing `packages/default.nix` is not needed. Builders that need consumer inputs take the curried form `{ deps }: { args }: ...`; when overriding a nixpkgs package of the same name, reference `pkgs.<name>`.
4. For external repos that have `package.nix` at the root, add a `flake = false` input to `flake.nix` and add one line to the external input table in `packages/default.nix`.
5. Use custom packages through the module argument `attopkgs`. Do not `callPackage` directly inside feature modules. Leave supplying them to `nixosModules.default` in `flake.nix`.
6. Pin fetched artifacts with a flake input or a version/hash inside the package. Do not use fetches that hit the network at evaluation time, such as `builtins.fetchTarball` or `fetchGit`, inside modules or packages. External repos are `flake = false` inputs even when a hash is available. Consumer-specific archive URLs, hashes, etc. stay on the consumer side.
7. Do not make evaluation depend on package contents (no IFD). Do not read store packages with `lib.importTOML "${pkgs.<x>}/..."` or `builtins.readFile`; copy the source of the needed configuration files into the repo, reference it with `./`, and handle updates with `update-packages`. Keep all packages covered by `flake check --no-build`.

Normal feature additions do not need individual module exports or separate HM loading added to `flake.nix`: `flake.modules.homeManager.<name>` and the checks are generated from the directories in `modules/`.
Do not mix updates of the Home Manager revision, the shared nixpkgs or the consumer nixpkgs into feature additions.

## 5. Evaluate

`tests/default.nix` holds evaluation-only module tests as flake checks (`checks.x86_64-linux.*`): `modules-disabled` (importing `nixosModules.default` with nothing enabled changes nothing in a minimal system; intentional differences go into its `allowed` list), `module-<name>` (the minimal system with only that feature enabled evaluates; public services are enabled through the registry with `host` = the test hostName), `home-manager-<name>` (standalone HM with `homeManager.<name>`) and `home-manager-unknown-option`. The per-module lists come from the directories in `modules/`, so a new module is tested automatically; add values to `tests/fixtures.nix` only when the feature has options that are required when enabled. Skipped directories are listed in `skip` / `hmSkip` with the reason. Go custom packages run each package's tests and `go vet` inside the build. Run the following from the repository root.

```sh
nix flake check --no-build 'path:.'
nix eval --raw 'path:.#checks.x86_64-linux.module-<name>.drvPath' # one check, in its own process
nix eval --raw 'path:.#packages.x86_64-linux.<name>.drvPath' # a changed package
```

- Evaluating every check in one process does not free memory between checks: `nix flake check --no-build` peaks at about 33 GB, while one check per process peaks at about 1.1 GB. On small hosts (the hermes container, CI with 6 GiB) evaluate the checks one per process, and run the full `nix flake check` only on attodesk.

- `nix flake check --no-build` must pass even when the packages are not in the store (§4-7).
- Confirm, by evaluating on the consumer side with `--override-input`, that feature settings and dependencies do not become enabled on their own while the feature is disabled, and that a single enable brings in the required configuration.
- `path:` evaluation includes untracked files. Do not change the existing staging state for verification.
- Use `--no-write-lock-file` for normal flake evaluation. Do not do lock updates, rebuilds, switches or pushes that were not requested.

Successful evaluation does not guarantee a successful build or working behavior on real machines. Check boot, PAM, desktop startup, user services, external devices, etc. separately after migrating the consumer.

## 6. Check documentation and the diff

- Update the feature list, scope, dependencies, custom options and consumer assumptions in `README.md`.
- Document the module's package/version, settings, configuration examples and operational constraints on the corresponding Wiki page; do not add duplicate per-feature docs. Document the implementation and supply contract of custom packages in `packages/README.md`. Do not leave work history or success logs in docs.
- Write version, revision and hash in only one place (the input in `flake.nix`, `package.nix`, or the external input table in `packages/default.nix`). In README and docs, write 「`flake.lock`／`package.nix`を参照」 ("see `flake.lock` / `package.nix`") and do not copy concrete values.
- Check that the consumer can override defaults without `mkForce` (§2) and that defaults that widen privilege or exposure are opt-in (§2).
- Check `git diff --check` and the diff of the target files, and confirm there are no unrelated changes or credentials. For new files, also check the untracked contents.
- In the completion report, briefly state the changed features and files, the verification that was run, and what remains unverified. State explicitly if consumer migration or applying to real machines was not done.

## 7. CI workflows and CI scripts

Follow these rules when changing `.forgejo/workflows/` and `packages/by-name/at/attos-ci/`.

- Pin every `nix run` and `nix shell` to the nixpkgs in `flake.lock` with `--inputs-from .`; do not use unpinned inputs via the registry. Consumers run `attos-ci` through their lock (`nix run --inputs-from . attos-nix-modules#attos-ci`), so it follows the revision they adopted; do not add a second rev pin for it. Pin tools from other repos by rev and bump them in the weekly update PR.
- Pass tokens only in the `env:` of the step that uses them; do not put them in workflow-wide or job-wide env. Do not embed them in URLs (`https://bot:$TOKEN@...`); pass them via `git -c http.extraHeader=...` or `GIT_ASKPASS`. Do not copy masked log output (`***`) into code.
- Add `timeout-minutes` to every job. Serialize jobs that evaluate multiple hosts with `needs:` or `concurrency`, and do not run them at the same time on the shared runner.
- When CI holds a fixed list of consumer hosts, make it overridable through `workflow_dispatch` inputs. `.forgejo/consumers` lists consumer repos (`owner/repo`); `attos-ci check-consumers` evaluates every name in each repo's `nixosConfigurations`, so adding or retiring a consumer host needs no edit here (`owner/repo:host,host` limits a line to those hosts).
- Evaluate flake checks one attribute per `nix eval` process (`attos-ci check-flake`), not with one `nix flake check`: evaluation-only checks add up beyond the runner's 6 GiB in one process.
- CI fails on evaluation warnings (`evaluation warning:` / `trace: warning:`) that `.forgejo/known-warnings` does not list. Fix new warnings where possible; otherwise add one fixed substring of the normalised message with a comment above it saying where it comes from and when to remove it. Remove lines that the notice reports as unused. Consumers keep their own `.forgejo/known-warnings` and run `attos-ci check-hosts` in their pr-check.
- Workflows add the private binary cache (`https://cache.attodao.cc/ci`, Attic on attobox) as an extra substituter in `NIX_CONFIG`, and push the fetched flake input sources to it with `attos-ci cache-push` (secret `ATTIC_TOKEN`, push/pull on the `ci` cache only). Never make a job depend on the cache: without the token it skips, and a failed push only warns.
- Version bumps of custom packages are built in the weekly `update/packages` job (evaluation never runs a build or installCheck). A bump that fails to build is reverted, listed in the PR body and fails the job; port or pin it by hand.
- The option tables of the wiki module pages (between `<!-- attos-options:begin -->` and `<!-- attos-options:end -->`) are generated by `attos-ci docs` and pushed by `.forgejo/workflows/docs.yml` after every push to main, with the secret `WIKI_TOKEN` (a token of the bot account `nix-bot`, which has write access to this repo, with scope `write:repository`; the user creates it in Forgejo and stores it as an Actions secret of this repo, nobody pastes it in chat). Do not edit those tables by hand: fix the option's `description`, type or `defaultText` in the module. Text outside the markers stays hand-written.
