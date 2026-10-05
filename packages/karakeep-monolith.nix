{ pkgsStatic, coreutils }:
# monolith 2.10.1 treats fragment-only SVG USE references as remote assets
# and embeds the entire HTML document into each reference. Keep those local
# references intact so MathJax and inline SVG sprites remain renderable.
pkgsStatic.monolith.overrideAttrs (oldAttrs: {
  patches = (oldAttrs.patches or [ ]) ++ [ ./karakeep-monolith.patch ];

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    local_fragment_output="$(${coreutils}/bin/printf '%s' \
      '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"><defs><path id="icon" d="M0 0h1v1H0z"></path><path id="legacy" d="M0 0h2v2H0z"></path></defs><use href="#icon"></use><use xlink:href="#legacy"></use></svg>' \
      | "$out/bin/monolith" -q -e -M -b file:///tmp/monolith-test/page.html -)"

    case "$local_fragment_output" in
      *'href="#icon"'*'xlink:href="#legacy"'*) ;;
      *)
        echo "fragment-only SVG USE references were not preserved" >&2
        exit 1
        ;;
    esac

    external_reference_output="$(${coreutils}/bin/printf '%s' \
      '<svg xmlns="http://www.w3.org/2000/svg"><use href="icons.svg#icon"></use></svg>' \
      | "$out/bin/monolith" -q -e -M -b file:///tmp/monolith-test/page.html -)"

    case "$external_reference_output" in
      *'href="data:text/plain;base64,"'*) ;;
      *)
        echo "external SVG USE references no longer follow the existing processing path" >&2
        exit 1
        ;;
    esac

    default_navigation_output="$(${coreutils}/bin/printf '%s' \
      '<html><body><a href="#section">Section</a><h2 id="section">Section</h2></body></html>' \
      | "$out/bin/monolith" -q -e -M -b https://source.example/page -)"

    case "$default_navigation_output" in
      *'href="#section"'*) ;;
      *)
        echo "fragment navigation changed without an archive URL prefix" >&2
        exit 1
        ;;
    esac

    archive_test_output="$TMPDIR/00000000-0000-0000-0000-000000000000"
    archive_test_stderr="$TMPDIR/archive-navigation.stderr"
    ${coreutils}/bin/printf '%s' \
      '<html><head><base href="https://source.example/page"></head><body><a href="#section">Section</a><area href="#map"><a href="#">Placeholder</a><a href="#missing">Missing</a><a href="/other">Other</a><a href="https://outside.example/path#fragment">Outside</a><h2 id="section">Section</h2><div id="map"></div><svg xmlns="http://www.w3.org/2000/svg"><defs><path id="icon" d="M0 0h1v1H0z"></path></defs><use href="#icon"></use></svg></body></html>' \
      | MONOLITH_FRAGMENT_NAVIGATION_PREFIX='https://keep.example/api/assets/' \
        "$out/bin/monolith" -e -I -j -M -b https://source.example/page \
          -o "$archive_test_output" - 2>"$archive_test_stderr"

    archive_navigation_output="$(<"$archive_test_output")"
    for expected in \
      'href="https://keep.example/api/assets/00000000-0000-0000-0000-000000000000#section"' \
      'href="https://keep.example/api/assets/00000000-0000-0000-0000-000000000000#map"' \
      'href="https://keep.example/api/assets/00000000-0000-0000-0000-000000000000#missing"' \
      'href="#"' \
      'href="https://source.example/other"' \
      'href="https://outside.example/path#fragment"' \
      'href="#icon"'
    do
      case "$archive_navigation_output" in
        *"$expected"*) ;;
        *)
          echo "archive navigation output is missing: $expected" >&2
          exit 1
          ;;
      esac
    done

    case "$(<"$archive_test_stderr")" in
      *'Warning: fragment target not found: #missing'*) ;;
      *)
        echo "missing fragment target warning was not emitted" >&2
        exit 1
        ;;
    esac

    runHook postInstallCheck
  '';
})
