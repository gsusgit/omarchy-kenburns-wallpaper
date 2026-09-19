import QtQuick
import Quickshell
import qs.Ui

// Bar entry point for the animated wallpaper.
//
// The manifest points at this file; the small menu lives in Panel.qml and is
// loaded lazily below, exactly as Omarchy's own clock plugin does it (see
// https://plugins.omarchy.org/develop.html). This file owns the bar button and
// forwards the panel lifecycle so clicks, the shell commands
// (`omarchy-shell shell summon <id>`) and popout switching all reach the panel.
BarWidget {
  id: root
  moduleName: "gsus.animated-wallpaper"

  // The plugin is also a service (kind "service"); the shell keeps one instance
  // of it and the widget reads its live state from here.
  readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property bool animating: service ? service.enabled === true : false

  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true
    : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Menu.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf03e"                    // picture glyph (Font Awesome range)
    tooltipText: root.animating ? "Animated wallpaper — animating" : "Animated wallpaper — paused"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }
}
