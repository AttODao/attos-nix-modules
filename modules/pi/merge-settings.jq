if length == $count and all(.[]; type == "object") then
  reduce .[] as $settings ({}; . * $settings)
else
  error("Pi settings must be one JSON object")
end
# Previous shared versions registered this package string automatically.
# Managed manifests now own its extension/skills. Preserve explicit objects
# (including user filters), npm/git sources, and all unrelated packages.
| if (.packages | type) == "array" then
    .packages |= map(select(
      if type == "string" then
        test("^/nix/store/[a-z0-9]{32}-context-mode-1\\.0\\.169/lib/context-mode$") | not
      else true end
    ))
  else . end
