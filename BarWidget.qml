import QtQuick
import "Model.js" as Model
import Quickshell
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
  readonly property var hoverItems: panelLoader.item ? (panelLoader.item.hoverItems || []) : []
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
    // Omarchy's shared tooltip is intentionally plain text. Tempest owns this
    // non-modal tooltip so only metric values receive semantic colors.
    tooltipText: ""

    property bool weatherTooltipReady: false

    HoverHandler {
      id: weatherTooltipHover
      onHoveredChanged: {
        if (hovered) weatherTooltipDelay.restart()
        else {
          weatherTooltipDelay.stop()
          button.weatherTooltipReady = false
        }
      }
    }

    Timer {
      id: weatherTooltipDelay
      interval: 500
      onTriggered: button.weatherTooltipReady = weatherTooltipHover.hovered
    }

    PopupWindow {
      id: weatherTooltipWindow

      visible: button.weatherTooltipReady && root.hoverItems.length > 0
      color: "transparent"
      implicitWidth: Math.ceil(weatherTooltipBubble.implicitWidth)
      implicitHeight: Math.ceil(weatherTooltipBubble.implicitHeight)

      anchor {
        id: weatherTooltipAnchor
        window: button.QsWindow.window
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.width: 1
        rect.height: 1

        onAnchoring: {
          var window = button.QsWindow.window
          if (!window || !root.bar) return

          var popupWidth = weatherTooltipWindow.implicitWidth
          var popupHeight = weatherTooltipWindow.implicitHeight
          var localX = button.width / 2 - popupWidth / 2
          var localY = button.height + 6

          if (root.bar.position === "bottom") {
            localY = -popupHeight - 6
          } else if (root.bar.position === "left") {
            localX = button.width + 6
            localY = button.height / 2 - popupHeight / 2
          } else if (root.bar.position === "right") {
            localX = -popupWidth - 6
            localY = button.height / 2 - popupHeight / 2
          }

          var point = window.contentItem.mapFromItem(button, localX, localY)
          weatherTooltipAnchor.rect.x = Math.round(point.x)
          weatherTooltipAnchor.rect.y = Math.round(point.y)
        }
      }

      Rectangle {
        id: weatherTooltipBubble
        anchors.fill: parent
        implicitWidth: weatherTooltipContent.implicitWidth + 20
        implicitHeight: weatherTooltipContent.implicitHeight + 14
        color: root.bar ? root.bar.background : "#1A1B26"
        border.color: Qt.rgba(button.foreground.r, button.foreground.g, button.foreground.b, 0.25)
        border.width: 1
        radius: 0

        Row {
          id: weatherTooltipContent
          anchors.centerIn: parent
          spacing: Style.space(8)

          Repeater {
            model: root.hoverItems

            Row {
              required property var modelData
              required property int index
              spacing: Style.space(4)

              Text {
                visible: index > 0
                text: "·"
                color: button.foreground
                font.family: button.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                text: modelData.icon + " " + modelData.label
                color: button.foreground
                font.family: button.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                text: modelData.value
                color: Model.semanticHex(modelData.level)
                font.family: button.fontFamily
                font.pixelSize: Style.font.body
                font.weight: Font.DemiBold
              }
            }
          }
        }
      }
    }

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
