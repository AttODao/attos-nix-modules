// Usage: node test-smoke.cjs PACKAGE/share/mcsmanager [bootstrap.cjs]
// Only test children, fake credentials, temp state and ephemeral loopback ports.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const net = require("node:net");
const { randomBytes } = require("node:crypto");
const { spawn } = require("node:child_process");
const { once } = require("node:events");
const { bootstrap } = require(process.argv[3] || "./bootstrap.cjs");
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function freePort() {
  const server = net.createServer();
  server.listen(0, "127.0.0.1"); await once(server, "listening");
  const port = server.address().port;
  await new Promise(resolve => server.close(resolve));
  return port;
}
async function eventually(check, children) {
  for (let i = 0; i < 100; i++) {
    assert(children.every(child => child.exitCode === null), "Test process exited before ready");
    try { if (await check()) return; } catch (_) { }
    await delay(100);
  }
  throw new Error("MCSManager test readiness timed out");
}
async function main() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "mcsm-smoke-"));
  const children = [];
  const key = randomBytes(32).toString("hex");
  const logs = { web: "", daemon: "" };
  try {
    const credentials = path.join(tmp, "credentials"); fs.mkdirSync(credentials);
    fs.writeFileSync(path.join(credentials, "daemon-key"), key, { mode: 0o600 });
    const cfg = { dataDir: path.join(tmp, "state"), packageDir: path.resolve(process.argv[2]),
      listenAddress: "127.0.0.1", hostname: "localhost", webPort: await freePort(),
      daemonPort: await freePort(), standalone: true, initialAdmin: false };
    assert.notEqual(cfg.webPort, cfg.daemonPort);
    assert(!fs.existsSync(path.join(cfg.packageDir, "web/node_modules")));
    assert(!fs.existsSync(path.join(cfg.packageDir, "daemon/node_modules")));
    bootstrap("daemon", cfg, credentials); bootstrap("web", cfg, credentials);
    for (const kind of ["daemon", "web"]) {
      const home = path.join(tmp, `${kind}-home`); fs.mkdirSync(home);
      const child = spawn(process.execPath, [path.join(cfg.packageDir, kind, "app.js")], {
        cwd: path.join(cfg.dataDir, kind),
        // No host env/secrets/proxy settings; any Docker lookup targets a nonexistent temp socket.
        env: { HOME: home, TMPDIR: tmp, LANG: "C.UTF-8", DOCKER_HOST: `unix://${tmp}/no-docker.sock` },
        stdio: ["ignore", "pipe", "pipe"]
      });
      child.on("error", error => { logs[kind] += error.message; });
      for (const stream of [child.stdout, child.stderr]) stream.on("data", data => { logs[kind] += data; });
      children.push(child);
    }
    const daemonUrl = `http://127.0.0.1:${cfg.daemonPort}`;
    const webUrl = `http://127.0.0.1:${cfg.webPort}`;
    await eventually(async () => {
      const response = await fetch(`${daemonUrl}/daemon/socket.io/?EIO=4&transport=polling`, { signal: AbortSignal.timeout(1000) });
      return response.ok && (await response.text()).startsWith('0{"sid":');
    }, children);
    await eventually(async () => {
      const response = await fetch(`${webUrl}/api/auth/status`, { signal: AbortSignal.timeout(1000) });
      const body = await response.json();
      return response.ok && (body.data || body).isInstall === false;
    }, children);
    const page = await fetch(webUrl).then(response => { assert(response.ok); return response.text(); });
    const asset = page.match(/(?:src|href)="([^" ]*\/assets\/[^" ]+\.js)"/);
    assert(asset, "Bundled frontend asset reference missing");
    const response = await fetch(new URL(asset[1], webUrl));
    assert(response.ok && (await response.text()).length > 100, "Bundled frontend asset not served");
    await eventually(() => logs.web.includes("key validation successful"), children);
    // Check both captured stdio and the upstream file log, not just journald output.
    for (const kind of ["web", "daemon"]) {
      assert(!logs[kind].includes(key), "Fake authentication key leaked to stdio");
      const logDir = path.join(cfg.dataDir, kind, "logs");
      for (const file of fs.readdirSync(logDir)) {
        assert(!fs.readFileSync(path.join(logDir, file), "utf8").includes(key), "Fake key leaked to a file log");
      }
    }
    console.log("MCSManager bundled release smoke: web/assets, daemon prefix, authenticated local node, no key logging OK");
  } catch (error) {
    // Only fake test state exists, but still redact its key from diagnostics.
    console.error((logs.daemon + logs.web).replaceAll(key, "[redacted]").slice(-3000));
    throw error;
  } finally {
    await Promise.all(children.map(async child => {
      if (!child.pid || child.exitCode !== null || child.signalCode !== null) return;
      const closed = once(child, "close");
      child.kill("SIGTERM");
      const force = setTimeout(() => child.kill("SIGKILL"), 3000);
      try { await closed; } finally { clearTimeout(force); }
    }));
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
