pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons

// The pet, drawn as modules on a ten-by-ten grid so the bar icon needs no
// sprite, no WebP decoder and no animation timer: at thirteen pixels the eyes
// and the mouth are all that survive anyway.
//
// Mood changes the face; colour is chosen by the caller. That split means the
// glyph never has to know what "waiting" means.
Item {
  id: root

  property real iconSize: Style.fontToken("icon", 13)
  property color color: "white"

  // idle | hidden | unknown | busy | waiting | done | error
  property string mood: "idle"

  width: iconSize
  height: iconSize
  readonly property real unit: width / 10

  // A pixel is the floor for every measurement here: half a module at 13px is
  // not a thin line, it is nothing at all.
  function px(value) {
    return Math.max(1, value * unit)
  }

  readonly property string eyes: root.mood === "busy" || root.mood === "error"
    ? "open"
    : root.mood === "waiting"
      ? "wide"
      : "closed"

  readonly property string mouth: root.mood === "waiting"
    ? "open"
    : root.mood === "done"
      ? "smile"
      : "flat"

  // Two ear nubs, drawn before the head so the outline stays unbroken in front
  // of them: the silhouette then reads as a creature, not a speech bubble.
  Repeater {
    model: [0.35, 7.05]

    Rectangle {
      required property var modelData
      x: root.px(modelData)
      y: root.px(0.7)
      width: root.px(2.6)
      height: root.px(2.0)
      radius: root.px(0.9)
      color: root.color
    }
  }

  // Head: an outline, so the eyes keep their contrast whatever the bar
  // background is.
  Rectangle {
    x: root.px(0.6)
    y: root.px(1.6)
    width: root.px(8.8)
    height: root.px(7.6)
    radius: root.px(2.6)
    color: "transparent"
    border.width: root.px(1.1)
    border.color: root.color
  }

  // Eyes.
  Repeater {
    model: [2.9, 5.9]

    Rectangle {
      required property var modelData
      x: root.px(modelData)
      width: root.eyes === "closed" ? root.px(1.7) : root.eyes === "wide" ? root.px(1.9) : root.px(1.3)
      height: root.eyes === "closed" ? root.px(0.55) : width
      radius: height / 2
      // Closed eyes sit a little higher: a dash on the eye line reads as a
      // squint, a dash above it reads as content.
      y: root.eyes === "closed" ? root.px(3.8) : root.px(3.5)
      color: root.color
    }
  }

  // Mouth: one bar, or three modules stepped into a small smile.
  Rectangle {
    visible: root.mouth !== "smile"
    x: root.px(3.9)
    y: root.px(6.4)
    width: root.px(2.2)
    height: root.mouth === "open" ? root.px(1.3) : root.px(0.6)
    radius: root.px(0.35)
    color: root.color
  }

  Repeater {
    model: root.mouth === "smile" ? [0, 1, 2] : []

    Rectangle {
      required property var modelData
      x: root.px(3.4 + modelData * 1.1)
      y: root.px(6.4 + (modelData === 1 ? 0.55 : 0))
      width: root.px(1.0)
      height: root.px(0.6)
      radius: height / 2
      color: root.color
    }
  }
}
