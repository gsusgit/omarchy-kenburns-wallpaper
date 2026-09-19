import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Settings.js" as Settings

// The settings panel behind the bar button.
//
// The panel edits a LOCAL DRAFT: nothing reaches the service (so nothing
// animates differently, and nothing is written to disk) until Apply is pressed.
// That is what makes "unsaved changes" a real, visible state instead of a hope,
// and it means a slider drag can never leave a half-chosen value behind.
//
// Deliberately small. Four values, two of them sliders, and every control
// changes something you can see. Removed after living with them: the preset
// dropdown (a shortcut through these values, not an effect of its own), the
// handheld shake and the breathing loop (both read as the wallpaper misbehaving
// rather than as camera work) and the smooth-motion toggle (ease-in-out is
// simply the better default, and the toggle only offered a worse one).
//
// Animate ("enabled") lives in the header with the reset action: it is a
// transport control, not a motion setting.
//
// Both callers that change the settings (this panel and the service's IPC
// surface) go through the service: it owns the file.
Panel {
  id: root
  moduleName: "gsus.animated-wallpaper"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
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
  // edit of the settings file) shows up in the panel, and unsaved edits survive
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

        // ------------------------------------------------------------ header
        // The switch and the reset sit next to the title: Animate turns the
        // effect on and off, so it is not one more row among the motion values.
        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - resetBtn.width - animateSwitch.width - parent.spacing * 2
            text: "Animated wallpaper"
            color: root.barForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
          }

          // Loads the defaults into the panel only. Apply is still required, so
          // this is undoable by reopening the panel.
          PanelActionButton {
            id: resetBtn
            anchors.verticalCenter: parent.verticalCenter
            iconText: "\uf021"                       // Font Awesome refresh
            tooltipText: "Reset to defaults"
            foreground: root.barForeground
            onClicked: root.editAll(Settings.sanitize({}))
          }

          ToggleSwitch {
            id: animateSwitch
            anchors.verticalCenter: parent.verticalCenter
            checked: root.draft.enabled === true
            foreground: root.barForeground
            onToggled: root.edit("enabled", !root.draft.enabled)

            PanelToolTip {
              visible: animateSwitch.containsMouse
              text: root.draft.enabled ? "ON" : "OFF"
              fontFamily: root.fontFamily
            }
          }
        }

        // The panel's whole "you have not applied this yet" signal, alongside
        // the Apply button lighting up.
        Text {
          width: parent.width
          visible: root.dirty
          text: "\u25cf Unsaved changes"
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }

        PanelSeparator { foreground: root.barForeground }

        // ------------------------------------------------------------- zoom
        PanelSectionHeader {
          width: parent.width
          text: "ZOOM"
          foreground: root.barForeground
          fontFamily: root.fontFamily
        }

        // The section header names the value, and it is the only control here, so
        // it needs no row label of its own.
        PanelSlider {
          width: parent.width
          bar: root.bar
          minimum: Settings.LIMITS.maxZoom.min
          maximum: Settings.LIMITS.maxZoom.max
          step: Settings.STEPS.maxZoom
          value: root.draft.maxZoom
          // PanelSlider never applies `step` on the mouse path, so snap here;
          // see snapToStep for why a raw drag value cannot be trusted.
          onMoved: function(v) {
            root.edit("maxZoom", Settings.snapToStep(v, Settings.STEPS.maxZoom, Settings.LIMITS.maxZoom.min))
          }
        }

        PanelSeparator { foreground: root.barForeground }

        // --------------------------------------------------------- duration
        PanelSectionHeader {
          width: parent.width
          text: "DURATION"
          foreground: root.barForeground
          fontFamily: root.fontFamily
        }

        Text {
          width: parent.width
          // One loop, not one traverse: the main leg is three quarters of this
          // and the return takes the rest.
          text: "Amount  " + Math.round(root.draft.duration) + " seconds"
          color: root.barForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        PanelSlider {
          width: parent.width
          bar: root.bar
          minimum: Settings.LIMITS.duration.min
          maximum: Settings.LIMITS.duration.max
          step: Settings.STEPS.duration
          integer: true
          value: root.draft.duration
          onMoved: function(v) {
            root.edit("duration", Settings.snapToStep(v, Settings.STEPS.duration, Settings.LIMITS.duration.min))
          }
        }

        PanelSeparator { foreground: root.barForeground }

        // -------------------------------------------------------- directions
        PanelSectionHeader {
          width: parent.width
          text: "DIRECTIONS"
          foreground: root.barForeground
          fontFamily: root.fontFamily
        }

        Text {
          width: parent.width
          text: "Drift"
          color: root.barForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        // A 3x3 diana: the eight compass points plus the centre, so a diagonal is
        // one click -- no angle to convert and no pair of axis values to reason
        // about. ButtonGroup is a Row, so this is a Grid of the same chips;
        // Button already brings focus and Enter/Space, and it centres its own
        // content, which is why a chip wider than its glyph still reads as a
        // button rather than as a left-aligned label.
        Item {
          width: parent.width
          height: driftGrid.height

          Grid {
            id: driftGrid
            anchors.horizontalCenter: parent.horizontalCenter
            columns: 3
            spacing: Style.spacing.sm

            Repeater {
              model: Settings.driftOptions()

              delegate: Button {
                required property var modelData
                width: Style.spacing.controlHeight * 1.5
                height: Style.spacing.controlHeight
                text: modelData.label
                tooltipText: modelData.tooltip
                selected: root.draft.drift === modelData.value
                bordered: true
                foreground: root.barForeground
                accent: Color.accent
                background: "transparent"
                fontFamily: root.fontFamily
                onClicked: root.edit("drift", modelData.value)
              }
            }
          }
        }

        Text {
          width: parent.width
          // As a fraction of the margin the zoom opens, so the number means the
          // same thing whatever the zoom is set to.
          text: "Length  " + Math.round(root.draft.driftLength * 100) + "%"
          color: root.barForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        PanelSlider {
          width: parent.width
          bar: root.bar
          minimum: Settings.LIMITS.driftLength.min
          maximum: Settings.LIMITS.driftLength.max
          step: Settings.STEPS.driftLength
          value: root.draft.driftLength
          onMoved: function(v) {
            root.edit("driftLength", Settings.snapToStep(v, Settings.STEPS.driftLength, Settings.LIMITS.driftLength.min))
          }
        }

        PanelSeparator { foreground: root.barForeground }

        // ------------------------------------------------------ apply
        Button {
          id: applyBtn
          width: parent.width
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
