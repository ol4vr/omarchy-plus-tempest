import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.ol4vr.tempest"
  ipcTarget: "io.github.ol4vr.tempest"
  manageIpc: false

  property var anchorItem: null
  property bool openedFromHotkey: false

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
    locationFile.reload()
    root.refresh()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    locationFile.reload()
    root.refresh()
    // Set after showing, not before: showing hands the popout coordinator
    // over, which closes whichever panel was open, and that close clears the
    // shared flag. Deferring means the panel taking over always wins, while
    // a handoff to a panel that does not manage the flag still leaves it
    // cleared rather than stuck on.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    if (root.editingLocation) root.cancelEditingLocation()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  // Parsed wttr.in j1 response. Kept on failure so stale data stays visible.
  property var report: null
  property var dailyForecastReport: null
  property var airQualityReport: null
  property string wttrLocation: ""

  // Configured location, read from the weather.json state file (owned by
  // omarchy-weather-location). The query is the wttr.in path segment
  // (coordinates when stored, else the encoded name); empty means IP
  // auto-detect. The watch makes hand edits take effect live.
  property var configuredLocationState: ({ name: "", latitude: null, longitude: null })
  readonly property string configuredLocation: configuredLocationState.name
  readonly property string locationQuery: Model.wttrLocationQuery(configuredLocationState.name, configuredLocationState.latitude, configuredLocationState.longitude)

  // Keep the previous report visible while the new location loads. The
  // editor remains open with a spinner, so stale data is never presented
  // under the newly configured location label.
  onLocationQueryChanged: {
    if (savingLocation) savingLocationQueryStarted = true
    forecastRetries = 0
    dailyForecastRetries = 0
    airQualityRetries = 0
    forecastProc.running = false
    dailyForecastProc.running = false
    airQualityProc.running = false
    airQualityReport = null
    Qt.callLater(refresh)
  }

  property FileView locationFile: FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.configuredLocationState = Model.parseLocationFile(text())
    onLoadFailed: root.configuredLocationState = Model.parseLocationFile("")
  }

  // The first read can race shell startup (observed sporadically), leaving a
  // stored location unhonored until the next file write. One delayed reload
  // self-corrects; if the first read was fine it's a no-op, since identical
  // state doesn't change locationQuery and so triggers no refetch.
  Timer {
    interval: 1500
    running: true
    onTriggered: locationFile.reload()
  }

  property int forecastRetries: 0
  property int dailyForecastRetries: 0
  property int airQualityRetries: 0

  // Click-to-edit state for the location label.
  property bool editingLocation: false
  property bool savingLocation: false
  property bool savingLocationQueryStarted: false
  property var locationSuggestions: []
  property int suggestionIndex: 0
  property string geocodePendingQuery: ""
  property string geocodeActiveQuery: ""

  // Shared hero/bar icon state, updated with each successful weather response.
  property string label: ""

  // wttr's current conditions when available; open-meteo's (bundled with the
  // much faster daily forecast fetch) fill the hero while wttr is in flight.
  readonly property bool hasConfiguredCoordinates: !isNaN(parseFloat(String(configuredLocationState.latitude))) && !isNaN(parseFloat(String(configuredLocationState.longitude)))
  readonly property var openMeteoCurrent: Model.openMeteoCurrentCondition(dailyForecastReport)
  readonly property var current: (hasConfiguredCoordinates && openMeteoCurrent) ? openMeteoCurrent : ((report && report.current_condition && report.current_condition[0]) ? report.current_condition[0] : openMeteoCurrent)
  readonly property var areaInfo: report && report.nearest_area && report.nearest_area[0] ? report.nearest_area[0] : null
  readonly property var forecastDays: buildForecastDays()
  readonly property string currentHour: Qt.formatDateTime(new Date(), "yyyy-MM-ddTHH:00")
  readonly property var hourlyForecast: Model.openMeteoHourly(dailyForecastReport, currentHour, 6, useImperial)
  readonly property var dayDetails: Model.openMeteoDayDetails(dailyForecastReport, Qt.formatDate(new Date(), "yyyy-MM-dd"), useImperial)
  readonly property var airQuality: Model.airQualitySummary(airQualityReport)
  readonly property var pollen: Model.pollenItems(airQualityReport, 24)
  readonly property var highlights: Model.weatherHighlights(hourlyForecast, dayDetails, useImperial)
  readonly property string reportCountry: areaInfo && areaInfo.country && areaInfo.country[0] ? areaInfo.country[0].value : ""

  readonly property bool useImperial: Model.shouldUseImperial(setting("unit", ""), Qt.locale().name, reportCountry)

  // Auto-refresh interval in minutes; clamped to a sane minimum.
  readonly property int refreshMinutes: Math.max(1, parseInt(setting("refreshMinutes", 15), 10) || 15)

  readonly property string reportLocation:  configuredLocation || wttrLocation || (areaInfo && areaInfo.areaName && areaInfo.areaName[0] ? areaInfo.areaName[0].value : "")
  readonly property string reportTempNum:   current ? String(useImperial ? current.temp_F : current.temp_C) : ""
  readonly property string tempUnit:        "°" + (useImperial ? "F" : "C")
  readonly property string barTemp: reportTempNum !== "" ? (reportTempNum + "°") : ""
  // Icon + temp for the bar. `label` stays icon-only so the popup hero is unchanged.
  readonly property string barLabel: (label && barTemp) ? (label + "  " + barTemp) : (barTemp || label)
  readonly property string reportFeels:     current ? formatTemp(useImperial ? current.FeelsLikeF : current.FeelsLikeC) : ""
  readonly property string reportWind:      current ? (useImperial ? (current.windspeedMiles + " mph") : (current.windspeedKmph + " km/h")) : ""
  readonly property string reportHumidity:  current ? (current.humidity + "%") : ""
  readonly property string reportVisibility: openMeteoCurrent && openMeteoCurrent.visibilityKm !== "" ? (openMeteoCurrent.visibilityKm + " km") : ""
  readonly property string hoverSummary: Model.hoverSummary(current, hourlyForecast, airQuality, pollen, useImperial)
  readonly property var detailItems: [
    { icon: "", label: "SUNRISE", value: dayDetails.sunrise || "—", level: "neutral" },
    { icon: "", label: "SUNSET", value: dayDetails.sunset || "—", level: "neutral" },
    { icon: "", label: "DAYLIGHT", value: dayDetails.daylight || "—", level: "neutral" },
    { icon: "󰖨", label: "UV MAX", value: dayDetails.uvMax || "—", level: Model.weatherMetricLevel("uv", dayDetails.uvMax) },
    { icon: "󰖝", label: "GUST MAX", value: dayDetails.gust ? (dayDetails.gust + " " + dayDetails.gustUnit) : "—", level: Model.weatherMetricLevel("gust", dayDetails.gustKmh) },
    { icon: "", label: "VISIBILITY", value: reportVisibility || "—", level: Model.weatherMetricLevel("visibility", openMeteoCurrent ? openMeteoCurrent.visibilityKmValue : null) },
    { icon: "󰖗", label: "RAIN MAX", value: dayDetails.precipitationProbability ? (dayDetails.precipitationProbability + "%") : "—", level: Model.weatherMetricLevel("rain", dayDetails.precipitationProbability) },
    { icon: "󰜗", label: "SNOW", value: dayDetails.snowfall ? (dayDetails.snowfall + " cm") : "—", level: Model.weatherMetricLevel("snow", dayDetails.snowfall) }
  ]

  readonly property color goodTone: "#8FCB9B"
  readonly property color fairTone: "#7AA2F7"
  readonly property color warningTone: "#E0AF68"
  readonly property color dangerTone: "#F7768E"

  function semanticColor(level) {
    if (level === "good") return goodTone
    if (level === "fair") return fairTone
    if (level === "warning") return warningTone
    if (level === "danger") return dangerTone
    return root.bar.foreground
  }

  function semanticFill(level) {
    var color = semanticColor(level)
    var alpha = level === "neutral" ? 0.045 : 0.105
    return Qt.rgba(color.r, color.g, color.b, alpha)
  }

  function semanticBorder(level, alpha) {
    var color = semanticColor(level)
    return Qt.rgba(color.r, color.g, color.b, alpha)
  }

  function refresh() {
    // Each full refresh cycle gets a fresh retry budget, so an earlier
    // exhausted round (e.g. waking with the network still down) doesn't
    // starve retries for the rest of the session.
    forecastRetries = 0
    dailyForecastRetries = 0
    airQualityRetries = 0
    if (!forecastProc.running) forecastProc.running = true
    if (root.locationQuery === "" && !locationProc.running) locationProc.running = true
    // With stored coordinates this fetches open-meteo right away — no need
    // to wait for the slow wttr response. Without them it's a no-op until
    // wttr reports the detected area.
    refreshDailyForecast(null)
  }

  function refreshDailyForecast(sourceReport) {
    var lat = parseFloat(String(root.configuredLocationState.latitude))
    var lon = parseFloat(String(root.configuredLocationState.longitude))
    if (isNaN(lat) || isNaN(lon)) {
      var area = sourceReport && sourceReport.nearest_area && sourceReport.nearest_area[0] ? sourceReport.nearest_area[0] : root.areaInfo
      if (!area) return
      lat = parseFloat(String(area.latitude || ""))
      lon = parseFloat(String(area.longitude || ""))
    }
    if (isNaN(lat) || isNaN(lon)) return

    root.refreshAirQuality(lat, lon)
    if (dailyForecastProc.running) return

    var url = "https://api.open-meteo.com/v1/forecast"
      + "?latitude=" + encodeURIComponent(String(lat))
      + "&longitude=" + encodeURIComponent(String(lon))
      + "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,daylight_duration,uv_index_max,precipitation_probability_max,wind_gusts_10m_max,snowfall_sum,moonrise,moonset,moon_phase"
      + "&hourly=temperature_2m,precipitation_probability,snowfall,weather_code,wind_gusts_10m,visibility,is_day"
      + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,wind_gusts_10m,visibility,weather_code,is_day"
      + "&forecast_days=4"
      + "&forecast_hours=12"
      + "&timezone=auto"
    dailyForecastProc.command = ["curl", "-fsS", "--max-time", "5", url]
    dailyForecastProc.running = true
  }

  function refreshAirQuality(lat, lon) {
    if (airQualityProc.running) return
    var url = "https://air-quality-api.open-meteo.com/v1/air-quality"
      + "?latitude=" + encodeURIComponent(String(lat))
      + "&longitude=" + encodeURIComponent(String(lon))
      + "&current=european_aqi,pm2_5,pm10,alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen"
      + "&hourly=alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen"
      + "&forecast_hours=24"
      + "&timezone=auto"
    airQualityProc.command = ["curl", "-fsS", "--max-time", "5", url]
    airQualityProc.running = true
  }

  // ---- Location editing. Clicking the location label swaps it for a search
  //      field; picking a geocoded suggestion persists name + coordinates to
  //      the module's shell.json entry. An empty commit returns to auto.
  function startEditingLocation() {
    editingLocation = true
    savingLocation = false
    savingLocationQueryStarted = false
    locationSuggestions = []
    suggestionIndex = 0
    Qt.callLater(function() {
      locationField.text = root.configuredLocation
      locationField.selectAll()
      locationField.forceActiveFocus()
    })
  }

  function cancelEditingLocation() {
    editingLocation = false
    savingLocation = false
    savingLocationQueryStarted = false
    locationSuggestions = []
    geocodeDebounce.stop()
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function commitLocation() {
    var location = Model.locationCommit(locationField.text, locationSuggestions, suggestionIndex)
    if (location.name === "") {
      clearLocation()
      return
    }
    savingLocation = true
    savingLocationQueryStarted = false
    configuredLocationState = {
      name: location.name,
      latitude: location.latitude,
      longitude: location.longitude
    }
    persistLocation(location.name, location.latitude, location.longitude)
  }

  function clearLocation() {
    persistLocation("", null, null)
    wttrLocation = ""
    cancelEditingLocation()
  }

  function pickSuggestion(suggestion) {
    if (!suggestion) return
    savingLocation = true
    savingLocationQueryStarted = false
    configuredLocationState = {
      name: suggestion.name,
      latitude: suggestion.latitude,
      longitude: suggestion.longitude
    }
    persistLocation(suggestion.name, suggestion.latitude, suggestion.longitude)
  }

  function finishSavingLocation() {
    if (savingLocation && savingLocationQueryStarted) cancelEditingLocation()
  }

  function persistLocation(name, latitude, longitude) {
    if (name && latitude !== null && longitude !== null)
      locationSaveProc.command = ["omarchy-weather-location", "--set", name, latitude + "," + longitude]
    else if (name)
      locationSaveProc.command = ["omarchy-weather-location", "--set", name]
    else
      locationSaveProc.command = ["omarchy-weather-location", "--clear"]
    locationSaveProc.running = true
  }

  // Debounced geocoding. Only one curl runs at a time; if the query moved on
  // while a fetch was in flight, the latest query is fetched right after.
  function requestGeocode() {
    var query = locationField.text.trim()
    if (query.length < 2) {
      locationSuggestions = []
      return
    }
    geocodePendingQuery = query
    if (!geocodeProc.running) startGeocode()
  }

  function startGeocode() {
    geocodeActiveQuery = geocodePendingQuery
    geocodeProc.command = ["curl", "-fsS", "--max-time", "5",
      "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(geocodeActiveQuery) + "&count=5&language=en&format=json"]
    geocodeProc.running = true
  }

  function buildForecastDays() {
    return Model.buildForecastDays(report, dailyForecastReport, Qt.formatDate(new Date(), "yyyy-MM-dd"))
  }

  function openMeteoForecastDays() {
    return Model.openMeteoForecastDays(dailyForecastReport, Qt.formatDate(new Date(), "yyyy-MM-dd"))
  }

  function wttrNextForecastDays() {
    return Model.wttrNextForecastDays(report, Qt.formatDate(new Date(), "yyyy-MM-dd"))
  }

  function isFutureForecastDate(dateString) {
    return Model.isFutureForecastDate(dateString, Qt.formatDate(new Date(), "yyyy-MM-dd"))
  }

  function roundedTemp(value) {
    return Model.roundedTemp(value)
  }

  function celsiusToFahrenheit(value) {
    return Model.celsiusToFahrenheit(value)
  }

  function formatTemp(value) {
    return Model.formatTemp(value, useImperial)
  }

  function dayName(dateString) {
    return Model.dayName(dateString, function(date) { return Qt.formatDate(date, "dddd") })
  }

  // Bare degree value (no unit letter), used in the forecast row.
  function bareTempForDay(day, kind) {
    return Model.bareTempForDay(day, kind, useImperial)
  }

  // Representative icon for a forecast day: the hourly entry nearest noon.
  function dayIcon(day) {
    return Model.dayIcon(day)
  }

  function iconForOpenMeteoCode(code) {
    return Model.iconForOpenMeteoCode(code)
  }

  // Mirrors omarchy-weather-icon's wttr.in code → nerd-font glyph mapping.
  function iconForCode(code, night) {
    return Model.iconForCode(code, night)
  }

  Process {
    id: forecastProc
    command: ["curl", "-fsS", "--max-time", "10", "https://wttr.in/" + root.locationQuery + "?format=j1"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) {
          root.scheduleForecastRetry()
          return
        }
        try {
          var parsed = JSON.parse(raw)
          root.report = parsed
          if (!root.hasConfiguredCoordinates)
            root.label = Model.provisionalCurrentIcon(parsed.current_condition && parsed.current_condition[0], root.label)
          root.forecastRetries = 0
          if (Model.weatherResponseCompletesSave(root.hasConfiguredCoordinates, "wttr"))
            root.finishSavingLocation()
          // Stored coordinates already drove the fast open-meteo fetch from
          // refresh(); only auto-detect needs the area wttr reported.
          if (isNaN(parseFloat(String(root.configuredLocationState.latitude))))
            root.refreshDailyForecast(parsed)
        } catch (e) {
          // Keep last-good report visible, but try again shortly.
          root.scheduleForecastRetry()
        }
      }
    }
  }

  // wttr.in can be slow or flaky, especially for a location it hasn't
  // cached yet. Retry a few times before leaving it to the refresh timer.
  function scheduleForecastRetry() {
    if (forecastRetries >= 3) return
    forecastRetries++
    forecastRetryTimer.restart()
  }

  Timer {
    id: forecastRetryTimer
    interval: 2500
    onTriggered: if (!forecastProc.running) forecastProc.running = true
  }

  // With configured coordinates this fetch is the only thing that updates the
  // bar icon, so a dropped response (e.g. waking before the network is back)
  // must retry rather than wait out the refresh timer with a stale icon.
  function scheduleDailyForecastRetry() {
    if (dailyForecastRetries >= 3) return
    dailyForecastRetries++
    dailyForecastRetryTimer.restart()
  }

  function scheduleAirQualityRetry() {
    if (airQualityRetries >= 3) return
    airQualityRetries++
    airQualityRetryTimer.restart()
  }

  Timer {
    id: dailyForecastRetryTimer
    interval: 2500
    onTriggered: root.refreshDailyForecast(null)
  }

  Timer {
    id: airQualityRetryTimer
    interval: 3000
    onTriggered: {
      var lat = parseFloat(String(root.configuredLocationState.latitude))
      var lon = parseFloat(String(root.configuredLocationState.longitude))
      if (!isNaN(lat) && !isNaN(lon)) root.refreshAirQuality(lat, lon)
    }
  }

  Process {
    id: dailyForecastProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) {
          root.scheduleDailyForecastRetry()
          return
        }
        try {
          var parsed = JSON.parse(raw)
          var parsedCurrent = Model.openMeteoCurrentCondition(parsed)
          root.dailyForecastReport = parsed
          root.label = Model.currentIcon(parsedCurrent, root.label)
          root.dailyForecastRetries = 0
          if (Model.weatherResponseCompletesSave(root.hasConfiguredCoordinates, "open-meteo"))
            root.finishSavingLocation()
        } catch (e) {
          // Keep last-good daily forecast visible, but try again shortly.
          root.scheduleDailyForecastRetry()
        }
      }
    }
  }

  Process {
    id: airQualityProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) {
          root.scheduleAirQualityRetry()
          return
        }
        try {
          var parsed = JSON.parse(raw)
          if (parsed.error) throw new Error(String(parsed.reason || "Air-quality request failed"))
          root.airQualityReport = parsed
          root.airQualityRetries = 0
        } catch (e) {
          root.scheduleAirQualityRetry()
        }
      }
    }
  }

  Process {
    id: geocodeProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.locationSuggestions = root.editingLocation ? Model.parseGeocodingResults(text) : []
        root.suggestionIndex = 0
        if (root.geocodePendingQuery !== root.geocodeActiveQuery) Qt.callLater(root.startGeocode)
      }
    }
  }

  Timer {
    id: geocodeDebounce
    interval: 300
    onTriggered: root.requestGeocode()
  }

  Process {
    id: locationSaveProc
    onExited: function(exitCode) {
      if (exitCode !== 0 || !root.savingLocation) return

      // FileView handles changed locations. Explicitly refresh here too so
      // saving the already-active location cannot strand the spinner.
      locationFile.reload()
      if (!root.savingLocationQueryStarted) {
        root.savingLocationQueryStarted = true
        root.forecastRetries = 0
        root.dailyForecastRetries = 0
        root.airQualityRetries = 0
        forecastProc.running = false
        dailyForecastProc.running = false
        airQualityProc.running = false
        Qt.callLater(root.refresh)
      }
    }
  }

  Process {
    id: locationProc
    command: ["curl", "-fsS", "--max-time", "4", "https://wttr.in/?format=%l"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) return
        root.wttrLocation = raw.split(",")[0]
      }
    }
  }

  Timer {
    id: refreshTimer
    interval: root.refreshMinutes * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function edit(): void { root.openFromHotkey(); root.startEditingLocation() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(480))
    contentHeight: panel.fittedContentHeight(weatherColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingLocation
      onReturnRequested: root.startEditingLocation()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: weatherScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: weatherColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: weatherColumn
          width: weatherScroll.width
          spacing: Style.space(14)

      // ---- Hero row: big icon + temp on the left; location and stats stacked on the right.
      Item {
        width: parent.width
        height: Math.max(heroLeft.height, heroRight.height)

        Row {
          id: heroLeft
          anchors.left: parent.left
          anchors.leftMargin: Style.space(16)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(16)

          Text {
            id: heroIcon
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 5
            text: root.label || "—"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            // Decorative condition emoji; intentionally larger than the
            // Style.font.* scale's displayLarge (28).
            font.pixelSize: 64
          }

          Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              id: tempBig
              text: root.reportTempNum || "—"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              // Hero temperature read-out; deliberately oversized, outside
              // the Style.font.* scale.
              font.pixelSize: 56
              font.bold: true
            }
            Text {
              text: root.current ? root.tempUnit : ""
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
              anchors.top: tempBig.top
              anchors.topMargin: Style.space(10)
            }
          }
        }

        Column {
          id: heroRight
          width: weatherStats.implicitWidth
          anchors.right: parent.right
          anchors.rightMargin: Style.space(20)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(12)

          Row {
            visible: !root.editingLocation && root.reportLocation !== ""
            spacing: Style.space(6)

            TapHandler {
              onTapped: root.startEditingLocation()
            }
            HoverHandler {
              cursorShape: Qt.PointingHandCursor
            }

            Text {
              text: ""  // nf-fa-map_marker
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              text: (root.reportLocation || "").toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              font.letterSpacing: 1
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Row {
            visible: root.editingLocation
            spacing: Style.space(6)

            TextField {
              id: locationField
              width: Style.space(190)
              enabled: !root.savingLocation
              placeholderText: "Search city"
              foreground: root.bar.foreground
              font.family: root.bar.fontFamily

              onTextChanged: if (root.editingLocation && !root.savingLocation) geocodeDebounce.restart()

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.cancelEditingLocation()
                  event.accepted = true
                } else if (event.key === Qt.Key_Down) {
                  if (root.suggestionIndex < root.locationSuggestions.length - 1) root.suggestionIndex++
                  event.accepted = true
                } else if (event.key === Qt.Key_Up) {
                  if (root.suggestionIndex > 0) root.suggestionIndex--
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.commitLocation()
                  event.accepted = true
                }
              }
            }

            // Clear back to IP auto-detect. While a committed location is
            // loading, this same compact affordance becomes a spinner.
            Rectangle {
              width: Style.space(18)
              height: Style.space(18)
              anchors.verticalCenter: parent.verticalCenter
              radius: Math.min(4, Style.cornerRadius)
              color: !root.savingLocation && clearLocationArea.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"

              Text {
                anchors.centerIn: parent
                text: root.savingLocation ? "󰦖" : "✕"
                font.family: root.bar.fontFamily
                color: Qt.darker(root.bar.foreground, 1.4)
                font.pixelSize: Style.font.bodySmall

                RotationAnimator on rotation {
                  running: root.savingLocation
                  from: 0; to: 360
                  duration: 800
                  loops: Animation.Infinite
                }
              }

              MouseArea {
                id: clearLocationArea
                anchors.fill: parent
                enabled: !root.savingLocation
                hoverEnabled: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.clearLocation()
              }
            }
          }

          Row {
            id: weatherStats
            visible: !!root.current
            spacing: Style.space(36)

            Column {
              spacing: Style.space(5)
              Text {
                text: "FEELS"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }
              Text {
                text: root.reportFeels
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
              }
            }

            Column {
              spacing: Style.space(5)
              Text {
                text: "WIND"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }
              Text {
                text: root.reportWind
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
              }
            }

            Column {
              spacing: Style.space(5)
              Text {
                text: "HUMID"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }
              Text {
                text: root.reportHumidity
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
              }
            }
          }
        }
      }

      // ---- Geocoding suggestions while the location is being edited.
      Column {
        visible: root.editingLocation && !root.savingLocation && root.locationSuggestions.length > 0
        width: parent.width
        spacing: 0

        Repeater {
          model: root.locationSuggestions

          Rectangle {
            required property var modelData
            required property int index
            width: parent.width
            height: suggestionRow.implicitHeight + Style.space(12)
            radius: Style.cornerRadius
            color: index === root.suggestionIndex ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"

            Row {
              id: suggestionRow
              anchors.left: parent.left
              anchors.leftMargin: Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              Text {
                text: modelData.name
                color: index === root.suggestionIndex ? Style.hoverStateColor(root.bar.foreground, Color.accent) : root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                visible: text !== ""
                text: modelData.description
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onPositionChanged: root.suggestionIndex = index
              onClicked: root.pickSuggestion(modelData)
            }
          }
        }
      }

      Text {
        visible: !root.current
        text: "Fetching forecast…"
        color: Qt.darker(root.bar.foreground, 1.5)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.italic: true
      }

      // ---- Context-sensitive heads-up badges. These are informational
      //      thresholds, not official weather warnings.
      Column {
        visible: root.highlights.length > 0
        width: parent.width
        spacing: Style.space(8)

        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(20)
          spacing: Style.space(8)

          Text {
            text: ""
            color: root.semanticColor("warning")
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
          }
          Text {
            text: "HEADS UP"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            font.letterSpacing: 0.5
          }
        }

        Flow {
          width: parent.width - Style.space(40)
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(8)

          Repeater {
            model: root.highlights

            Rectangle {
              required property string modelData
              implicitWidth: highlightText.implicitWidth + Style.space(18)
              implicitHeight: highlightText.implicitHeight + Style.space(9)
              radius: Math.min(7, Style.cornerRadius)
              color: root.semanticFill("warning")
              border.width: 1
              border.color: root.semanticBorder("warning", 0.28)

              Text {
                id: highlightText
                anchors.centerIn: parent
                text: modelData
                color: root.semanticColor("warning")
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 0.6
              }
            }
          }
        }
      }

      Rectangle {
        visible: root.hourlyForecast.length > 0
        width: parent.width
        height: Style.spacing.hairline
        color: root.bar.foreground
        opacity: 0.12
      }

      Column {
        visible: root.hourlyForecast.length > 0
        width: parent.width
        spacing: Style.space(12)

        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(20)
          spacing: Style.space(8)

          Text {
            text: ""
            color: Color.accent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
          }
          Text {
            text: "NEXT 6 HOURS"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            font.letterSpacing: 0.5
          }
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(8)

          Repeater {
            model: root.hourlyForecast

            Rectangle {
              required property var modelData
              width: Style.space(68)
              height: Style.space(92)
              radius: Math.min(8, Style.cornerRadius)
              color: root.semanticFill("neutral")

              Column {
                anchors.centerIn: parent
                spacing: Style.space(3)

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: modelData.timeLabel
                  color: Qt.darker(root.bar.foreground, 1.45)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: modelData.icon
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.display
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: modelData.temperature
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: modelData.precipitationProbability !== "" ? ("󰖗 " + modelData.precipitationProbability + "%") : ""
                  visible: text !== ""
                  color: root.semanticColor(Model.weatherMetricLevel("rain", modelData.precipitationProbability))
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }
      }

      // ---- Divider between current conditions and forecast.
      Rectangle {
        visible: root.forecastDays.length > 0
        width: parent.width
        height: Style.spacing.hairline
        color: root.bar.foreground
        opacity: 0.12
      }

      // ---- Three-day outlook.
      Column {
        visible: root.forecastDays.length > 0
        width: parent.width
        spacing: Style.space(12)

        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(20)
          spacing: Style.space(8)

          Text {
            text: ""
            color: Color.accent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
          }
          Text {
            text: "3-DAY OUTLOOK"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            font.letterSpacing: 0.5
          }
        }

        Row {
          id: forecastRow
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(10)

          Repeater {
            model: root.forecastDays

            Rectangle {
              required property var modelData
              required property int index
              width: Style.space(142)
              height: Style.space(66)
              radius: Math.min(8, Style.cornerRadius)
              color: root.semanticFill("neutral")

              Row {
                anchors.fill: parent
                anchors.margins: Style.space(10)
                spacing: Style.space(10)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.dayIcon(modelData)
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.display
                }

                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(3)

                  Text {
                    text: root.dayName(modelData.date).toUpperCase()
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 0.5
                  }

                  Row {
                    spacing: Style.space(8)

                    Text {
                      text: "↑ " + root.bareTempForDay(modelData, "max")
                      color: root.semanticColor("warning")
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.body
                    }
                    Text {
                      text: "↓ " + root.bareTempForDay(modelData, "min")
                      color: root.semanticColor("fair")
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.body
                    }
                  }
                }
              }
            }
          }
        }
      }

      Rectangle {
        visible: root.dailyForecastReport !== null
        width: parent.width
        height: Style.spacing.hairline
        color: root.bar.foreground
        opacity: 0.12
      }

      Column {
        visible: root.dailyForecastReport !== null
        width: parent.width
        spacing: Style.space(12)

        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(20)
          spacing: Style.space(8)

          Text {
            text: ""
            color: Color.accent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
          }
          Text {
            text: "TODAY'S DETAILS"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            font.letterSpacing: 0.5
          }
        }

        Grid {
          anchors.horizontalCenter: parent.horizontalCenter
          columns: 2
          columnSpacing: Style.space(12)
          rowSpacing: Style.space(8)

          Repeater {
            model: root.detailItems

            Rectangle {
              required property var modelData
              width: Style.space(218)
              height: Style.space(54)
              radius: Math.min(8, Style.cornerRadius)
              color: root.semanticFill(modelData.level)
              border.width: modelData.level === "neutral" ? 0 : 1
              border.color: root.semanticBorder(modelData.level, 0.22)

              Row {
                anchors.fill: parent
                anchors.margins: Style.space(10)
                spacing: Style.space(10)

                Text {
                  width: Style.space(22)
                  anchors.verticalCenter: parent.verticalCenter
                  horizontalAlignment: Text.AlignHCenter
                  text: modelData.icon
                  color: root.semanticColor(modelData.level)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.title
                }
                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  Text {
                    text: modelData.label
                    color: Qt.darker(root.bar.foreground, 1.42)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 0.7
                  }
                  Text {
                    text: modelData.value
                    color: modelData.level === "neutral" ? root.bar.foreground : root.semanticColor(modelData.level)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                }
              }
            }
          }
        }

        Rectangle {
          visible: root.dayDetails.moonPhase !== ""
          width: Style.space(448)
          height: Style.space(48)
          anchors.horizontalCenter: parent.horizontalCenter
          radius: Math.min(8, Style.cornerRadius)
          color: root.semanticFill("neutral")

          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            spacing: Style.space(10)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: ""
              color: Color.accent
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.dayDetails.moonPhase.toUpperCase()
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: (root.dayDetails.moonrise ? ("RISE  " + root.dayDetails.moonrise) : "")
                + (root.dayDetails.moonrise && root.dayDetails.moonset ? "    " : "")
                + (root.dayDetails.moonset ? ("SET  " + root.dayDetails.moonset) : "")
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }

      Rectangle {
        visible: root.airQuality.category !== "" || root.pollen.length > 0
        width: parent.width
        height: Style.spacing.hairline
        color: root.bar.foreground
        opacity: 0.12
      }

      Column {
        visible: root.airQuality.category !== "" || root.pollen.length > 0
        width: parent.width
        spacing: Style.space(12)

        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(20)
          spacing: Style.space(8)

          Text {
            text: "󰌪"
            color: Color.accent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
          }
          Text {
            text: "AIR QUALITY"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            font.letterSpacing: 0.5
          }
        }

        Rectangle {
          visible: root.airQuality.category !== ""
          width: Style.space(448)
          height: Style.space(68)
          anchors.horizontalCenter: parent.horizontalCenter
          radius: Math.min(8, Style.cornerRadius)
          color: root.semanticFill(root.airQuality.level)
          border.width: 1
          border.color: root.semanticBorder(root.airQuality.level, 0.24)

          Row {
            anchors.fill: parent
            anchors.margins: Style.space(12)
            spacing: Style.space(14)

            Text {
              width: Style.space(24)
              anchors.verticalCenter: parent.verticalCenter
              horizontalAlignment: Text.AlignHCenter
              text: "󰵃"
              color: root.semanticColor(root.airQuality.level)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
            }
            Column {
              width: Style.space(104)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "EU AQI"
                color: Qt.darker(root.bar.foreground, 1.42)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 0.7
              }
              Text {
                text: root.airQuality.aqi
                color: root.semanticColor(root.airQuality.level)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }
            }

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              implicitWidth: aqiCategory.implicitWidth + Style.space(16)
              implicitHeight: aqiCategory.implicitHeight + Style.space(8)
              radius: Math.min(7, Style.cornerRadius)
              color: root.semanticFill(root.airQuality.level)

              Text {
                id: aqiCategory
                anchors.centerIn: parent
                text: root.airQuality.category.toUpperCase()
                color: root.semanticColor(root.airQuality.level)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 0.5
              }
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(3)

              Text {
                visible: root.airQuality.pm2_5 !== ""
                text: "PM2.5   " + root.airQuality.pm2_5
                color: Qt.darker(root.bar.foreground, 1.32)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                visible: root.airQuality.pm10 !== ""
                text: "PM10    " + root.airQuality.pm10
                color: Qt.darker(root.bar.foreground, 1.32)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        Rectangle {
          visible: root.pollen.length > 0
          width: parent.width - Style.space(40)
          height: Style.spacing.hairline
          anchors.horizontalCenter: parent.horizontalCenter
          color: root.bar.foreground
          opacity: 0.08
        }

        Row {
          visible: root.pollen.length > 0
          anchors.left: parent.left
          anchors.leftMargin: Style.space(20)
          spacing: Style.space(8)

          Text {
            text: ""
            color: root.semanticColor("good")
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
          }
          Column {
            spacing: Style.space(2)

            Text {
              text: "POLLEN"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              font.letterSpacing: 0.5
            }
            Text {
              text: "NOW / NEXT 24H PEAK  ·  GRAINS/M³"
              color: Qt.darker(root.bar.foreground, 1.45)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 0.4
            }
          }
        }

        Grid {
          visible: root.pollen.length > 0
          anchors.horizontalCenter: parent.horizontalCenter
          columns: 2
          columnSpacing: Style.space(12)
          rowSpacing: Style.space(8)

          Repeater {
            model: root.pollen

            Rectangle {
              required property var modelData
              width: Style.space(218)
              height: Style.space(58)
              radius: Math.min(8, Style.cornerRadius)
              color: root.semanticFill(modelData.level)
              border.width: 1
              border.color: root.semanticBorder(modelData.level, 0.2)

              Row {
                anchors.fill: parent
                anchors.margins: Style.space(10)
                spacing: Style.space(9)

                Text {
                  width: Style.space(20)
                  anchors.verticalCenter: parent.verticalCenter
                  horizontalAlignment: Text.AlignHCenter
                  text: "󰐕"
                  color: root.semanticColor(modelData.level)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.title
                }
                Column {
                  width: Style.space(112)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  Text {
                    text: modelData.label.toUpperCase()
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 0.5
                  }
                  Text {
                    text: modelData.current + "  →  " + modelData.peak
                    color: root.semanticColor(modelData.level)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.trend.toUpperCase()
                  color: root.semanticColor(modelData.level)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
            }
          }
        }

        Text {
          visible: root.airQuality.category !== "" && root.pollen.length === 0
          anchors.left: parent.left
          anchors.leftMargin: Style.space(20)
          text: "No pollen reported for the current forecast window"
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          font.italic: true
        }
      }
    }
  }
  }
  }

}
