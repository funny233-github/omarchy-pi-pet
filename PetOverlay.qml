import QtQuick
import Quickshell
import Quickshell.Wayland

// 一块屏一个全屏透明 layer-shell 窗口，宠物在窗口内自由移动 / 被甩飞。
// 输入区域（mask）只包含宠物身体（和右键菜单打开时的整窗），其余位置点击穿透。
// 右键菜单打开期间整窗接收输入，点空白处关闭；平时不抢键盘。
PanelWindow {
  id: win

  property var service
  property var petCfg

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }
  color: "transparent"
  // Normal + exclusiveZone 0：窗口只占可用区域，不压 bar；窗口底边就是宠物的地面
  exclusionMode: ExclusionMode.Normal
  exclusiveZone: 0
  WlrLayershell.namespace: "pi-pet"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: chat.open || menu.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  // The window outlives 隐藏 when a menu is open: the list has to be reachable
  // from the bar even while the pet is put away.
  visible: !service.hidden || menu.open

  // PanelWindow 的 width/height 是 implicit 尺寸的别名，四边锚定时恒为 0；真实尺寸从填满窗口的 Item 取
  Item {
    id: area
    anchors.fill: parent
  }
  readonly property real areaW: area.width
  readonly property real areaH: area.height

  Region {
    id: fullRegion
    x: 0
    y: 0
    width: win.areaW
    height: win.areaH
  }

  Pet {
    id: pet
    cfg: win.petCfg
    service: win.service
    overlay: win
    // The surface can be up for the menu alone; the sprite follows 隐藏.
    visible: !win.service.hidden
  }

  Region {
    id: chatRegion
    x: chat.x
    y: chat.y
    width: chat.open ? chat.width : 0
    height: chat.open ? chat.height : 0
  }

  mask: Region {
    regions: menu.open ? [fullRegion] : [pet.hitRegion, chatRegion]
  }

  // 顶栏右键走这条路：同一份菜单，只是锚点换成了图标的位置
  readonly property var petObject: pet
  readonly property string screenName: screen ? screen.name : ""

  function openMenu(targetPet, px, py) {
    menu.show(targetPet, px, py)
  }

  Component.onCompleted: if (win.service) win.service.registerOverlay(win)
  Component.onDestruction: if (win.service) win.service.unregisterOverlay(win)

  function openChat(targetPet) {
    chat.show(targetPet)
  }

  PetMenu {
    id: menu
    anchors.fill: parent
    service: win.service
  }

  ChatInput {
    id: chat
    service: win.service
    areaWidth: win.areaW
    areaHeight: win.areaH
  }
}
