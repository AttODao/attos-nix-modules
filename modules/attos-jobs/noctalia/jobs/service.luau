--!nonstrict
-- Opens the panel once when a shutdown starts waiting for remote work, so the
-- user can stop it (or leave) before the local session is ended.
local lib = require("./lib.luau")

local shown = false

function update()
  noctalia.setUpdateInterval(2000)
  local doc = lib.read()
  local waiting = doc ~= nil and doc.preparingForShutdown and #doc.items > 0
  if waiting and not shown then
    shown = true
    noctalia.togglePanel(lib.panelId)
  elseif not waiting then
    shown = false
  end
end
