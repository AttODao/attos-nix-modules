// No service or host-state manipulation: all files are confined to a temp directory.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const { bootstrap } = require("./bootstrap.cjs");
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "mcsm-bootstrap-"));
try {
  const credentials = path.join(tmp, "credentials");
  fs.mkdirSync(credentials);
  const key = "0123456789abcdef".repeat(4);
  fs.writeFileSync(path.join(credentials, "daemon-key"), key + "\n");
  const admin = { userName: "admin", passWord: "$2b$10$" + "a".repeat(53) };
  fs.writeFileSync(path.join(credentials, "initial-admin"), JSON.stringify(admin));
  const cfg = { dataDir: path.join(tmp, "state"), packageDir: path.join(tmp, "package"),
    listenAddress: "10.250.0.1", hostname: "mine.example.test", webPort: 23333,
    daemonPort: 24444, standalone: false, initialAdmin: true };
  const read = file => JSON.parse(fs.readFileSync(path.join(cfg.dataDir, file), "utf8"));
  bootstrap("daemon", cfg, credentials);
  bootstrap("web", cfg, credentials);
  assert.equal(read("daemon/data/Config/global.json").key, key);
  assert.equal(read("daemon/data/Config/global.json").ip, cfg.listenAddress);
  assert.equal(read("daemon/data/Config/global.json").prefix, "/daemon/");
  const node = read("web/data/RemoteServiceConfig/00000000000000000000000000000001.json");
  assert.equal(node.apiKey, key);
  assert.equal(node.ip, cfg.listenAddress);
  assert.equal(node.prefix, "/daemon/");
  assert.deepEqual(node.remoteMappings, [{
    from: { ip: cfg.hostname, port: 443, prefix: "" },
    to: { ip: `https://${cfg.hostname}`, port: 443, prefix: "/daemon/" }
  }]);
  assert.equal(read("web/data/SystemConfig/config.json").reverseProxyMode, true);
  const users = path.join(cfg.dataDir, "web/data/User");
  const userFile = path.join(users, fs.readdirSync(users)[0]);
  const user = JSON.parse(fs.readFileSync(userFile));
  assert.equal(user.permission, 10);
  assert.equal(user.passWordType, 1);
  assert.equal(user.passWord, admin.passWord);
  assert.equal(fs.statSync(userFile).mode & 0o777, 0o600);
  assert.equal(fs.statSync(path.join(cfg.dataDir, "daemon/data/Config/global.json")).mode & 0o777, 0o600);
  // Preserve users, custom configuration, other nodes and instance/game data.
  const custom = path.join(cfg.dataDir, "web/data/SystemConfig/config.json");
  const config = JSON.parse(fs.readFileSync(custom)); config.language = "ja_jp";
  fs.writeFileSync(custom, JSON.stringify(config));
  const instance = path.join(cfg.dataDir, "daemon/data/world.txt");
  fs.writeFileSync(instance, "existing game data");
  const existingNode = path.join(cfg.dataDir, "web/data/RemoteServiceConfig/external.json");
  fs.writeFileSync(existingNode, '{"ip":"other"}');
  fs.writeFileSync(path.join(credentials, "initial-admin"), "invalid contents are ignored once users exist");
  const nextKey = "f".repeat(64);
  fs.writeFileSync(path.join(credentials, "daemon-key"), nextKey);
  bootstrap("daemon", cfg, credentials); bootstrap("web", cfg, credentials);
  assert.deepEqual(JSON.parse(fs.readFileSync(userFile)), user);
  assert.equal(read("web/data/SystemConfig/config.json").language, "ja_jp");
  assert.equal(read("daemon/data/Config/global.json").key, nextKey);
  assert.equal(read("web/data/RemoteServiceConfig/00000000000000000000000000000001.json").apiKey, nextKey);
  assert.equal(fs.readFileSync(instance, "utf8"), "existing game data");
  assert.equal(fs.readFileSync(existingNode, "utf8"), '{"ip":"other"}');
  cfg.standalone = true; cfg.listenAddress = "127.0.0.1";
  bootstrap("web", cfg, credentials);
  assert.equal(read("web/data/SystemConfig/config.json").reverseProxyMode, false);
  assert.deepEqual(read("web/data/RemoteServiceConfig/00000000000000000000000000000001.json").remoteMappings, []);
  // Invalid credentials fail without leaking secret-containing parser messages.
  const settings = path.join(tmp, "settings.json");
  fs.writeFileSync(settings, JSON.stringify(cfg));
  const secret = 'SECRET-INVALID-KEY{"';
  fs.writeFileSync(path.join(credentials, "daemon-key"), secret);
  const result = spawnSync(process.execPath, [path.join(__dirname, "bootstrap.cjs"), "daemon", settings],
    { env: { ...process.env, CREDENTIALS_DIRECTORY: credentials }, encoding: "utf8" });
  assert.equal(result.status, 1);
  assert(!result.stdout.includes(secret) && !result.stderr.includes(secret));
  assert(!result.stderr.includes(nextKey));
  fs.writeFileSync(path.join(credentials, "daemon-key"), key);
  const daemonConfig = path.join(cfg.dataDir, "daemon/data/Config/global.json");
  fs.unlinkSync(daemonConfig); fs.symlinkSync(instance, daemonConfig);
  assert.throws(() => bootstrap("daemon", cfg, credentials));
  assert.equal(fs.readFileSync(instance, "utf8"), "existing game data");
  // Fresh state rejects plaintext initial administrator passwords.
  cfg.dataDir = path.join(tmp, "fresh");
  fs.writeFileSync(path.join(credentials, "initial-admin"), JSON.stringify({ userName: "admin", passWord: "plaintext" }));
  assert.throws(() => bootstrap("web", cfg, credentials));
  assert.deepEqual(fs.readdirSync(path.join(cfg.dataDir, "web/data/User")), []);
  console.log("MCSManager runtime bootstrap: OK");
} finally { fs.rmSync(tmp, { recursive: true, force: true }); }
