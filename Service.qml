import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "lib/jsonc.mjs" as Jsonc
import "lib/pi-state.mjs" as PS
import "lib/i18n.mjs" as I18n

// pi-pet 的状态中枢：配置、pi 会话状态、宠物说话、通知、IPC。
// 每块屏一个 PetOverlay（全屏透明 layer-shell 窗口）。
Scope {
  id: root

  // 宿主注入
  property var shell: null
  property string omarchyPath: ""
  property var manifest: null

  // 部署验证用：改一次代码就递增，state 里能看到运行的是不是新代码
  readonly property string build: "v1.2-sayinfo"
  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, ""))
  // 目录一律走 XDG：用户把 XDG_CONFIG_HOME / XDG_STATE_HOME 指到别处时也要跟着走
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")
  readonly property string userConfigPath: configHome + "/agent-pet/config.jsonc"
  readonly property string stateDir: stateHome + "/agent-pet"
  // socket 所在目录（0700）。XDG_RUNTIME_DIR 没设时按 /run/user/<uid> 兜底，
  // 与 ext/*.ts 里的算法保持一致（一个在 QML，一个在 Node，必须同源同规则）
  property string runtimeBase: ""
  readonly property string runtimeDir: runtimeBase === "" ? "" : runtimeBase + "/agent-pet"

  // ------------------------------------------------------------ 配置
  property var config: ({})
  property bool ready: false
  property string configError: ""
  property bool hidden: false
  property string lang: "zh"
  // 动画帧率：assets/webp/manifest.json 里写的 15fps，读不到就用它
  property int assetFps: 15

  function tr(key, params) {
    return I18n.t(lang, key, params)
  }

  // 提示气泡统一入口：先清掉上一句说话的滞留，再发 speak，否则 speech 的优先级会把提示盖住
  function sayInfo(text) {
    speech = null
    speechMeme = ""
    speak("", text, "", "info")
  }

  readonly property var murmur: config.murmur || ({})
  readonly property var petCfg: ({
    id: "main",
    name: "Pi Pet",
    size: Number((config.pet || {}).size) || 300,
    corner: (config.pet || {}).corner || "bottom-right",
    marginX: Number((config.pet || {}).marginX) || 0,
    marginY: Number((config.pet || {}).marginY) || 0
  })

  function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value)
  }

  // 深合并：对象逐层合并、数组整体替换、null = 删掉这个键（回退到内置默认）。
  // 这样 {"murmur": {"model": "x"}} 不会再把手写没写的兄弟键一起冲掉。
  function deepMerge(base, override) {
    var out = Array.isArray(base) ? base.slice() : (isPlainObject(base) ? Object.assign({}, base) : {})
    if (!isPlainObject(override)) return out
    var keys = Object.keys(override)
    for (var i = 0; i < keys.length; i++) {
      var key = keys[i]
      var value = override[key]
      if (value === null) delete out[key]
      else if (isPlainObject(value) && isPlainObject(out[key])) out[key] = deepMerge(out[key], value)
      else out[key] = value
    }
    return out
  }

  function rebuildConfig() {
    var base
    try {
      base = JSON.parse(defaultFile.text())
    } catch (e) {
      console.warn("[pi-pet] 内置配置解析失败:", e)
      return
    }
    var user = {}
    configError = ""
    var userText = userFile.loaded ? userFile.text() : ""
    if (userText.trim() !== "") {
      try {
        user = Jsonc.parseJsonc(userText) || {}
      } catch (e) {
        configError = String(e)
        console.warn("[pi-pet] 用户配置解析失败，使用内置配置:", e)
      }
    }
    var merged = deepMerge(base, user)
    lang = I18n.resolveLang(merged.language, {
      LANGUAGE: Quickshell.env("LANGUAGE") || "",
      LC_ALL: Quickshell.env("LC_ALL") || "",
      LC_MESSAGES: Quickshell.env("LC_MESSAGES") || "",
      LANG: Quickshell.env("LANG") || ""
    })
    // 内置文案是中文：英文界面下，用户没自定义的就换成英文版
    if (lang === "en" && !("workStatusTexts" in user)) merged.workStatusTexts = I18n.WORK_STATUS_TEXTS_EN
    config = merged
    ready = true
    if (configError) sayInfo(tr("configError", { error: configError }))
  }

  FileView {
    id: assetManifest
    path: root.pluginDir + "/assets/webp/manifest.json"
    blockLoading: true
    printErrors: false
    onLoaded: {
      try {
        root.assetFps = Number(JSON.parse(text()).fps) || 15
      } catch (e) {}
    }
  }

  function reloadConfig() {
    userFile.reload()
    defaultFile.reload()
  }

  FileView {
    id: defaultFile
    path: root.pluginDir + "/assets/config.json"
    blockLoading: true
    onLoaded: root.rebuildConfig()
  }

  FileView {
    id: userFile
    path: root.userConfigPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: if (defaultFile.loaded) root.rebuildConfig()
    onLoadFailed: if (defaultFile.loaded) root.rebuildConfig()
  }

  // ------------------------------------------------------------ 宠物对外信号
  property var speech: null

  // petId 为空 = 所有宠物
  signal speak(string petId, string text, string meme, string kind)
  signal playRequest(string petId, string name)
  // 整理记忆时的"睡觉"状态：true 睡下（循环动画），false 醒来
  signal sleepRequest(bool sleeping)

  // ------------------------------------------------------------ overlay 登记
  // 每块屏一个 overlay。顶栏右键要把菜单开在"这块屏上的那只宠物"里，所以得能从
  // IPC 找到对应实例——顺序无关，按屏名匹配。
  property var overlays: []

  function registerOverlay(overlay) {
    overlays = overlays.filter(function (other) { return other !== overlay }).concat([overlay])
  }

  function unregisterOverlay(overlay) {
    overlays = overlays.filter(function (other) { return other !== overlay })
  }

  function overlayFor(screenName) {
    for (var i = 0; i < overlays.length; i++) {
      if (overlays[i].screenName === screenName) return overlays[i]
    }
    return overlays.length > 0 ? overlays[0] : null
  }

  // ------------------------------------------------------------ 工作状态
  property var wsStore: PS.createStore()
  property var workStatus: null
  // 宠物自己那个持久会话（--session-id agent-pet）的上下文占用，由子进程 pet.ts 上报
  property var petCtx: null

  EventServer {
    id: eventServer
    path: root.runtimeDir + "/events.sock"
    replyHandler: root.replyToChild
    onReceived: line => root.handleEvent(line)
  }

  // 子进程（宠物自己的 pi）来问状态：带 id，回一行；host 的推送不带 id，不回。
  function replyToChild(line) {
    var ev
    try {
      ev = JSON.parse(line)
    } catch (e) {
      return ""
    }
    if (!ev || ev.src !== "child" || !ev.id) return ""
    if (ev.e !== "state") return JSON.stringify({ id: ev.id, ok: false })
    var snapshot = PS.snapshot(root.wsStore, Date.now(), {
      hidden: root.hidden,
      speaking: pi.busy,
      lang: root.lang
    })
    return JSON.stringify({ id: ev.id, ok: true, state: snapshot })
  }

  function handleEvent(line) {
    var ev
    try {
      ev = JSON.parse(line)
    } catch (e) {
      return "bad-json"
    }
    if (!ev) return "bad-event"
    if (ev.src === "child" && ev.e === "petctx") {
      var pct = Number(ev.pct)
      if (Number.isFinite(pct)) {
        petCtx = { pct: pct, tok: ev.tok, win: ev.win }
      }
      return "petctx"
    }
    if (ev.src !== "host") return "ignored"
    var res = PS.applyEvent(wsStore, ev, Date.now())
    if (res.entered) notifyFor(res.entry, res.entered)
    if (res.changed) refreshWorkStatus()
    return "ok"
  }

  function refreshWorkStatus() {
    var cur = PS.current(wsStore)
    if (!cur) {
      if (workStatus) workStatus = null
      return
    }
    var prev = workStatus
    // 档位、工具、命令、上下文或总结任一变化都发新快照；宠物只在会话/档位变化时切动画
    if (prev && prev.key === cur.key && prev.state === cur.state && prev.tool === cur.tool
      && prev.detail === cur.detail && prev.ctxPercent === cur.ctxPercent
      && prev.cwd === cur.cwd && prev.lastLine === cur.lastLine) return
    workStatus = Object.assign({}, cur)
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: if (PS.prune(root.wsStore, Date.now())) root.refreshWorkStatus()
  }

  // ------------------------------------------------------------ 系统通知
  // 只发固定文字（agent 名 + 状态）。Omarchy 的通知服务会把标题正文放进 bash 参数落盘，
  // 所以项目名、命令、消息一律不进通知。
  function notifyFor(entry, state) {
    var n = config.notify || {}
    if (state !== "waiting" && state !== "success" && state !== "error") return
    if (state === "waiting" && n.waiting === false) return
    if (state === "success" && n.done === false) return
    if (state === "error" && n.error === false) return
    if (n.onlyWhenUnfocused !== false && entry.focused) return
    var titleKey = state === "waiting" ? "notifyWaiting" : state === "success" ? "notifySuccess" : "notifyError"
    var icon = state === "waiting" ? "approval" : state === "success" ? "done" : "error"
    Quickshell.execDetached(["notify-send", "-a", "pi-pet",
      "-i", root.pluginDir + "/assets/pic/notify-" + icon + ".png",
      "pi · " + tr(titleKey)])
  }

  // ------------------------------------------------------------ 说话（宠物自己的 pi）
  Pi {
    id: pi
    pluginDir: root.pluginDir
    stateDir: root.stateDir
    lang: root.lang
    model: String(root.murmur.model || "")
    provider: String(root.murmur.provider || "")
    thinking: String(root.murmur.thinking || "low")
    sessionId: root.murmur.session === undefined ? "agent-pet" : String(root.murmur.session)
    tools: Array.isArray(root.murmur.tools) ? root.murmur.tools.join(",") : String(root.murmur.tools || "")
    extensions: Array.isArray(root.murmur.extensions) ? root.murmur.extensions : []
    streamMode: root.murmur.stream !== false
    typewriterCps: Number(root.murmur.typewriterCps) || 0
    showThinking: root.murmur.showThinking !== false
    firstTokenTimeoutSec: Number(root.murmur.firstTokenTimeoutSec) || 15
    timeoutSec: Number(root.murmur.timeoutSec) || 120
    onTick: root.syncSpeech()
    onFinished: function(ok, code, detail) { root.onSpeechFinished(ok, code, detail) }
  }

  readonly property bool piBusy: pi.busy
  property string speechMeme: ""

  property bool sleeping: false

  // ------------------------------------------------------------ 整理记忆（compact 持久会话）
  Process {
    id: compactProc
    stdout: StdioCollector { id: compactOut }
    stderr: StdioCollector { id: compactErr }
    onExited: function(exitCode) { root.onCompactFinished(exitCode) }
  }

  function requestCompact() {
    if (!murmurReady()) {
      sayInfo(tr("errNoModel"))
      return "no-model"
    }
    if (pi.busy || compactProc.running || sleeping) {
      sayInfo(tr("busy"))
      return "busy"
    }
    var sessionId = root.murmur.session === undefined ? "agent-pet" : String(root.murmur.session)
    if (sessionId === "") {
      sayInfo(tr("compactNoSession"))
      return "no-session"
    }
    var cmd = ["bash", pluginDir + "/bin/agent-pet-pi",
      "--model", String(root.murmur.model || ""),
      "--session", sessionId,
      "--compact",
      "--plugin", pluginDir, "--state", stateDir]
    if (String(root.murmur.provider || "")) cmd = cmd.concat(["--provider", String(root.murmur.provider)])
    compactProc.command = cmd
    compactProc.running = true
    sleeping = true
    sleepRequest(true)
    sayInfo(tr("compactRunning"))
    return "ok"
  }

  function onCompactFinished(exitCode) {
    // 醒来：先播醒来动画，再报结果
    sleeping = false
    sleepRequest(false)
    // compact 后旧的占用不再准确：清掉，等下次说话时子进程重新上报
    petCtx = null
    var text = String(compactOut.text || "").trim()
    var ok = false
    var detail = ""
    if (text) {
      try {
        var resp = JSON.parse(text)
        if (resp.success && resp.data) {
          ok = true
          detail = tr("compactDone", {
            before: resp.data.tokensBefore,
            after: resp.data.estimatedTokensAfter
          })
        } else {
          detail = tr("compactFailed", { reason: String(resp.error || "?") })
        }
      } catch (e) {
        detail = tr("compactFailed", { reason: text.slice(0, 80) })
      }
    } else if (exitCode !== 0) {
      var errLine = String(compactErr.text || "").trim().split("\n").pop() || ("exit " + exitCode)
      detail = tr("compactFailed", { reason: errLine.slice(0, 80) })
    } else {
      detail = tr("compactFailed", { reason: "no response" })
    }
    sayInfo(detail)
  }

  // 气泡停留时长：碎碎念一句就走，对话多留一会儿
  property int speechHoldMs: 12000

  function setSpeech(next) {
    var cur = speech
    if (cur && cur.text === next.text && cur.thinking === next.thinking && cur.notice === next.notice
      && cur.streaming === next.streaming && cur.error === next.error && cur.meme === next.meme) return
    speech = next
  }

  function syncSpeech() {
    var text = pi.displayText
    var s = {
      kind: "speech",
      text: text,
      thinking: pi.displayThinking,
      notice: pi.notice,
      streaming: pi.streaming,
      error: "",
      meme: root.speechMeme
    }
    // 刚起进程、还没有任何输出：先占位，别让人以为点了没反应
    if (!s.text && !s.thinking && !s.notice && pi.busy) s.notice = "……"
    // 进程结束且没什么可放的：保留当前内容（可能是错误气泡），不要清空
    if (!s.text && !s.thinking && !s.notice && !pi.busy) return
    setSpeech(s)
  }

  function onSpeechFinished(ok, code, detail) {
    var empty = { kind: "speech", text: "", thinking: "", notice: "", streaming: false, error: "", meme: "" }
    if (ok) {
      setSpeech({
        kind: "speech",
        text: pi.displayText,
        thinking: "",
        notice: "",
        streaming: false,
        error: "",
        meme: root.speechMeme
      })
    } else if (code === "killed" || code === "silent") {
      // 被打断 / 只想了没说话：留存已经说出的部分，没有就静默
      if (String(pi.speechText).trim() === "") {
        speech = null
        return
      }
      setSpeech({
        kind: "speech",
        text: pi.displayText,
        thinking: "",
        notice: "",
        streaming: false,
        error: "",
        meme: root.speechMeme
      })
    } else if (code === "timeout") {
      setSpeech(Object.assign({}, empty, { error: tr("errTimeout") }))
    } else if (code === "pi") {
      setSpeech(Object.assign({}, empty, { error: tr("errPi", { detail: detail || "?" }) }))
    } else {
      setSpeech(Object.assign({}, empty, { error: tr("errExit", { detail: detail || "?" }) }))
    }
    speechTimer.restart()
  }

  Timer {
    id: speechTimer
    interval: root.speechHoldMs
    onTriggered: root.speech = null
  }

  function murmurReady() {
    return root.murmur.enabled === true && String(root.murmur.model || "") !== ""
  }

  function requestMurmur(manual) {
    if (sleeping) {
      if (manual) sayInfo(tr("sleeping"))
      return "sleeping"
    }
    if (!murmurReady()) {
      if (manual) sayInfo(tr("errNoModel"))
      return "no-model"
    }
    if (pi.busy) {
      if (manual) sayInfo(tr("busy"))
      return "busy"
    }
    // 隐藏时只有手动点（IPC/菜单）才会开口
    if (!manual && root.hidden) return "hidden"
    // 你正在干活时不打扰（只有手动点才允许插一句）
    if (!manual && PS.anyBusy(wsStore)) return "agent-busy"
    var meme = ""
    var names = Object.keys(config.memes || {})
    if (names.length && Math.random() < 0.5) meme = names[Math.floor(Math.random() * names.length)]
    speechMeme = config.memes && config.memes[meme] ? meme : ""
    speechHoldMs = 12000
    var sep = lang === "en" ? " " : ""
    var prompt = tr("murmurNow", { time: Qt.formatTime(new Date(), "HH:mm") })
    if (speechMeme) prompt += sep + tr("murmurMeme", { desc: config.memes[speechMeme] })
    prompt += sep + tr("murmurOutput")
    return pi.run(prompt, "murmur") ? "ok" : "busy"
  }

  /** 对话：和碎碎念同一条会话、同一套隔离，只是提示词和停留时长不同。 */
  function requestChat(text) {
    if (sleeping) {
      sayInfo(tr("sleeping"))
      return "sleeping"
    }
    if (!murmurReady()) {
      sayInfo(tr("errNoModel"))
      return "no-model"
    }
    if (pi.busy) {
      sayInfo(tr("busy"))
      return "busy"
    }
    speechMeme = ""
    speechHoldMs = 30000
    var sep = lang === "en" ? " " : ""
    var prompt = tr("chatPrompt", { text: text }) + sep + tr("chatStyle")
    if (!pi.run(prompt, "chat")) {
      sayInfo(tr("busy"))
      return "busy"
    }
    return "ok"
  }

  Timer {
    id: murmurTimer
    interval: Math.max(60, Number(root.murmur.intervalSec) || 600) * 1000
    // 隐藏时不自动开口：每次开口都是一次子 pi spawn（本地模型也要算力），看不见就别烧
    running: root.ready && root.murmurReady() && !root.hidden
    repeat: true
    onTriggered: root.requestMurmur(false)
  }

  // ------------------------------------------------------------ 上下文占用（原"余额"）
  function showContext() {
    if (!petCtx || !(petCtx.pct >= 0)) {
      sayInfo(tr("ctxUnknown"))
      return
    }
    var pct = Math.round(petCtx.pct)
    sayInfo(tr("ctxUsage", { pct: pct }))
    var pool = (config.animations || {}).events || {}
    var slot = (pool.context || [])[PS.ctxTier(petCtx.pct)]
    if (slot !== undefined) playRequest("", pickPoolSlot(slot))
  }

  // 播放档位池里的一段（字符串或数组），与 Pet 内部同一套规则
  function pickPoolSlot(slot) {
    if (typeof slot === "string") return slot
    if (Array.isArray(slot) && slot.length) return slot[Math.floor(Math.random() * slot.length)]
    return ""
  }

  // ------------------------------------------------------------ IPC：omarchy-shell agent-pet <method>
  // 用 ShellIpc 而不是裸 IpcHandler：omarchy-shell 先问 shell 自己的 IpcRegistry（ShellIpc 才会注册），
  // 查不到才退回去起一个 qs ipc 客户端。裸 IpcHandler 只能走后者，慢且易受实例匹配影响。
  ShellIpc {
    target: "agent-pet"

    function ping(): string {
      return "pong"
    }

    function say(text: string): string {
      root.sayInfo(text)
      return "ok"
    }
    function play(name: string): string {
      root.playRequest("", name)
      return "ok"
    }
    function murmur(): string {
      return root.requestMurmur(true)
    }
    function chat(text: string): string {
      return root.requestChat(text)
    }
    function context(): string {
      root.showContext()
      return "ok"
    }
    function compact(): string {
      return root.requestCompact()
    }
    function reload(): string {
      root.reloadConfig()
      return "ok"
    }
    function toggle(): string {
      root.hidden = !root.hidden
      if (root.hidden) pi.cancel()
      return root.hidden ? "hidden" : "shown"
    }
    // 顶栏图标右键：把宠物自己的菜单开在图标下面。用的是同一个 PetMenu、同一份动作
    // 表，所以两边永远不会长出两套列表。
    function menu(screen: string, x: string, y: string): string {
      var overlay = root.overlayFor(String(screen || ""))
      if (!overlay) return "no-pet"
      var px = Number(x)
      var py = Number(y)
      if (!Number.isFinite(px) || !Number.isFinite(py)) return "bad-point"
      overlay.openMenu(overlay.petObject, px, py)
      return "ok"
    }
    function forget(): string {
      pi.cancel()
      root.speech = null
      Quickshell.execDetached(["bash", "-c",
        'dir="${XDG_STATE_HOME:-$HOME/.local/state}/agent-pet/pi-sessions"; [ -d "$dir" ] && rm -rf -- "$dir"/*; true'])
      return "ok"
    }
    function state(): string {
      var ws = root.workStatus
      return JSON.stringify({
        build: root.build,
        ready: root.ready,
        hidden: root.hidden,
        configError: root.configError,
        lang: root.lang,
        workStatus: ws,
        sessions: root.wsStore.sessions,
        ctxTier: ws && ws.ctxPercent >= 0 ? PS.ctxTier(ws.ctxPercent) : -1,
        petCtx: root.petCtx,
        speech: root.speech,
        murmur: {
          ready: root.murmurReady(),
          busy: pi.busy,
          model: String(root.murmur.model || ""),
          thinking: String(root.murmur.thinking || "")
        }
      })
    }
  }

  // ------------------------------------------------------------ 每块屏一个透明 overlay
  Variants {
    model: root.ready ? Quickshell.screens : []

    PetOverlay {
      required property var modelData
      screen: modelData
      service: root
      petCfg: root.petCfg
    }
  }

  Component.onCompleted: console.log("[pi-pet] service mounted, pluginDir=" + root.pluginDir)

  // 运行时目录：先解析（XDG_RUNTIME_DIR 可能没设），再建目录（0700），最后才开监听
  Process {
    running: true
    command: ["bash", "-c", 'printf %s "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"']
    stdout: StdioCollector { id: runtimeOut }
    onExited: function(exitCode) {
      root.runtimeBase = String(runtimeOut.text || "").trim()
      if (exitCode !== 0 || root.runtimeBase === "") {
        console.warn("[pi-pet] 拿不到运行时目录，收不到 pi 事件")
        return
      }
      mkDirs.running = true
    }
  }

  Process {
    id: mkDirs
    command: ["bash", "-c", 'mkdir -p -m 700 "$@" && chmod 700 "$@"', "_", root.stateDir, root.runtimeDir]
    onExited: function(exitCode) {
      if (exitCode === 0) eventServer.start()
      else console.warn("[pi-pet] 无法创建 " + root.runtimeDir + "，收不到 pi 事件")
    }
  }
}
