import QtQuick
import qs.Commons

// 右键「对话」的输入框：回车发送、Esc 关闭。打开期间 overlay 独占键盘。
// 回复走和碎碎念同一条流式管线（Service.speech → 气泡），所以打字机、思考灰字、光标都一样。
Rectangle {
  id: chat

  property var service
  property var pet: null
  property bool open: false
  property real areaWidth: 0
  property real areaHeight: 0

  visible: open
  width: 260
  height: 40
  radius: Style.cornerRadius
  color: Color.popups.background
  border.color: Color.popups.border
  border.width: 1

  function show(targetPet) {
    pet = targetPet
    // 身体命中框右上角旁边，超出屏幕就夹回
    var px = targetPet.x + targetPet.hitX + targetPet.hitW + 6
    var py = targetPet.y + targetPet.hitY + 6
    x = Math.max(4, Math.min(areaWidth - width - 4, px))
    y = Math.max(4, Math.min(areaHeight - height - 4, py))
    input.text = ""
    open = true
    input.forceActiveFocus()
  }

  function close() {
    open = false
    pet = null
  }

  TextInput {
    id: input
    anchors.fill: parent
    anchors.margins: 10
    verticalAlignment: TextInput.AlignVCenter
    color: Color.popups.text
    font.family: Style.fontFamily
    font.pixelSize: 14
    clip: true
    focus: chat.open

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: input.text === ""
      text: chat.service
        ? chat.service.tr(chat.service.piBusy ? "chatBusy"
          : chat.service.murmurReady() ? "chatPlaceholder" : "chatNoModel")
        : ""
      color: Color.muted
      font: input.font
    }

    Keys.onReturnPressed: send()
    Keys.onEnterPressed: send()
    Keys.onEscapePressed: chat.close()

    function send() {
      var text = input.text.trim()
      if (!text || !chat.pet) return
      chat.close()
      chat.service.requestChat(text)
    }
  }
}
