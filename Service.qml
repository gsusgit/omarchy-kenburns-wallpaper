import QtQuick
import Quickshell
import Quickshell.Wayland
import QtQuick.Effects
import qs.Commons

// A soft glow that breathes over the wallpaper.
//
// It draws on the wl-layer-shell *bottom* layer: the wallpaper is painted by
// Omarchy's own background plugin on the *background* layer, and the inter-layer
// order (background < bottom < top < overlay) puts this surface on top of the
// wallpaper and underneath every window and the bar.
//
// Nothing about the wallpaper file is read or touched: the glow is additive
// light tinted with the theme accent, which is why it works with any wallpaper
// and any theme (and follows a theme switch live).
Item {
  id: root

  // Injected by the shell host.
  property var shell: null
  property string omarchyPath: ""
  property var manifest: null

  // ---------------------------------------------------------------- taste knobs
  readonly property real intensity: 0.16   // peak glow alpha. 0.10 subtle, 0.25 loud.
  readonly property int periodMs: 11000    // one full breath
  readonly property int frameMs: 70        // repaint interval (~14 fps)
  readonly property real scale: 1.3        // bloom size, as a multiple of screen width

  readonly property color accent: Color.accent !== undefined ? Color.accent : "#ffffff"

  // One clock drives everything: the glow's alpha is a function of `phase`, so
  // the repaint rate is ours to choose instead of the compositor's, and no
  // NumberAnimation runs per screen.
  property real phase: 0.5                 // 0.5 = starts at full glow

  Timer {
    interval: root.frameMs
    running: true
    repeat: true
    onTriggered: root.phase = (root.phase + root.frameMs / root.periodMs) % 1
  }

  Component.onCompleted: console.log("[animated-wallpaper] ready: screens="
    + Quickshell.screens.length + " intensity=" + root.intensity
    + " periodMs=" + root.periodMs + " accent=" + root.accent)

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: win
      required property var modelData
      screen: modelData

      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }

      // Visual only: an empty input region, so the surface never eats a click.
      // Without this, double-clicking the desktop would stop opening Omarchy's
      // background switcher.
      mask: Region { }
      // Never reserve space or push windows around.
      exclusionMode: ExclusionMode.Ignore

      WlrLayershell.namespace: "gsus-animated-wallpaper"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      Item {
        id: bloom
        width: win.width * root.scale
        height: width
        anchors.centerIn: parent
        opacity: root.intensity * (0.5 - 0.5 * Math.cos(2 * Math.PI * root.phase))

        // The source stays hidden; MultiEffect draws the tinted copy in its
        // place. colorization recolours the white texture without touching its
        // alpha, so the radial falloff survives.
        Image {
          id: texture
          anchors.fill: parent
          source: Qt.resolvedUrl("glow.png")
          fillMode: Image.PreserveAspectFit
          visible: false
        }

        MultiEffect {
          source: texture
          anchors.fill: texture
          colorization: 1.0
          colorizationColor: root.accent
        }
      }
    }
  }
}
