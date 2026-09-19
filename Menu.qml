import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Settings.js" as Settings

// The settings panel behind the bar button.
//
// The panel edits a LOCAL DRAFT: nothing reaches the service (and therefore
// nothing animates differently, and nothing is written to disk) until Apply is
// pressed. That is what makes "unsaved changes" a real, visible state instead of
// a hope -- and it means a slider drag can never leave a half-chosen value
// behind. The service remains the only writer of settings.json.
Panel {
  id: root
  moduleName: "gsus.animated-wallpaper"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property color dim: Qt.darker(root.barForeground, 1.55)
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  // ------------------------------------------------------------------- draft
  property var draft: Settings.sanitize({})
  property bool dirty: false

  // Compare canonically: two configs that differ only in key order or in a
  // numeric type are the same settings, and should not light up "unsaved".
  function matchesApplied() {
    if (!root.service) return true
    return Settings.serialise(root.draft) === Settings.serialise(root.service.config)
  }

  function loadDraft() {
    root.draft = Settings.sanitize(root.service ? root.service.config : {})
    root.dirty = false
  }

  function editAll(next) {
    root.draft = Settings.sanitize(next)
    root.dirty = !root.matchesApplied()
  }

  function edit(key, value) {
    var next = {}
    for (var k in root.draft) next[k] = root.draft[k]
    next[key] = value
    root.editAll(next)
  }

  function apply() {
    if (!root.service) return
    root.service.config = root.draft
    root.service.save()
    root.dirty = false
  }

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

  // The draft starts from whatever is applied, and follows the service only
  // while there is nothing unsaved to lose -- so an external change (IPC, a hand
  // edit of settings.json) shows up in the panel, and unsaved edits survive
  // closing and reopening the panel instead of being silently thrown away.
  function syncFromService() {
    if (root.dirty) return
    root.loadDraft()
  }

  onServiceChanged: root.syncFromService()
  Component.onCompleted: root.loadDraft()

  Connections {
    target: root.service
    function onConfigChanged() { root.syncFromService() }
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

        // The only thing above the controls, and only when it has something to
        // say. It is the panel's whole "you have not applied this yet" signal.
        Text {
          width: parent.width
          visible: root.dirty
          text: "\u25cf Unsaved changes"
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
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
            checked: root.draft.enabled === true
            foreground: root.barForeground
            onToggled: root.edit("enabled", !root.draft.enabled)
          }
        }

        // ------------------------------------------------------- duration
        Text {
          width: parent.width
          text: "Duration  " + Math.round(root.draft.duration) + " s"
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
          value: root.draft.duration
          onMoved: function(v) {
            root.edit("duration", Settings.snapToStep(v, 1, Settings.LIMITS.duration.min))
          }
        }

        // ------------------------------------------------------- maxZoom
        Text {
          width: parent.width
          text: "Zoom level  " + root.draft.maxZoom.toFixed(2) + "x"
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
          value: root.draft.maxZoom
          onMoved: function(v) {
            root.edit("maxZoom", Settings.snapToStep(v, 0.01, Settings.LIMITS.maxZoom.min))
          }
        }

        // ------------------------------------------------------- pauseAtEnd
        Text {
          width: parent.width
          text: "Pause at end  " + Number(root.draft.pauseAtEnd).toFixed(1) + " s"
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
          value: root.draft.pauseAtEnd
          onMoved: function(v) {
            root.edit("pauseAtEnd", Settings.snapToStep(v, 0.5, Settings.LIMITS.pauseAtEnd.min))
          }
        }

        // ------------------------------------------------------- mode
        Dropdown {
          width: parent.width
          label: "Direction mode"
          fontFamily: root.fontFamily
          options: Settings.modeOptions()
          value: root.draft.mode
          onChanged: function(v) { root.edit("mode", v) }
        }

        // ------------------------------------------------------- easing
        Row {
          width: parent.width
          spacing: Style.space(10)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - easingSwitch.width - parent.spacing
            text: root.draft.smoothEasing ? "Smooth motion (ease in-out)" : "Smooth motion (linear)"
            color: root.barForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          ToggleSwitch {
            id: easingSwitch
            anchors.verticalCenter: parent.verticalCenter
            checked: root.draft.smoothEasing === true
            foreground: root.barForeground
            onToggled: root.edit("smoothEasing", !root.draft.smoothEasing)
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: root.dim
          opacity: 0.35
        }

        // ------------------------------------------------- apply / reset
        Row {
          width: parent.width
          spacing: Style.space(8)

          // Loads the defaults into the panel only. Apply is still required, so
          // this is undoable by reopening the panel.
          PanelActionButton {
            id: resetBtn
            anchors.verticalCenter: parent.verticalCenter
            iconText: "\uf021"                       // Font Awesome refresh
            tooltipText: "Load the defaults into the panel"
            foreground: root.barForeground
            onClicked: root.editAll(Settings.sanitize({}))
          }

          Button {
            id: applyBtn
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - resetBtn.width - parent.spacing
            text: root.dirty ? "Apply changes" : "Apply"
            fontFamily: root.fontFamily
            // Deliberately NOT `selected`: this theme sets the selected-color
            // token to #f6dcac, which is its foreground too, so a selected button
            // reads as ordinary text on a faint wash. Driving the label and the
            // fill from Color.accent (#faa968 here) makes the button the same
            // orange as the "Unsaved changes" dot above it, so the two signals
            // say the same thing at a glance.
            foreground: root.dirty ? Color.accent : root.barForeground
            accent: Color.accent
            background: root.dirty ? Style.selectedAccentFill : "transparent"
            bordered: true
            opacity: root.dirty ? 1 : 0.6
            onClicked: root.apply()
          }
        }
      }
    }
  }
}
