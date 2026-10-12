## Mermaid Studio over SSH

When `mermaid_diagram` is available and Pi runs on a remote server, use
`create` / `update` to obtain the workbench URL. Avoid `open` / `/mermaid`
on headless servers: they launch a browser on the server, not the SSH client.

Whenever showing a workbench URL, also show a forwarding command to run on the
user's **local computer**, using the actual remote port from that URL:

```sh
ssh -N -T -o ExitOnForwardFailure=yes -L 127.0.0.1:LOCAL_PORT:127.0.0.1:REMOTE_PORT user@server
```

Replace the port placeholders with numbers and use the user's known SSH
destination/alias (and SSH port/jump options); ask if the destination is unknown.
The server listens on `127.0.0.1` with a dynamically allocated port: **37421 is
not a default**. LOCAL_PORT can equal REMOTE_PORT if unused locally. Show the
local browser URL too, changing only its port and preserving the full
`/t/TOKEN/` path and `?id=...` query. The token grants access to project diagrams
and edits: never write it into files, logs, or public reports. Keep Pi and the
SSH tunnel running; a new workbench/session may need a new port and token.
Do not open firewall ports, bind publicly, or use `ssh -g`.
`ExitOnForwardFailure` checks tunnel setup, not remote workbench readiness.
