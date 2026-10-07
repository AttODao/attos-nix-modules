#!/usr/bin/env python3
import http.client
import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import threading

scripts = Path(__file__).parent
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    docker = root / "docker"
    docker.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
log = pathlib.Path(os.environ["FAKE_LOG"])
with log.open("a") as stream:
    stream.write(json.dumps(args) + "\\n")
if args[0] == "info":
    print(os.environ["FAKE_STATE"] if "LocalNodeState" in args[-1] else os.environ["FAKE_CONTROL"])
elif args[:2] == ["swarm", "init"]:
    print("init output with fake-sensitive-token")
elif args[:2] == ["swarm", "join-token"]:
    if os.environ.get("FAKE_TOKEN_EMPTY") != "yes": print("fake-sensitive-token")
elif args[:2] == ["network", "inspect"]:
    sys.exit(1)
elif args[:2] == ["network", "create"]:
    sys.exit(0 if os.environ.get("FAKE_NETWORK") == "ok" else 1)
''')
    docker.chmod(0o755)
    for command, code in (("sleep", "exit 0"), ("curl", '[ "$FAKE_CURL" = ok ]')):
        executable = root / command
        executable.write_text("#!/bin/sh\n" + code + "\n")
        executable.chmod(0o755)
    log = root / "calls"
    environment = {**os.environ, "PATH": str(root) + os.pathsep + os.environ["PATH"], "FAKE_LOG": str(log), "FAKE_STATE": "inactive", "FAKE_CONTROL": "true", "FAKE_NETWORK": "ok", "FAKE_CURL": "ok"}
    def run(*arguments, **overrides):
        log.write_text("")
        return subprocess.run(["bash", str(scripts / "swarm.sh"), *map(str, arguments)], env={**environment, **overrides}, capture_output=True, text=True)
    def calls():
        return [json.loads(line) for line in log.read_text().splitlines()]

    token = root / "private" / "worker-token"
    result = run("manager", "10.250.0.1", token)
    assert result.returncode == 0 and "fake-sensitive-token" not in result.stdout + result.stderr
    assert token.read_text().strip() == "fake-sensitive-token" and stat.S_IMODE(token.stat().st_mode) == 0o600
    old = token.read_bytes()
    result = run("manager", "10.250.0.1", token, FAKE_STATE="active", FAKE_TOKEN_EMPTY="yes")
    assert result.returncode != 0 and token.read_bytes() == old
    assert list(token.parent.glob("worker-token.*")) == []
    result = run("manager", "10.250.0.1", token, FAKE_STATE="active", FAKE_CONTROL="false")
    assert result.returncode != 0 and not any(args[:2] == ["swarm", "init"] for args in calls())
    assert run("worker", "10.250.0.1:2377", token, FAKE_CONTROL="false").returncode == 0
    assert ["swarm", "join", "--token", "fake-sensitive-token", "10.250.0.1:2377"] in calls()
    assert run("worker", "10.250.0.1:2377", token, FAKE_STATE="active", FAKE_CONTROL="true").returncode != 0
    assert run("worker", "10.250.0.1:2377", token, FAKE_STATE="active", FAKE_CONTROL="false").returncode == 0
    assert not any(args[:2] == ["swarm", "join"] for args in calls())
    marker = root / "ready" / "traefik-network-ready"
    assert run("network", "10.251.0.0/24", "10.251.0.1", marker).returncode == 0
    assert marker.read_bytes() == b""
    assert ["network", "create", "--driver", "overlay", "--attachable", "--subnet", "10.251.0.0/24", "--gateway", "10.251.0.1", "traefik"] in calls()
    assert run("network", "10.251.0.0/24", "10.251.0.1", root / "absent", FAKE_NETWORK="bad").returncode != 0
    assert not (root / "absent").exists()
    assert run("wait", "http://manager/traefik-network-ready").returncode == 0
    assert run("wait", "http://manager/traefik-network-ready", FAKE_CURL="bad").returncode != 0

    # Fetch never publishes a failed/invalid response over the existing credential.
    curl = root / "curl"
    curl.write_text('''#!/bin/sh
printf '%s\\n' "$@" > "$FAKE_LOG"
printf '%s\\n' "$FAKE_FETCH_TOKEN"
[ "$FAKE_CURL" = ok ]
''')
    fetched = root / "fetched" / "worker-token"
    fetched.parent.mkdir()
    fetched.write_text("old-token")
    for value, status in (("not-a-token", "ok"), ("SWMTKN-1-fake", "bad")):
        assert run("fetch", "http://manager:2378/worker-token", "10.250.0.2", fetched, FAKE_FETCH_TOKEN=value, FAKE_CURL=status).returncode != 0
        assert fetched.read_text() == "old-token"
        assert list(fetched.parent.glob("worker-token.*")) == []
    result = run("fetch", "http://manager:2378/worker-token", "10.250.0.2", fetched, FAKE_FETCH_TOKEN="SWMTKN-1-fake")
    assert result.returncode == 0 and "SWMTKN" not in result.stdout + result.stderr
    assert fetched.read_text() == "SWMTKN-1-fake\n"
    assert stat.S_IMODE(fetched.stat().st_mode) == 0o600
    assert log.read_text().splitlines() == ["--noproxy", "*", "--interface", "10.250.0.2", "-fsS", "--max-time", "2", "http://manager:2378/worker-token"]
    assert run("fetch", "http://manager:2378/worker-token", "", fetched, FAKE_FETCH_TOKEN="SWMTKN-1-fake").returncode == 0
    assert "--interface" not in log.read_text().splitlines()

    spec = importlib.util.spec_from_file_location("readiness", scripts / "readiness-server.py")
    readiness = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(readiness)
    server = readiness.ThreadingHTTPServer(("127.0.0.1", 0), readiness.ReadinessHandler)
    server.marker = marker
    marker.write_text("fake-sensitive-token")
    (marker.parent / "worker-token").write_text("fake-sensitive-token")
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        for path, status in (("/traefik-network-ready", 200), ("/", 404), ("/worker-token", 404), ("/../private/worker-token", 404)):
            connection = http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=2)
            connection.request("GET", path)
            response = connection.getresponse()
            body = response.read()
            assert response.status == status and b"fake-sensitive-token" not in body
            connection.close()
        marker.unlink()
        connection = http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=2)
        connection.request("GET", "/traefik-network-ready")
        assert connection.getresponse().status == 404
        connection.close()
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
    spec = importlib.util.spec_from_file_location("transport", scripts / "token-server.py")
    transport = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(transport)
    server = transport.ThreadingHTTPServer(("127.0.0.1", 0), transport.TokenHandler)
    server.token = fetched
    server.marker = marker
    server.allowed_addresses = ["127.0.0.1"]
    marker.touch()
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    def request(path):
        connection = http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=2)
        connection.request("GET", path)
        response = connection.getresponse()
        result = response.status, response.read(), response.getheader("Cache-Control")
        connection.close()
        return result
    try:
        assert request("/worker-token") == (200, b"SWMTKN-1-fake\n", "no-store")
        assert request("/traefik-network-ready") == (200, b"", "no-store")
        for path in ("/", "/worker-token?x=1", "/../worker-token", "/worker-token/"):
            status, body, _ = request(path)
            assert status == 404 and b"SWMTKN" not in body
        fetched.unlink()
        assert request("/worker-token")[0] == 503
        marker.unlink()
        assert request("/traefik-network-ready")[0] == 503
        server.allowed_addresses = ["192.0.2.1"]
        for path in ("/worker-token", "/traefik-network-ready", "/"):
            assert request(path)[0] == 403
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
print("swarm operations, atomic fetch, safe readiness and restricted token transport: OK")
