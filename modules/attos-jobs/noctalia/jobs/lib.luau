--!nonstrict
-- Shared helpers: read the agent's status file and call the attos-jobs CLI.
local cfg = require("./config.luau")

local M = {}

M.panelId = "attos/jobs:panel"

-- Returns the decoded status document, or nil when the agent is not running.
function M.read()
  local raw = noctalia.readFile(cfg.status)
  if raw == nil or raw == "" then
    return nil
  end
  local doc = noctalia.json.decode(raw)
  if type(doc) ~= "table" then
    return nil
  end
  if type(doc.items) ~= "table" then
    doc.items = {}
  end
  return doc
end

function M.age(since)
  if since == nil or since == 0 then
    return ""
  end
  local d = os.time() - since
  if d < 60 then
    return tostring(math.max(d, 0)) .. "秒"
  elseif d < 3600 then
    return tostring(math.floor(d / 60)) .. "分"
  elseif d < 48 * 3600 then
    return string.format("%d時間%d分", math.floor(d / 3600), math.floor(d % 3600 / 60))
  end
  return tostring(math.floor(d / 86400)) .. "日"
end

function M.mem(bytes)
  if bytes == nil or bytes == 0 then
    return ""
  end
  if bytes >= 1024 * 1024 * 1024 then
    return string.format("%.1fGiB", bytes / (1024 * 1024 * 1024))
  end
  return string.format("%dMiB", math.floor(bytes / (1024 * 1024)))
end

M.glyphs = {
  heavy = "cpu",
  ci = "git-branch",
  session = "terminal-2",
  unit = "server",
}

M.kindNames = {
  heavy = "heavy",
  ci = "CI",
  session = "リモートsession",
  unit = "サービス",
}

function M.from(it)
  if it.user ~= nil and it.user ~= "" then
    return it.user .. "@" .. (it.origin or "?")
  end
  return it.origin or ""
end

-- One-line summary used in tooltips and rows.
function M.meta(it)
  local parts = {}
  for _, p in ipairs({ M.kindNames[it.kind] or it.kind, M.from(it), M.age(it.sinceUnix), M.mem(it.memory), it.state or "" }) do
    if p ~= "" then
      table.insert(parts, p)
    end
  end
  return table.concat(parts, " · ")
end

-- Runs `attos-jobs <args...>` and calls done(ok, text) with its output.
function M.run(args, done)
  local argv = { cfg.bin }
  for _, a in ipairs(args) do
    table.insert(argv, a)
  end
  local started = noctalia.runAsync(argv, function(res)
    local text = (res.stdout or "") .. (res.stderr or "")
    if done then
      done(res.exitCode == 0, text)
    end
  end)
  if not started and done then
    done(false, "attos-jobs could not be started")
  end
end

return M
