{ python3Packages }:
let
  # AtCoder now reports memory limits in MiB; keep the host package pin.
  apiClient = python3Packages.online-judge-api-client.overridePythonAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace onlinejudge/service/atcoder.py \
        --replace-fail \
          "^(メモリ制限|Memory Limit): ([0-9.]+) (KB|MB)" \
          "^(メモリ制限|Memory Limit): ([0-9.]+) (KB|MB|MiB)" \
        --replace-fail \
          "elif memory_limit_unit == 'MB':" \
          "elif memory_limit_unit in ('MB', 'MiB'):"
    '';
  });
in
python3Packages.online-judge-tools.overridePythonAttrs (old: {
  dependencies = map (
    dependency: if (dependency.pname or "") == "online-judge-api-client" then apiClient else dependency
  ) old.dependencies;
})
