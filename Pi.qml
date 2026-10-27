import QtQuick
import Quickshell
import Quickshell.Io

// 宠物自己的 pi。两个职责：
//   1) 唯一 spawn 点：只通过 bin/agent-pet-pi 启动，flag 全在脚本里写死（不要让 QML 直接拼 pi 命令）；
//   2) 流式解析：--mode json 的 NDJSON 逐行读，维护「思考 → 说话」相位机 + 打字机 + 双超时。
//
// 相位机（实测得出，见 README 的测试记录）：
//   thinking_delta 先来，text_delta 后到；而 thinking_end 往往在全部 text_delta 之后才到，
//   所以绝不能用 thinking_end 刷新显示——那会在说完之后把思考文字盖回来。
//
// 收尾一律以「进程退出」为准：中断时 pi 不会发 agent_end / agent_settled（实测 exit=143）。
Scope {
  id: pi

  // ------------------------------------------------------------ 注入
  property string pluginDir: ""
  property string stateDir: ""
  property string lang: "zh"
  property string model: ""
  property string provider: ""
  property string thinking: "low"
  property string sessionId: "agent-pet"
  property string tools: "pet_state"
  property var extensions: []
  property bool streamMode: true
  property int firstTokenTimeoutSec: 15
  property int timeoutSec: 120
  property int typewriterCps: 30
  property bool showThinking: true
  property int thinkingMaxChars: 100

  // ------------------------------------------------------------ 对外状态
  property string requestKind: ""
  property string phase: "idle" // idle | thinking | speech
  property string thinkText: ""
  property string speechText: ""
  property string notice: "" // 例如 "（pet_state）"：她回头看了一眼
  property bool streaming: false
  readonly property bool busy: proc.running
  readonly property string displayText: shown >= speechText.length ? speechText : speechText.slice(0, shown)
  readonly property string displayThinking: phase === "thinking" ? thinkText : ""

  signal tick()
  // ok=true 表示这次成功说出了话；否则 code 是 "timeout" / "killed" / "pi" / "exit" / "silent"
  signal finished(bool ok, string code, string detail)

  property int shown: 0
  property string errorLine: ""
  property bool stopReasonError: false
  property bool selfKilled: false
  property string timeoutKind: ""

  // ------------------------------------------------------------ 入口
  function run(prompt, kind) {
    if (proc.running) return false
    if (!model) return false
    reset()
    requestKind = kind || "murmur"
    proc.command = buildCommand()
    proc.stdinEnabled = true
    proc.input = prompt
    proc.running = true
    streaming = true
    firstTokenTimer.restart()
    totalTimer.restart()
    tick()
    return true
  }

  /** 用户主动打断（隐藏宠物、切走、再来一次）：不算错误 */
  function cancel() {
    if (!proc.running) return
    selfKilled = true
    proc.signal(15)
  }

  function buildCommand() {
    var cmd = ["bash", pluginDir + "/bin/agent-pet-pi",
      "--model", model,
      "--thinking", thinking,
      "--session", sessionId || "",
      "--tools", tools || "",
      "--lang", lang,
      "--stream", streamMode ? "1" : "0",
      "--plugin", pluginDir,
      "--state", stateDir]
    if (provider) cmd = cmd.concat(["--provider", provider])
    var extra = extensions || []
    for (var i = 0; i < extra.length; i++) {
      if (String(extra[i])) cmd = cmd.concat(["--ext", String(extra[i])])
    }
    return cmd
  }

  function reset() {
    phase = "idle"
    thinkText = ""
    speechText = ""
    notice = ""
    shown = 0
    streaming = false
    errorLine = ""
    stopReasonError = false
    selfKilled = false
    timeoutKind = ""
  }

  // ------------------------------------------------------------ 逐行解析
  function handleLine(line) {
    if (line === undefined || line === null) return
    if (!streamMode) {
      // 逃生口：--mode text，纯文本一次性输出（SplitParser 的行尾换行由这里补回）
      beginSpeech()
      speechText += String(line) + "\n"
      firstTokenTimer.stop()
      tick()
      return
    }

    var ev
    try {
      ev = JSON.parse(line)
    } catch (e) {
      return
    }

    if (ev.type === "message_update") {
      var d = ev.assistantMessageEvent || {}
      if (d.type === "thinking_start") {
        firstTokenTimer.stop()
        tick()
      } else if (d.type === "thinking_delta") {
        firstTokenTimer.stop()
        appendThinking(d.delta)
      } else if (d.type === "text_start") {
        firstTokenTimer.stop()
        beginSpeech()
      } else if (d.type === "text_delta") {
        firstTokenTimer.stop()
        beginSpeech()
        speechText += String(d.delta || "")
        tick()
      } else if (d.type === "text_end") {
        beginSpeech()
        // 权威内容：用它覆盖前面拼的，丢包也不会残句
        speechText = String(d.content || speechText)
        tick()
      } else if (d.type === "toolcall_start") {
        notice = "（" + String(d.toolName || "tool") + "）"
        tick()
      } else if (d.type === "error") {
        errorLine = String(d.error || d.reason || "").slice(0, 200)
      }
      return
    }

    if (ev.type === "message_end") {
      var message = ev.message || {}
      if (message.role !== "assistant") return
      if (message.stopReason === "error") stopReasonError = true
      if (message.errorMessage) errorLine = String(message.errorMessage).slice(0, 200)
      var full = textOf(message)
      if (full) {
        beginSpeech()
        speechText = full
        tick()
      }
    }
  }

  function textOf(message) {
    try {
      if (typeof message.content === "string") return message.content
      if (Array.isArray(message.content)) {
        return message.content
          .filter(function(block) { return block && block.type === "text" })
          .map(function(block) { return block.text || "" })
          .join("")
      }
    } catch (e) {}
    return ""
  }

  function beginSpeech() {
    if (phase === "speech") return
    phase = "speech"
    thinkText = ""
    notice = ""
    tick()
  }

  function appendThinking(delta) {
    if (!showThinking) return
    if (phase !== "thinking") {
      phase = "thinking"
      tick()
    }
    if (thinkText.length >= thinkingMaxChars) return
    thinkText = (thinkText + String(delta || "")).slice(0, thinkingMaxChars)
    tick()
  }

  // ------------------------------------------------------------ 进程
  Process {
    id: proc
    property string input: ""
    // 写完立即关闭 stdin，pi 读到 EOF 才开始
    onStarted: {
      proc.write(proc.input)
      proc.stdinEnabled = false
      proc.input = ""
    }
    stdout: SplitParser {
      onRead: line => pi.handleLine(line)
    }
    stderr: StdioCollector {
      id: errText
    }
    onExited: function(exitCode) {
      pi.handleExit(exitCode)
    }
  }

  function lastStderr(exitCode) {
    var text = String(errText.text || "").trim()
    if (!text) return "退出码 " + exitCode
    var lines = text.split("\n")
    return String(lines[lines.length - 1]).slice(0, 200)
  }

  function handleExit(exitCode) {
    firstTokenTimer.stop()
    totalTimer.stop()
    streaming = false
    // 不把 shown 直接跳到末尾：打字机继续把剩下的字放完，收尾更自然
    var ok = false
    var code = ""
    var detail = ""
    if (timeoutKind !== "") {
      code = "timeout"
      detail = timeoutKind
    } else if (selfKilled) {
      code = "killed"
    } else if (String(speechText).trim() !== "") {
      ok = true
    } else if (errorLine !== "" || stopReasonError) {
      code = "pi"
      detail = errorLine
    } else if (exitCode !== 0) {
      code = "exit"
      detail = lastStderr(exitCode)
    } else {
      // 只想了没说话（实测中断时会出现），静默收尾
      code = "silent"
    }
    tick()
    finished(ok, code, detail)
  }

  // ------------------------------------------------------------ 打字机
  // 33ms 一拍：cps=30 时约每拍一个字；积压超过 40 字自动加速，避免说完再慢慢放三秒。
  Timer {
    id: ticker
    interval: 33
    repeat: true
    running: pi.shown < pi.speechText.length
    onTriggered: {
      var backlog = pi.speechText.length - pi.shown
      if (pi.typewriterCps <= 0) {
        pi.shown = pi.speechText.length
      } else {
        var step = Math.max(1, Math.round(pi.typewriterCps * interval / 1000))
        if (backlog > 40) step = step * 2
        pi.shown = Math.min(pi.speechText.length, pi.shown + step)
      }
      pi.tick()
    }
  }

  // ------------------------------------------------------------ 双超时
  // 首字超时与总超时分开：冷启动慢的本地模型不该被总超时判死，真卡死的也不该拖满两分钟。
  Timer {
    id: firstTokenTimer
    interval: Math.max(3, pi.firstTokenTimeoutSec) * 1000
    onTriggered: {
      if (!proc.running) return
      pi.timeoutKind = "first"
      proc.signal(15)
    }
  }

  Timer {
    id: totalTimer
    interval: Math.max(10, pi.timeoutSec) * 1000
    onTriggered: {
      if (!proc.running) return
      pi.timeoutKind = "total"
      proc.signal(15)
    }
  }
}
