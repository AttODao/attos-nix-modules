: "${out:?out must be set}"
: "${CODE_SERVER_SOURCE:?CODE_SERVER_SOURCE must be set}"
: "${NERD_FONT_FILE:?NERD_FONT_FILE must be set}"
: "${NERD_FONT_CSS:?NERD_FONT_CSS must be set}"

runHook preInstall

mkdir -p "$out/bin" "$out/libexec/code-server"
cp -R "$CODE_SERVER_SOURCE/." "$out/libexec/code-server"
chmod -R u+w "$out/libexec/code-server"
ln -s ../libexec/code-server/bin/code-server "$out/bin/code-server"

web_font_directory="$out/libexec/code-server/src/browser/media"
font_file_name="${NERD_FONT_FILE##*/}"
install -m 0644 "$NERD_FONT_FILE" "$web_font_directory/$font_file_name"
woff2_compress "$web_font_directory/$font_file_name"
rm "$web_font_directory/$font_file_name"
install -m 0644 "$NERD_FONT_CSS" "$web_font_directory/nerd-font.css"

workbench_directory="$out/libexec/code-server/lib/vscode/out/vs/code/browser/workbench"
workbench_html="$workbench_directory/workbench.html"
workbench_css_href='{{WORKBENCH_WEB_BASE_URL}}/out/vs/code/browser/workbench/workbench.css'
nerd_font_css_href='{{BASE}}/_static/src/browser/media/nerd-font.css'
substituteInPlace "$workbench_html" \
  --replace-fail \
  "<link rel=\"stylesheet\" href=\"$workbench_css_href\">" \
  "<link rel=\"stylesheet\" href=\"$workbench_css_href\">
        <link rel=\"stylesheet\" href=\"$nerd_font_css_href\">"

runHook postInstall
