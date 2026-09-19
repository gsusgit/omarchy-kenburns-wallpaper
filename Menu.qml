import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Settings.js" as Settings

// The small menu behind the bar button: every user-facing parameter of the
// animation, live.
//
// This is the ONLY writer of settings.json. The service reads the file (its own
// FileView watches it) and applies whatever it finds, so the two never fight
// over the same file. A control changes the value locally and writes once it is
// done being dragged -- writing on every pixel of a drag would rewrite the file
// dozens of times a second for no reason.
Panel {
  id: root
  moduleName: "gsus.animated-wallpaper"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  // The service is the source of truth; until it exists, show the defaults.
  readonly property var cfg: service && service.config ? service.config : Settings.sanitize({})

  readonly property string wallpaper: service && service.displayPath
    ? String(service.displayPath).split("/").pop()
    : "-"
  readonly property string variant: service && service.variant ? String(service.variant) : "-"

  readonly property color dim: Qt.darker(root.barForeground, 1.55)
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  function open() {
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  // ------------------------------------------------------------------ config
  // The service owns the file (it reads AND writes it, so there is exactly one
  // writer and no chance of the two ends fighting over it). The menu only sets
  // values and asks it to save once a control stops being dragged -- writing on
  // every pixel of a drag would rewrite the file dozens of times a second.
  function set(key, value) {
    if (!root.service) return
    root.service.set(key, value)
  }

  function flush() {
    if (!root.service) return
    root.service.save()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(8)

        Text {
          width: parent.width
          text: "Animated wallpaper"
          color: root.barForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          text: (root.cfg.enabled ? "Animating" : "Paused")
                + "  ·  " + root.variant
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          width: parent.width
          text: "zoom " + (root.service ? root.service.zoom.toFixed(3) : "1.000")
                + "x  ·  " + root.wallpaper
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideMiddle
        }

        Rectangle {
          width: parent.width
          height: 1
          color: root.dim
          opacity: 0.35
        }

        // ------------------------------------------------------- enable
        Row {
          width: parent.width
          spacing: Style.space(10)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - enableSwitch.width - parent.spacing
            text: "Animate"
            color: root.barForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          ToggleSwitch {
            id: enableSwitch
            anchors.verticalCenter: parent.verticalCenter
            checked: root.cfg.enabled === true
            foreground: root.barForeground
            onToggled: {
              root.set("enabled", !root.cfg.enabled)
              root.flush()
            }
          }
        }

        // ------------------------------------------------------- duration
        Text {
          width: parent.width
          text: "Duration  " + Math.round(root.cfg.duration) + " s"
          color: root.barForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        PanelSlider {
          width: parent.width
          bar: root.bar
          minimum: Settings.LIMITS.duration.min
          maximum: Settings.LIMITS.duration.max
          step: 1
          integer: true
          value: root.cfg.duration
          onMoved: function(v) { root.set("duration", v) }
          onReleased: root.flush()
        }

        // ------------------------------------------------------- maxZoom
        Text {
          width: parent.width
          text: "Zoom level  " + root.cfg.maxZoom.toFixed(2) + "x"
          color: root.barForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        PanelSlider {
          width: parent.width
          bar: root.bar
          minimum: Settings.LIMITS.maxZoom.min
          maximum: Settings.LIMITS.maxZoom.max
          step: 0.01
          value: root.cfg.maxZoom
          onMoved: function(v) { root.set("maxZoom", v) }
          onReleased: root.flush()
        }

        // ------------------------------------------------------- pauseAtEnd
        Text {
          width: parent.width
          text: "Pause at end  " + Number(root.cfg.pauseAtEnd).toFixed(1) + " s"
          color: root.barForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        PanelSlider {
          width: parent.width
          bar: root.bar
          minimum: Settings.LIMITS.pauseAtEnd.min
          maximum: Settings.LIMITS.pauseAtEnd.max
          step: 0.5
          value: root.cfg.pauseAtEnd
          onMoved: function(v) { root.set("pauseAtEnd", v) }
          onReleased: root.flush()
        }

        // ------------------------------------------------------- mode
        Dropdown {
          width: parent.width
          label: "Direction mode"
          fontFamily: root.fontFamily
          options: Settings.modeOptions()
          value: root.cfg.mode
          onChanged: function(v) {
            root.set("mode", v)
            root.flush()
          }
        }

        // ------------------------------------------------------- easing
        Row {
          width: parent.width
          spacing: Style.space(10)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - easingSwitch.width - parent.spacing
            text: root.cfg.smoothEasing ? "Smooth motion (ease in-out)" : "Smooth motion (linear)"
            color: root.barForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          ToggleSwitch {
            id: easingSwitch
            anchors.verticalCenter: parent.verticalCenter
            checked: root.cfg.smoothEasing === true
            foreground: root.barForeground
            onToggled: {
              root.set("smoothEasing", !root.cfg.smoothEasing)
              root.flush()
            }
          }
        }

        // ------------------------------------------------------- reset
        Row {
          width: parent.width
          spacing: Style.space(10)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - resetBtn.width - parent.spacing
            text: "Reset to defaults"
            color: root.barForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          PanelActionButton {
            id: resetBtn
            anchors.verticalCenter: parent.verticalCenter
            iconText: "\uf021"                       // Font Awesome refresh
            tooltipText: "Reset duration, zoom, mode and easing"
            foreground: root.barForeground
            onClicked: {
              if (!root.service) return
              root.service.config = Settings.sanitize({})
              root.flush()
            }
          }
        }
      }
    }
  }
}
