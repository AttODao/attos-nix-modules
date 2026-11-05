--!nonstrict
-- Bar widget: always shown; a dim glyph while nothing remote runs, otherwise a glyph
-- and the item count.
local lib = require("./lib.luau")

function update()
  noctalia.setUpdateInterval(3000)
  barWidget.setVisible(true)
  local doc = lib.read()
  if doc == nil then
    barWidget.setGlyph("server-off")
    barWidget.setText("")
    barWidget.setGlyphColor("error", "script")
    barWidget.setTooltip("attos-jobs-agentの状態を読めません（停止中？）")
    return
  end
  if #doc.items == 0 and not doc.paused then
    barWidget.setGlyph("server")
    barWidget.setText("")
    barWidget.setGlyphColor("on_surface_variant", "script")
    barWidget.setTooltip("他ホストからの作業はありません")
    return
  end
  barWidget.setGlyph(doc.paused and "player-pause" or "server-bolt")
  barWidget.setText(#doc.items > 0 and tostring(#doc.items) or "")
  if doc.preparingForShutdown then
    barWidget.setGlyphColor("error", "script")
  else
    barWidget.setGlyphColor("on_surface")
  end
  local rows = {}
  if doc.preparingForShutdown then
    table.insert(rows, { "電源オフ待ち", "下の作業の終了を待っています" })
  end
  if doc.paused then
    table.insert(rows, { "受付停止中", doc.pausedBy or "" })
  end
  for _, it in ipairs(doc.items) do
    table.insert(rows, { it.title or it.id, lib.meta(it) })
  end
  barWidget.setTooltip(rows)
end

function onClick()
  noctalia.togglePanel(lib.panelId)
end
