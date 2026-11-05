--!nonstrict
-- Panel: the remote work list with per-item stop, stop-all, pause/resume, and
-- the shutdown choices while a power-off waits for remote work.
local lib = require("./lib.luau")

local doc = nil
local confirm = nil -- id (or "all") waiting for the second click
local busy = false
local message = nil
local messageIsError = false

local render

local function load()
  doc = lib.read()
end

local function finish(ok, text, okText)
  busy = false
  confirm = nil
  messageIsError = not ok
  if ok then
    message = okText
  else
    message = text ~= "" and text or "失敗しました"
    noctalia.notifyError("attos-jobs", message)
  end
  load()
  render()
end

local function run(args, okText)
  busy = true
  message = "実行中…"
  messageIsError = false
  render()
  lib.run(args, function(ok, text)
    finish(ok, text, okText)
  end)
end

local function confirmOr(id, action)
  if confirm == id then
    action()
  else
    confirm = id
    render()
  end
end

local function itemRow(it)
  local stopText = confirm == it.id and "本当に停止" or "停止"
  return ui.row({ key = "row-" .. it.id, gap = 10, align = "center", padding = 8, radius = 8, fill = "surface_container_high/0.6" }, {
    ui.glyph({ name = lib.glyphs[it.kind] or "point", size = 18 }),
    ui.column({ gap = 2, flexGrow = 1 }, {
      ui.label({ text = it.title or it.id, fontWeight = "bold", maxLines = 1 }),
      ui.label({ text = lib.meta(it), fontSize = 11, color = "on_surface_variant", maxLines = 1 }),
      (it.detail ~= nil and it.detail ~= "") and ui.label({ text = it.detail, fontSize = 11, maxLines = 2 }) or nil,
    }),
    ui.button({
      text = stopText,
      variant = confirm == it.id and "destructive" or "outline",
      controlSize = "sm",
      enabled = not busy,
      tooltip = it.id,
      onClick = function()
        confirmOr(it.id, function()
          run({ "stop", it.id }, (it.title or it.id) .. " を停止しました")
        end)
      end,
    }),
  })
end

render = function()
  local children = {}
  local items = doc and doc.items or {}

  local header = {
    ui.label({ text = "他ホストからの作業" .. (doc and doc.host and (" (" .. doc.host .. ")") or ""), fontSize = 16, fontWeight = "bold", color = "primary", flexGrow = 1 }),
  }
  if doc ~= nil then
    table.insert(header, ui.button({
      text = doc.paused and "受付を再開" or "受付を停止",
      glyph = doc.paused and "player-play" or "player-pause",
      variant = "outline",
      controlSize = "sm",
      enabled = not busy,
      tooltip = doc.paused and "heavy jobとCI runnerの受付を再開します" or "新しいheavy jobを断り、CI runnerを止めます（実行中のCI jobは中断されます）",
      onClick = function()
        if doc.paused then
          run({ "resume" }, "受付を再開しました")
        else
          confirmOr("pause", function()
            run({ "pause" }, "受付を停止しました（再起動か「受付を再開」まで）")
          end)
        end
      end,
    }))
    if #items > 0 then
      table.insert(header, ui.button({
        text = confirm == "all" and "本当に全部止める" or "全部止める",
        variant = confirm == "all" and "destructive" or "outline",
        controlSize = "sm",
        enabled = not busy,
        onClick = function()
          confirmOr("all", function()
            run({ "stop", "--all" }, "すべて停止しました")
          end)
        end,
      }))
    end
  end
  table.insert(header, ui.button({ glyph = "close", variant = "ghost", controlSize = "sm", onClick = function() panel.close() end }))
  table.insert(children, ui.row({ gap = 8, align = "center" }, header))

  if doc == nil then
    table.insert(children, ui.label({ text = "attos-jobs-agentの状態を読めません（停止中？）", color = "error" }))
  else
    if doc.preparingForShutdown and #items > 0 then
      table.insert(children, ui.column({ gap = 8, padding = 10, radius = 8, fill = "error/0.15" }, {
        ui.label({ text = "電源オフを待っています", fontWeight = "bold", color = "error" }),
        ui.label({ text = "下の作業が終わると電源が切れます。しばらくするとデスクトップは自動で終了します。", fontSize = 12, maxLines = 3 }),
        ui.row({ gap = 8 }, {
          ui.button({
            text = "全部止めて電源オフ",
            variant = "destructive",
            enabled = not busy,
            onClick = function()
              run({ "stop", "--all" }, "停止しました。まもなく電源が切れます")
            end,
          }),
          ui.button({
            text = "終わるまで待つ（今すぐログアウト）",
            variant = "outline",
            enabled = not busy,
            onClick = function()
              run({ "leave" }, "ログアウトします")
            end,
          }),
        }),
      }))
    end
    if doc.paused then
      table.insert(children, ui.label({ text = "受付停止中: " .. (doc.pausedBy or ""), fontSize = 12, color = "on_surface_variant" }))
    end
    if #items == 0 then
      table.insert(children, ui.label({ text = "他ホストからの作業はありません", color = "on_surface_variant" }))
    else
      local rows = {}
      for _, it in ipairs(items) do
        table.insert(rows, itemRow(it))
      end
      table.insert(children, ui.scroll({ gap = 6, flexGrow = 1 }, rows))
    end
    if doc.errors ~= nil and #doc.errors > 0 then
      table.insert(children, ui.label({ text = "取得エラー: " .. table.concat(doc.errors, "; "), fontSize = 11, color = "error", maxLines = 2 }))
    end
  end
  if message ~= nil then
    table.insert(children, ui.label({ text = message, fontSize = 12, color = messageIsError and "error" or "on_surface_variant", maxLines = 3 }))
  end
  panel.render(ui.column({ gap = 10, flexGrow = 1 }, children))
end

function onOpen(_context)
  confirm = nil
  message = nil
  load()
  panel.setWantsSecondTicks(true)
  render()
end

function onClose()
  confirm = nil
end

local ticks = 0
function update()
  ticks += 1
  if ticks % 2 == 0 and not busy then
    load()
    render()
  end
end
