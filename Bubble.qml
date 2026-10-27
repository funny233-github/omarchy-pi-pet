import QtQuick

// 头顶气泡：白底圆角 + 小尾巴，可带一张表情包。不接收输入（不在 overlay 的 mask 里）。
//
// 流式显示的三个约定（见 Pi.qml）：
// - 流式期间宽度锁在 maxTextWidth，否则每来一个字就重新折行、气泡左右横跳；
// - 说话时末尾挂一个闪烁的光标，结束后摘掉；
// - 思考阶段用灰色斜体、最多两行；错误用深红。
Item {
  id: bubble

  // { text, thinking, notice, streaming, error, meme }
  property var content: null
  property url memeDir
  property real maxTextWidth: 240
  property bool fixedWidth: false
  // 字体：fontFile（字体文件路径）> fontFamily（已安装字体名）> sans-serif
  property string fontFamily: ""
  property string fontFile: ""
  property int fontSize: 14
  property real tailX: width / 2

  // 淡出期间保留最后一份内容，避免先清空再消失
  property var shownContent: null
  onContentChanged: if (content) shownContent = content

  readonly property bool hasText: shownContent && shownContent.text ? String(shownContent.text) !== "" : false
  readonly property bool thinking: shownContent && !hasText && shownContent.thinking ? String(shownContent.thinking) !== "" : false
  readonly property bool isError: shownContent && shownContent.error ? String(shownContent.error) !== "" : false
  readonly property bool streaming: shownContent ? shownContent.streaming === true : false

  readonly property string bodyText: {
    if (!shownContent) return ""
    if (shownContent.error) return String(shownContent.error)
    if (hasText) return String(shownContent.text) + (streaming && cursorOn ? "▍" : "")
    if (thinking) return String(shownContent.thinking)
    if (shownContent.notice) return String(shownContent.notice)
    return ""
  }

  readonly property bool active: bodyText !== ""
  opacity: active ? 1 : 0
  visible: opacity > 0
  Behavior on opacity {
    NumberAnimation {
      duration: 160
    }
  }

  readonly property int pad: 10
  width: body.width
  height: body.height + tail.height / 2

  FontLoader {
    id: loader
    source: bubble.fontFile ? "file://" + bubble.fontFile : ""
  }

  readonly property string resolvedFamily: loader.status === FontLoader.Ready ? loader.name
    : bubble.fontFamily || "sans-serif"

  Rectangle {
    id: body
    // 流式期间锁宽：宁可留白，也不要一边打字一边变宽
    width: (bubble.fixedWidth || bubble.streaming || bubble.thinking) ? bubble.maxTextWidth + bubble.pad * 2
      : Math.max(label.width, meme.visible ? meme.width : 0) + bubble.pad * 2
    height: column.height + bubble.pad * 2
    radius: 12
    color: Qt.rgba(1, 1, 1, 0.94)
    border.color: Qt.rgba(0.17, 0.17, 0.17, 0.12)

    Column {
      id: column
      x: bubble.pad
      y: bubble.pad
      spacing: 6

      Text {
        id: label
        text: bubble.bodyText
        // 内容来自 pi 会话和模型输出，不可信：一律按纯文本显示。
        // 默认的 AutoText 在首行像 HTML 时会按富文本解析，<img> 里的远程地址会被直接请求。
        textFormat: Text.PlainText
        color: bubble.isError ? "#b3261e" : bubble.thinking ? "#8a8a8a" : "#2b2b2b"
        font.family: bubble.resolvedFamily
        font.pixelSize: bubble.fontSize
        font.italic: bubble.thinking
        lineHeight: 1.25
        wrapMode: Text.Wrap
        maximumLineCount: bubble.thinking ? 2 : 0
        elide: bubble.thinking ? Text.ElideRight : Text.ElideNone
        width: Math.min(implicitWidth, bubble.maxTextWidth)
      }

      Image {
        id: meme
        readonly property string name: bubble.shownContent && bubble.shownContent.meme ? bubble.shownContent.meme : ""
        visible: name !== "" && status === Image.Ready
        source: name ? bubble.memeDir + name + ".png" : ""
        width: 110
        height: visible ? width * (implicitHeight / Math.max(1, implicitWidth)) : 0
        fillMode: Image.PreserveAspectFit
        smooth: true
        asynchronous: true
      }
    }
  }

  Rectangle {
    id: tail
    width: 12
    height: 12
    rotation: 45
    color: body.color
    x: Math.max(body.radius, Math.min(body.width - body.radius - width, bubble.tailX - width / 2))
    y: body.height - height / 2 - 1
    z: -1
  }

  // 光标闪烁：只在说话时跑，省得平时也在打点
  Timer {
    interval: 500
    repeat: true
    running: bubble.streaming
    onTriggered: bubble.cursorOn = !bubble.cursorOn
  }
  property bool cursorOn: true
}
