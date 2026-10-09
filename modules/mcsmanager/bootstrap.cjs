// Runtime-only initialization; neither credentials nor mutable state enter the Nix store.
const fs = require("node:fs");
const path = require("node:path");
const { randomUUID } = require("node:crypto");

function readObject(file) {
  const stat = fs.lstatSync(file);
  if (!stat.isFile()) throw new Error("State is not a regular file");
  const value = JSON.parse(fs.readFileSync(file, "utf8"));
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid object");
  return value;
}
function load(file) { return fs.existsSync(file) ? readObject(file) : {}; }
function save(file, value) {
  if (fs.existsSync(file)) readObject(file); // Do not follow a state-file symlink.
  fs.mkdirSync(path.dirname(file), { recursive: true, mode: 0o700 });
  const temp = `${file}.${randomUUID()}.tmp`;
  try {
    fs.writeFileSync(temp, JSON.stringify(value), { mode: 0o600, flag: "wx" });
    fs.renameSync(temp, file);
  } finally { if (fs.existsSync(temp)) fs.unlinkSync(temp); }
}
function link(target, dest) {
  // lstat also sees dangling symlinks after an old package is garbage-collected.
  try {
    if (!fs.lstatSync(dest).isSymbolicLink()) throw new Error("Asset path is not a symlink");
    fs.unlinkSync(dest);
  } catch (error) { if (error.code !== "ENOENT") throw error; }
  fs.symlinkSync(target, dest);
}
function bootstrap(kind, cfg, credentials) {
  const key = fs.readFileSync(path.join(credentials, "daemon-key"), "utf8").trim();
  if (!/^[A-Za-z0-9_-]{32,256}$/.test(key)) throw new Error("Invalid daemon key");
  const root = path.join(cfg.dataDir, kind);
  fs.mkdirSync(root, { recursive: true, mode: 0o700 });
  for (const dir of ["data", "logs"]) fs.mkdirSync(path.join(root, dir), { recursive: true, mode: 0o700 });
  if (kind === "daemon") {
    const file = path.join(root, "data/Config/global.json");
    save(file, { ...load(file), version: 2, ip: cfg.listenAddress, port: cfg.daemonPort,
      prefix: "/daemon/", key, ssl: false, updateSourceUrl: "" });
    fs.mkdirSync(path.join(root, "lib"), { recursive: true, mode: 0o700 });
    for (const tool of ["pty", "file_zip", "7z"]) {
      const name = `${tool}_linux_${process.arch === "arm64" ? "arm64" : "x64"}`;
      link(path.join(cfg.packageDir, "daemon/lib", name), path.join(root, "lib", name));
    }
  } else if (kind === "web") {
    const file = path.join(root, "data/SystemConfig/config.json");
    save(file, { ...load(file), httpIp: cfg.listenAddress, httpPort: cfg.webPort, prefix: "",
      ssl: false, reverseProxyMode: !cfg.standalone, reverseProxyHeader: "X-Real-IP",
      crossDomain: false, updateSourceUrl: "" });
    link(path.join(cfg.packageDir, "web/public"), path.join(root, "public"));
    const nodeFile = path.join(root, "data/RemoteServiceConfig/00000000000000000000000000000001.json");
    const remoteMappings = cfg.standalone ? [] : [{
      from: { ip: cfg.hostname, port: 443, prefix: "" },
      to: { ip: `https://${cfg.hostname}`, port: 443, prefix: "/daemon/" }
    }];
    save(nodeFile, { ...load(nodeFile), ip: cfg.listenAddress, port: cfg.daemonPort,
      prefix: "/daemon/", remarks: "Local native daemon", apiKey: key, remoteMappings });
    const users = path.join(root, "data/User");
    fs.mkdirSync(users, { recursive: true, mode: 0o700 });
    if (cfg.initialAdmin && !fs.readdirSync(users).some(name => name.endsWith(".json"))) {
      const admin = readObject(path.join(credentials, "initial-admin"));
      if (typeof admin.userName !== "string" || !admin.userName.trim() || admin.userName.length > 64 ||
          /[\x00-\x1f\x7f]/.test(admin.userName) ||
          typeof admin.passWord !== "string" || !/^\$2[aby]\$\d{2}\$[./A-Za-z0-9]{53}$/.test(admin.passWord)) {
        throw new Error("Invalid initial administrator");
      }
      const uuid = randomUUID().replaceAll("-", "");
      save(path.join(users, `${uuid}.json`), { uuid, userName: admin.userName, passWord: admin.passWord,
        passWordType: 1, permission: 10, isInit: false, instances: [], apiKey: "", secret: "", open2FA: false,
        registerTime: new Date().toISOString(), loginTime: "", salt: "" });
    }
  } else throw new Error("Invalid component");
}
if (require.main === module) {
  try {
    bootstrap(process.argv[2], readObject(process.argv[3]), process.env.CREDENTIALS_DIRECTORY);
  } catch (_) {
    // Upstream JSON/parser exceptions may contain secret contents. Never print them.
    console.error("MCSManager runtime initialization failed; check credential formats and state permissions.");
    process.exitCode = 1;
  }
}
module.exports = { bootstrap };
