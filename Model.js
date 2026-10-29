// What the bar icon is allowed to say, and how it says it.
//
// The pet knows six phases (lib/pi-state.mjs). A glyph that is 13 pixels tall
// cannot show six of anything: it shows the shape of the eyes and the mouth,
// and colour only ever answers one question — does this want you, is it busy,
// or is it quiet. The exact phase goes in the tooltip, where there is text.

// Six phases, four moods. "result" is still work: the tool call finished, the
// turn did not.
var MOODS = {
  thinking: "busy",
  working: "busy",
  result: "busy",
  waiting: "waiting",
  success: "done",
  error: "error",
}

// `omarchy-shell agent-pet state` prints one JSON object. Anything else (an
// unknown target, a half-written line, a shell that is reloading) is not a
// state and must not be shown as one.
function parseState(raw) {
  var text = String(raw || "").trim()
  if (text === "") return null
  var start = text.indexOf("{")
  if (start < 0) return null
  try {
    var parsed = JSON.parse(text.slice(start))
    return parsed && typeof parsed === "object" ? parsed : null
  } catch (e) {
    return null
  }
}

function moodOf(info) {
  if (!info || info.ready !== true) return "unknown"
  if (info.hidden === true) return "hidden"
  var status = info.workStatus
  if (!status || !status.state) return "idle"
  return MOODS[status.state] || "busy"
}

var LABELS = {
  zh: {
    idle: "空闲",
    busy: "在干活",
    waiting: "等你确认",
    done: "这一轮完了",
    error: "出错了",
    hidden: "已隐藏",
    unknown: "没连上",
  },
  en: {
    idle: "idle",
    busy: "working",
    waiting: "needs you",
    done: "done for now",
    error: "error",
    hidden: "hidden",
    unknown: "not connected",
  },
}

function label(lang, mood) {
  var table = LABELS[lang === "en" ? "en" : "zh"]
  return table[mood] || table.unknown
}

function baseName(path) {
  var parts = String(path || "").split("/").filter(function (part) { return part !== "" })
  return parts.length > 0 ? parts[parts.length - 1] : ""
}

// "Pi Pet · 在干活 · omarchy-pi-pet (bash)". The project comes before the tool:
// which session is talking matters more than which command it ran.
function tooltip(info, mood, lang) {
  var text = "Pi Pet · " + label(lang, mood)
  var status = info && info.workStatus
  if (status) {
    var project = baseName(status.cwd)
    if (project !== "") text += " · " + project
    if (status.tool) text += " (" + String(status.tool) + ")"
  }
  return text
}

// The right-click menu. Same labels in both languages, and the last row says
// what it will do rather than what state it is in.
var MENU = {
  zh: [
    ["murmur", "碎碎念"],
    ["context", "看看上下文"],
    ["compact", "整理记忆"],
    ["reload", "重载配置"],
  ],
  en: [
    ["murmur", "Murmur something"],
    ["context", "Show context usage"],
    ["compact", "Tidy her memory"],
    ["reload", "Reload config"],
  ],
}

// A fresh array each call: the caller owns it, and the toggle row depends on
// whether the pet is currently hidden.
function menuItems(lang, hidden) {
  var table = MENU[lang === "en" ? "en" : "zh"]
  var items = table.map(function (row) { return { label: row[1], method: row[0] } })
  items.push({
    label: hidden
      ? (lang === "en" ? "Show her" : "把宠物放出来")
      : (lang === "en" ? "Hide her" : "把宠物藏起来"),
    method: "toggle",
  })
  return items
}

// The bar hands widgets a palette; a theme may not define every key, so every
// read needs a fallback rather than a binding to undefined.
function barValue(bar, name, fallback) {
  return bar && bar[name] !== undefined ? bar[name] : fallback
}

if (typeof module !== "undefined") {
  module.exports = {
    parseState: parseState,
    moodOf: moodOf,
    label: label,
    tooltip: tooltip,
    menuItems: menuItems,
    barValue: barValue
  }
}
