if length == $count and all(.[]; type == "object") then
  .[0] as $defaults
  | (.[1] // {}) as $user
  | ($defaults * $user)
  | if (.packages | type) == "array" then
      # Preserve user package order, append missing module defaults, and remove the retired source.
      .packages = (
        (($user.packages // []) + ($defaults.packages // []))
        | reduce .[] as $package (
            [];
            if any(.[]; . == $package) then . else . + [$package] end
          )
        | map(select(
            if type == "string" then
              test("^/nix/store/[a-z0-9]{32}-context-mode-1\\.0\\.169/lib/context-mode$") | not
            else true end
          ))
      )
    else . end
else
  error("Pi settings must be one JSON object")
end
