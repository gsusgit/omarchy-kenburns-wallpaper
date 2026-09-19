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

  // Which level each level-based control is on. The steppers' buttons and their
  // sliders both read these, so neither can disagree with the value applied.
  //
  // The zoom index runs low-to-high (1.10 to 1.30); the speed index is inverted
  // against the loop period it writes, because a short loop is the fast one.
  readonly property int zoomIndex: Settings.maxZoomLevelIndex(root.draft.maxZoom)
  readonly property int speedIndex: Settings.speedLevelIndex(root.draft.duration)

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

        // Five levels, walked with two buttons and drawn as five notches on the
        // slider between them. The slider is driven by the LEVEL INDEX rather than
        // by the zoom factor, so PanelSlider's own integer rounding does the
        // snapping and a drag can never land between levels.
        Row {
          width: parent.width
          spacing: Style.spacing.sm

          PanelActionButton {
            id: zoomDownBtn
            anchors.verticalCenter: parent.verticalCenter
            iconText: "\uf068"                       // Font Awesome minus
            tooltipText: "Less zoom"
            foreground: root.barForeground
            enabled: root.zoomIndex > 0
            onClicked: root.edit("maxZoom", Settings.MAXZOOM_LEVELS[root.zoomIndex - 1])
          }

          PanelSlider {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - zoomDownBtn.width - zoomUpBtn.width - parent.spacing * 2
            bar: root.bar
            minimum: 0
            maximum: Settings.MAXZOOM_LEVELS.length - 1
            integer: true
            tickCount: Settings.MAXZOOM_LEVELS.length
            value: root.zoomIndex
            onMoved: function(i) { root.edit("maxZoom", Settings.MAXZOOM_LEVELS[Math.round(i)]) }
          }

          PanelActionButton {
            id: zoomUpBtn
            anchors.verticalCenter: parent.verticalCenter
            iconText: "\uf067"                       // Font Awesome plus
            tooltipText: "More zoom"
            foreground: root.barForeground
            enabled: root.zoomIndex < Settings.MAXZOOM_LEVELS.length - 1
            onClicked: root.edit("maxZoom", Settings.MAXZOOM_LEVELS[root.zoomIndex + 1])
          }
        }

        PanelSeparator { foreground: root.barForeground }

        // --------------------------------------------------------- duration
        PanelSectionHeader {
          width: parent.width
          text: "SPEED"
          foreground: root.barForeground
          fontFamily: root.fontFamily
        }

        // The same five-level stepper as the zoom: two buttons with the slider
        // between them, and no number anywhere. The notches on the track are what
        // show how many levels there are and which one you are on, and they move
        // as you press.
        //
        // Everything here walks the SPEED index, which runs opposite to the loop
        // period: "less" is slower (a longer loop) and the slider's right end is the
        // quick one. Writing the period from a speed index is what keeps the two
        // from contradicting each other -- the first version had a "Slower" button
        // that actually shortened the loop.
        Row {
          width: parent.width
          spacing: Style.spacing.sm

          PanelActionButton {
            id: slowerBtn
            anchors.verticalCenter: parent.verticalCenter
            iconText: "\uf068"                       // Font Awesome minus
            tooltipText: "Slower"
            foreground: root.barForeground
            enabled: root.speedIndex > 0
            onClicked: root.edit("duration", Settings.durationForSpeedIndex(root.speedIndex - 1))
          }

          PanelSlider {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - slowerBtn.width - fasterBtn.width - parent.spacing * 2
            bar: root.bar
            minimum: 0
            maximum: Settings.DURATION_LEVELS.length - 1
            integer: true
            tickCount: Settings.DURATION_LEVELS.length
            value: root.speedIndex
            onMoved: function(i) { root.edit("duration", Settings.durationForSpeedIndex(i)) }
          }

          PanelActionButton {
            id: fasterBtn
            anchors.verticalCenter: parent.verticalCenter
            iconText: "\uf067"                       // Font Awesome plus
            tooltipText: "Faster"
            foreground: root.barForeground
            enabled: root.speedIndex < Settings.DURATION_LEVELS.length - 1
            onClicked: root.edit("duration", Settings.durationForSpeedIndex(root.speedIndex + 1))
          }
        }

        PanelSeparator { foreground: root.barForeground }

        // -------------------------------------------------------- directions
        PanelSectionHeader {
          width: parent.width
          text: "DIRECTION"
          foreground: root.barForeground
          fontFamily: root.fontFamily
        }

        // A 3x3 diana: the eight compass points plus the centre, so a diagonal is
        // one click -- no angle to convert and no pair of axis values to reason
        // about. No row label above it and no length slider below it: the section
        // header and the glyphs say everything, and the length is fixed at the
        // ceiling (see Service.qml). Left-aligned, flush with the panel's own
        // content, which is where a 3x3 block of chips belongs.
        //
        // ButtonGroup is a Row and cannot do 3x3, so this is a Grid of the same
        // chips; Button brings focus, tooltips and Enter/Space, and centres its own
        // content, so a chip wider than its glyph still reads as a button.
        Grid {
          id: driftGrid
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
