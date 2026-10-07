#!/usr/bin/env python3
import base64
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import stat
import tempfile
from unittest.mock import patch

source = Path(__file__).with_name("wireguard-runtime.py")
spec = importlib.util.spec_from_file_location("wireguard_runtime", source)
wg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wg)


def rejected(call):
    try:
        call()
    except (ValueError, RuntimeError):
        return
    raise AssertionError("Invalid input was accepted")


with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    keys = {}
    for name, value in (("server-private", 1), ("server-public", 2), ("client-private", 3), ("client-public", 4)):
        keys[name] = root / name
        keys[name].write_text(base64.b64encode(bytes([value]) * 32).decode() + "\n")
    metadata = {
        "interface": "wg0", "listenPort": 51820, "namespace": None,
        "privateKeyFile": str(keys["server-private"]), "serverPublicKeyFile": str(keys["server-public"]),
        "clientDns": "10.252.0.1", "clientEndpoint": "vpn.example.test:51820",
        "clientConfigsDirectory": str(root / "configs"),
        "clients": [{"name": "phone", "address": "10.252.0.2", "privateKeyFile": str(keys["client-private"]), "publicKeyFile": str(keys["client-public"])}],
    }
    configs = root / "configs"
    configs.mkdir()
    (configs / "stale.conf").write_text("old")
    (configs / "unmanaged.txt").write_text("keep")
    wg.sync_configs(metadata)
    target = configs / "phone.conf"
    old = target.read_bytes()
    assert b"Address = 10.252.0.2/32" in old and b"Endpoint = vpn.example.test:51820" in old
    assert stat.S_IMODE(target.stat().st_mode) == 0o600
    wg.sync_configs({**metadata, "clientConfigMode": "0660"})
    assert stat.S_IMODE(target.stat().st_mode) == 0o660
    wg.sync_configs({**metadata, "clientConfigMode": "0640"})
    assert stat.S_IMODE(target.stat().st_mode) == 0o640
    for mode in ("0644", "0777", "bad", 0o600):
        rejected(lambda: wg.sync_configs({**metadata, "clientConfigMode": mode}))
        assert target.read_bytes() == old
        assert stat.S_IMODE(target.stat().st_mode) == 0o640
    wg.sync_configs(metadata)
    assert stat.S_IMODE(target.stat().st_mode) == 0o600
    assert not (configs / "stale.conf").exists() and (configs / "unmanaged.txt").read_text() == "keep"
    keys["client-private"].write_text("invalid")
    rejected(lambda: wg.sync_configs(metadata))
    assert target.read_bytes() == old
    keys["client-private"].write_text(base64.b64encode(bytes([3]) * 32).decode())
    rejected(lambda: wg.clients({**metadata, "clients": metadata["clients"] * 2}))
    rejected(lambda: wg.clients({**metadata, "clients": [{**metadata["clients"][0], "name": "../escape"}]}))
    rejected(lambda: wg.sync_configs({**metadata, "clientDns": "10.252.0.1\nInjected"}))
    for endpoint in ("bad:0", "bad:65536", "bad\nname:51820"):
        rejected(lambda: wg.checked_endpoint(endpoint))
    assert wg.checked_endpoint("[2001:db8::1]:51820") == "[2001:db8::1]:51820"

    calls = []
    def fake_run(command, **kwargs):
        path = Path(command[-1])
        assert stat.S_IMODE(path.stat().st_mode) == 0o600
        text = path.read_text()
        assert "ListenPort = 51820" in text and "AllowedIPs = 10.252.0.2/32" in text
        calls.append((command, path))
        return b""
    with patch.object(wg, "run", fake_run), patch.dict(os.environ, {"RUNTIME_DIRECTORY": directory}):
        wg.sync_peers(metadata)
        wg.sync_peers({**metadata, "namespace": "private-net"})
    assert calls[0][0][:3] == ["wg", "syncconf", "wg0"]
    assert calls[1][0][:7] == ["ip", "netns", "exec", "private-net", "wg", "syncconf", "wg0"]
    assert all(not path.exists() for _, path in calls)

    def failed_run(command, **kwargs):
        calls.append((command, Path(command[-1])))
        raise RuntimeError("fake wg failure")
    with patch.object(wg, "run", failed_run):
        rejected(lambda: wg.sync_peers(metadata))
    assert not calls[-1][1].exists()
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        wg.qr(metadata, ["--list"])
    assert output.getvalue() == "phone\n"
    rejected(lambda: wg.qr(metadata, ["../escape"]))
    binary = io.BytesIO()
    stream = io.TextIOWrapper(binary)
    with contextlib.redirect_stdout(stream), patch.object(wg, "run", return_value=b"fake-qr") as run:
        wg.qr(metadata, ["phone"])
        assert run.call_args.args[0] == ["qrencode", "-t", "ANSIUTF8"]
        assert run.call_args.kwargs["input"] == old
        assert binary.getvalue() == b"fake-qr"
print("wireguard runtime: OK")
