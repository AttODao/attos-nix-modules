#!/usr/bin/env node
// node test-resources.mjs PI_ROOT MANIFEST_DIRECTORY...
// Use built HM manifest directories; all diagrams/state stay in a temp project.
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

const [piRoot, ...manifests] = process.argv.slice(2);
assert(piRoot && manifests.length, "Provide Pi root and built manifest directories");
const { discoverAndLoadExtensions } = await import(pathToFileURL(
  path.join(piRoot, "dist/core/extensions/loader.js"),
));
const temp = await fs.mkdtemp(path.join(os.tmpdir(), "pi-resources-test-"));
const agent = path.join(temp, "agent");
const project = path.join(temp, "project");
let mermaid;
try {
  await fs.mkdir(path.join(agent, "extensions"), { recursive: true });
  await fs.mkdir(project);
  const expected = [];
  for (const [i, directory] of manifests.entries()) {
    const manifest = JSON.parse(await fs.readFile(path.join(directory, "package.json"), "utf8"));
    assert.deepEqual(manifest.pi.skills, []);
    expected.push(...manifest.pi.extensions);
    await fs.symlink(directory, path.join(agent, "extensions", String(i)));
  }
  // Existing writable package settings must not be needed for autodiscovery.
  const loaded = await discoverAndLoadExtensions([], project, agent);
  assert.deepEqual(loaded.errors, []);
  assert.deepEqual(loaded.extensions.map(e => e.path).sort(), expected.sort());
  mermaid = loaded.extensions.find(e => e.tools.has("mermaid_diagram"));
  assert(mermaid, "Mermaid tool was not registered");
  const tool = mermaid.tools.get("mermaid_diagram").definition;
  const context = { cwd: project };
  const source = "flowchart LR\n  A[Client] --> B[Server]";
  const validated = await tool.execute("validate", { action: "validate", source }, undefined, undefined, context);
  assert(validated.details.ok);
  const created = await tool.execute("create", { action: "create", id: "smoke", source }, undefined, undefined, context);
  assert(created.details.ok);
  const url = new URL(created.details.url);
  assert(url.hostname === "127.0.0.1" && Number(url.port) > 0);
  assert(url.pathname.startsWith("/t/") && url.searchParams.get("id") === "smoke");
  assert((await fetch(url)).ok);
  assert(!(await fetch(url.origin)).ok, "Workbench must require its capability token");
  console.log("Pi resource autodiscovery and Mermaid validate/create/HTTP: OK (temp-only)");
} finally {
  for (const shutdown of mermaid?.handlers.get("session_shutdown") ?? []) {
    await shutdown({ type: "session_shutdown" }, { cwd: project });
  }
  await fs.rm(temp, { recursive: true, force: true });
}
