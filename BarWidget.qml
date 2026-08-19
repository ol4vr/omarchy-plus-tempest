import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.ol4vr.tempest"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  // Shape contract for shell.summon/hide/toggle routing (Bar.findPanelWidget
  // requires open/close/opened on the bar-widget root). Open maps to the
  // panel's hotkey path so summoning suppresses the center hover reveal,
  // matching what the old per-plugin IpcHandler did.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity: Bar.requestPopout prefers closeForPopoutSwitch over close, and
  // KeyboardPanel reads popoutSwitchClosing back off its owner.
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  readonly property string iconText: panelLoader.item ? (panelLoader.item.label || "") : ""
  readonly property string tempText: panelLoader.item ? (panelLoader.item.barTemp || "") : ""
  readonly property string hoverSummary: panelLoader.item ? (panelLoader.item.hoverSummary || "") : ""
  readonly property string displayText: (iconText && tempText) ? (iconText + "  " + tempText) : (tempText || iconText)
  readonly property var verticalLines: {
    var parts = []
    if (iconText !== "") parts.push(iconText)
    if (tempText !== "") parts.push(tempText)
    return parts
  }
  readonly property real openPanelIndicatorWidth: button.labelWidth

  visible: displayText !== ""
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
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
    text: root.vertical ? "" : root.displayText
    labelVisible: !root.vertical
    hasVisualContent: root.displayText !== ""
    fixedHeight: root.vertical ? root.verticalLines.length * Style.bar.iconSlot : -1
    horizontalMargin: 8.75
    tooltipText: root.hoverSummary

    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.RightButton) root.bar.run("omarchy-notification-send \"$(omarchy-weather-status)\"")
      else if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }

    Column {
      visible: root.vertical
      anchors.fill: parent

      Repeater {
        model: root.vertical ? root.verticalLines : []

        OpticalGlyph {
          required property string modelData
          width: button.width
          height: Style.bar.iconSlot
          text: modelData
          fontFamily: button.fontFamily
          fontSize: button.fontSize
          color: button.foreground
        }
      }
    }
  }
}
