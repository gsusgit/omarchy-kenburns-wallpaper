import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The small menu behind the bar button.
//
// KeyboardPanel anchors it to the bar button and renders the surface;
// PanelKeyCatcher makes Escape close it and Tab switch to the neighbouring
// panel. Content is a plain Column: title, live state, separator, then the
// actions. Add rows to the `actions` column.
//
// Live state comes from the plugin's own service instance, so the numbers here
// are the same ones the wallpaper is using.
Panel {
  id: root
  moduleName: "gsus.animated-wallpaper"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property bool animating: service ? service.enabled === true : false
  readonly property real zoom: service ? service.zoom : 1
  readonly property real motion: service ? service.motion : 0
  readonly property string wallpaper: service && service.displayPath
    ? String(service.displayPath).split("/").pop()
    : "—"

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

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(280))
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
          text: root.animating ? "Animating" : "Paused"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          width: parent.width
          text: "zoom " + root.zoom.toFixed(3) + "×  ·  motion " + Math.round(root.motion * 100) + "%"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          width: parent.width
          text: root.wallpaper
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

        // ------------------------------------------------------------ actions
        // Add menu rows here. Each one should read state off `root.service`
        // (the plugin's service instance) and write back to it.
        Row {
          id: actions
          width: parent.width
          spacing: Style.space(10)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: actions.width - animateSwitch.width - actions.spacing
            text: "Animate"
            color: root.barForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          ToggleSwitch {
            id: animateSwitch
            anchors.verticalCenter: parent.verticalCenter
            checked: root.animating
            foreground: root.barForeground
            onToggled: {
              if (!root.service) return
              root.service.enabled = !root.animating
            }
          }
        }
      }
    }
  }
}
