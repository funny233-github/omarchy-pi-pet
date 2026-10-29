pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The pet, reduced to what fits in the bar: a face whose expression says
// "quiet / working / wants you / done / broke", and a tooltip that says which
// of the six phases it is in and which project it is in it.
//
// It reads the plugin's own IPC (`omarchy-shell agent-pet state`) rather than
// reaching into Service.qml: the service already publishes exactly this
// snapshot, and a bar widget that asks the same question a script would ask
// cannot drift from what the script reports.
BarWidget {
  id: root

  moduleName: "local.pi-pet"

  // The last snapshot that parsed. A failed poll leaves it alone; a poll that
  // exits non-zero clears it, because then the answer really is "nothing".
  property var info: null

  readonly property string mood: Model.moodOf(root.info)
  readonly property string lang: root.info && root.info.lang === "en" ? "en" : "zh"

  readonly property color foreground: Model.barValue(bar, "foreground", Commons.Color.foreground)
  readonly property color urgent: Model.barValue(bar, "urgent", Commons.Color.urgent)
  readonly property color accent: Model.barValue(bar, "accent", Commons.Color.accent)

  // Colour answers one question only: does this want you, is it busy, or is it
  // quiet. Everything else is in the shape of the face.
  readonly property color iconColor: root.mood === "waiting" || root.mood === "error"
    ? root.urgent
    : root.mood === "busy"
      ? root.accent
      : root.foreground

  readonly property real iconOpacity: root.mood === "hidden" || root.mood === "unknown" ? 0.45 : 1.0

  // argv, not a command line: `menu <screen> <x> <y>` is four arguments, and a
  // single string with spaces in it would be one.
  function run(method, args) {
    if (actionProc.running) return
    actionProc.command = ["omarchy-shell", "agent-pet", method].concat(args || [])
    actionProc.running = true
  }

  // The pet owns the menu — its animation tree, its chat box, its "tidy memory"
  // — so the bar does not draw a second one: it tells the pet where the icon is
  // and the pet opens the very same PetMenu there. Coordinates are window-local
  // on both sides (bar window and overlay both span their screen), so the point
  // only has to name the screen, not convert anything.
  function openPetMenu() {
    var win = button.QsWindow.window
    var screenName = win && win.screen ? win.screen.name : ""
    var corner = button.mapToItem(null, 0, 0)
    var x = Math.round(corner.x + button.width / 2)
    var y = Math.round(corner.y + button.height + Style.space(2))
    run("menu", [screenName, String(x), String(y)])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button

    anchors.fill: parent
    bar: root.bar
    tooltipText: Model.tooltip(root.info, root.mood, root.lang)

    iconComponent: Component {
      Item {
        PetGlyph {
          x: (parent.width - width) / 2
          y: (parent.height - height) / 2
          iconSize: button.iconSize
          color: root.iconColor
          opacity: root.iconOpacity
          mood: root.mood
        }
      }
    }

    // Left toggles the pet, right opens the action list. The pet's own menu
    // still has the animation tree; this one is the four things worth doing
    // without reaching for the pet.
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) {
        root.openPetMenu()
        return
      }
      root.run("toggle")
    }
  }

  // Three seconds: each poll is a process, and the phase is the pet's own
  // business — the overlay already animates it in the corner of the screen.
  // This only has to be fast enough to look live.
  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!stateProc.running) stateProc.running = true
  }

  Process {
    id: stateProc
    command: ["omarchy-shell", "agent-pet", "state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // A parse failure keeps the previous snapshot: the shell being busy for
        // one tick is not news.
        var next = Model.parseState(text)
        if (next) root.info = next
      }
    }
    stderr: StdioCollector { waitForEnd: true }
    // Non-zero means the target did not answer at all, and a face from three
    // seconds ago would be a lie.
    onExited: function(exitCode) { if (exitCode !== 0) root.info = null }
  }

  Process {
    id: actionProc
    command: []
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) { if (!stateProc.running) stateProc.running = true }
  }
}
