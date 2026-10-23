import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "KenBurnsSettings.js" as Settings

// Bar entry point for Ken Burns Wallpaper.
//
// The manifest points at this file; the small menu lives in Menu.qml and is
// loaded lazily below, exactly as Omarchy's own clock plugin does it (see
// https://omarchyplugins.com/develop). This file owns the bar button and
// forwards the panel lifecycle so clicks, the shell commands
// (`omarchy-shell shell summon <id>`) and popout switching all reach the panel.
BarWidget {
  id: root
  moduleName: "io.github.gsusgit.kenburnswallpaper"

  // Own facade: serviceFor(moduleName) is this plugin's service. Inside the
  // tray the facade is the tray's, that lookup is null, and hostedService is
  // the same singleton the shell loaded.
  property var hostedService: null
  property var unwatchService: null
  readonly property var service: {
    var found = bar && bar.shell && typeof bar.shell.serviceFor === "function"
      ? bar.shell.serviceFor(moduleName) : null
    return found || hostedService
  }

  Component.onCompleted: {
    root.unwatchService = Settings.watchService(function(next) { root.hostedService = next })
  }
  Component.onDestruction: Settings.unwatchService(root.unwatchService)
  // On only when the layer would map. enabled=true with mode=image, or
  // mode=kenburns with the switch off, both show as off.
  readonly property bool animating: service
    ? service.enabled === true && service.wallpaperMode === "kenburns"
    : false

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
    // Reload the panel when the plugin hot-reloads: KenBurnsSettings.js is a library
    // and can stay cached, but the menu QML must not keep an old instance.
    source: Qt.resolvedUrl("Menu.qml?v=factory-reset")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.animating ? "Ken Burns - ON" : "Ken Burns - OFF"
    dimmed: !root.animating
    iconComponent: Component {
      Item {
        ApertureIcon {
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: button.foreground
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) {
        root.toggle()
        return
      }
      if (buttonCode === Qt.RightButton && root.service) {
        root.service.set("enabled", !root.animating)
        root.service.save()
      }
    }
  }
}
