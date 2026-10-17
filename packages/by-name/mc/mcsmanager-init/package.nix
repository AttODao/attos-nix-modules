{
  build-go-program,
  mcsmanager,
  nodejs,
}:
(build-go-program {
  pname = "mcsmanager-init";
  src = ./.;
  meta.description = "Runtime configuration and initial administrator bootstrap for native MCSManager";
}).overrideAttrs
  (old: {
    # The smoke test starts the bundled release against temp state and fake credentials.
    nativeCheckInputs = [ nodejs ];
    env = old.env // {
      MCSMANAGER_PACKAGE = "${mcsmanager}/share/mcsmanager";
    };
  })
