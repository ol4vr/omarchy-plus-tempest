// weather.json holds {"name": ..., "latitude": ..., "longitude": ...} (see
// omarchy-weather-location, which owns the format). Missing, blank, or
// unparseable means the location is auto-detected from the IP address.
function parseLocationFile(raw) {
  var unset = { name: "", latitude: null, longitude: null }
  try {
    var data = JSON.parse(String(raw || ""))
    if (!data || typeof data !== "object") return unset

    var latitude = parseFloat(data.latitude)
    var longitude = parseFloat(data.longitude)
    var hasCoordinates = !isNaN(latitude) && !isNaN(longitude)
    return {
      name: typeof data.name === "string" ? data.name.replace(/^\s+|\s+$/g, "") : "",
      latitude: hasCoordinates ? latitude : null,
      longitude: hasCoordinates ? longitude : null
    }
  } catch (e) {
    return unset
  }
}

// wttr.in path segment for a configured location: exact coordinates when
// both are present, the URL-encoded name as a fallback (hand-edited
// weather.loc files may only carry a name), empty for IP auto-detect.
function wttrLocationQuery(location, latitude, longitude) {
  var lat = parseFloat(String(latitude))
  var lon = parseFloat(String(longitude))
  if (!isNaN(lat) && !isNaN(lon)) return lat + "," + lon

  var name = String(location || "").replace(/^\s+|\s+$/g, "")
  return name === "" ? "" : encodeURIComponent(name)
}

// Open-Meteo geocoding response → suggestion rows for the location picker.
function parseGeocodingResults(raw) {
  try {
    var data = JSON.parse(String(raw || "{}"))
    var results = data.results
    if (!results || !results.length) return []

    var out = []
    for (var i = 0; i < results.length; i++) {
      var r = results[i]
      if (!r || !r.name || r.latitude === undefined || r.longitude === undefined) continue
      var region = [r.admin1, r.country].filter(function(part) { return !!part }).join(", ")
      out.push({
        name: String(r.name),
        description: region,
        latitude: r.latitude,
        longitude: r.longitude
      })
    }
    return out
  } catch (e) {
    return []
  }
}

function locationCommit(text, suggestions, selectedIndex) {
  var name = String(text || "").replace(/^\s+|\s+$/g, "")
  if (name === "") return { name: "", latitude: null, longitude: null }

  var choices = suggestions || []
  var index = Math.max(0, Math.min(parseInt(selectedIndex, 10) || 0, choices.length - 1))
  var suggestion = choices[index]
  if (suggestion) return suggestion

  return { name: name, latitude: null, longitude: null }
}

function isFutureForecastDate(dateString, todayString) {
  if (!dateString) return false
  return String(dateString).slice(0, 10) > String(todayString || "")
}

function roundedTemp(value) {
  if (value === undefined || value === null || value === "") return ""
  var n = parseFloat(String(value))
  return isNaN(n) ? "" : String(Math.round(n))
}

function celsiusToFahrenheit(value) {
  if (value === undefined || value === null || value === "") return ""
  var n = parseFloat(String(value))
  return isNaN(n) ? "" : (n * 9 / 5) + 32
}

function formatTemp(value, useImperial) {
  if (value === undefined || value === null || value === "") return ""
  return value + "°" + (useImperial ? "F" : "C")
}

function finiteNumber(value) {
  if (value === undefined || value === null || value === "") return null
  var n = parseFloat(String(value))
  return isNaN(n) || !isFinite(n) ? null : n
}

function roundedNumber(value, decimals) {
  var n = finiteNumber(value)
  if (n === null) return ""
  var places = Math.max(0, parseInt(decimals, 10) || 0)
  var factor = Math.pow(10, places)
  return String(Math.round(n * factor) / factor)
}

function formatVisibilityKm(meters) {
  var value = finiteNumber(meters)
  if (value === null || value <= 0) return ""
  if (value < 1000) return "<1"
  return roundedNumber(value / 1000, value < 10000 ? 1 : 0)
}

function isoTimeLabel(value) {
  var raw = String(value || "")
  return raw.length >= 16 ? raw.slice(11, 16) : ""
}

function durationLabel(seconds) {
  var value = finiteNumber(seconds)
  if (value === null || value < 0) return ""
  var minutes = Math.round(value / 60)
  return Math.floor(minutes / 60) + "h " + String(minutes % 60).padStart(2, "0") + "m"
}

function dailyIndex(report, dateString) {
  var daily = report && report.daily ? report.daily : null
  var times = daily && daily.time ? daily.time : []
  var wanted = String(dateString || "").slice(0, 10)
  for (var i = 0; i < times.length; i++) {
    if (String(times[i]).slice(0, 10) === wanted) return i
  }
  return times.length > 0 ? 0 : -1
}

function arrayValue(object, key, index) {
  var values = object && object[key] ? object[key] : null
  return values && index >= 0 && index < values.length ? values[index] : null
}

function moonPhaseLabel(value) {
  var phase = finiteNumber(value)
  if (phase === null) return ""
  phase = ((phase % 1) + 1) % 1
  var labels = [
    "New moon", "Waxing crescent", "First quarter", "Waxing gibbous",
    "Full moon", "Waning gibbous", "Last quarter", "Waning crescent"
  ]
  return labels[Math.floor(phase * 8 + 0.5) % 8]
}

function openMeteoDayDetails(report, dateString, useImperial) {
  var daily = report && report.daily ? report.daily : null
  var index = dailyIndex(report, dateString)
  if (!daily || index < 0) return {}

  var gustKmh = finiteNumber(arrayValue(daily, "wind_gusts_10m_max", index))
  var gust = gustKmh === null ? "" : roundedNumber(useImperial ? gustKmh * 0.621371 : gustKmh, 0)
  var snow = roundedNumber(arrayValue(daily, "snowfall_sum", index), 1)
  return {
    sunrise: isoTimeLabel(arrayValue(daily, "sunrise", index)),
    sunset: isoTimeLabel(arrayValue(daily, "sunset", index)),
    daylight: durationLabel(arrayValue(daily, "daylight_duration", index)),
    uvMax: roundedNumber(arrayValue(daily, "uv_index_max", index), 1),
    precipitationProbability: roundedNumber(arrayValue(daily, "precipitation_probability_max", index), 0),
    gust: gust,
    gustKmh: gustKmh,
    gustUnit: useImperial ? "mph" : "km/h",
    snowfall: snow,
    moonrise: isoTimeLabel(arrayValue(daily, "moonrise", index)),
    moonset: isoTimeLabel(arrayValue(daily, "moonset", index)),
    moonPhase: moonPhaseLabel(arrayValue(daily, "moon_phase", index))
  }
}

// Small, deliberately conservative visual scale for weather metrics. These
// levels drive presentation only; they are not official warnings.
function weatherMetricLevel(kind, value) {
  var number = finiteNumber(value)
  if (number === null) return "neutral"

  if (kind === "uv") {
    if (number <= 2) return "good"
    if (number <= 5) return "fair"
    if (number <= 7) return "warning"
    return "danger"
  }
  if (kind === "gust") {
    if (number < 30) return "good"
    if (number < 50) return "fair"
    if (number < 75) return "warning"
    return "danger"
  }
  if (kind === "visibility") {
    if (number >= 10) return "good"
    if (number >= 4) return "fair"
    if (number >= 1) return "warning"
    return "danger"
  }
  if (kind === "rain") {
    if (number < 20) return "good"
    if (number < 50) return "fair"
    if (number < 70) return "warning"
    return "danger"
  }
  if (kind === "snow") {
    if (number <= 0) return "good"
    if (number <= 1) return "fair"
    if (number <= 5) return "warning"
    return "danger"
  }
  return "neutral"
}

function openMeteoHourly(report, nowString, count, useImperial) {
  var hourly = report && report.hourly ? report.hourly : null
  var times = hourly && hourly.time ? hourly.time : []
  var wanted = String(nowString || "").slice(0, 13)
  var limit = Math.max(0, parseInt(count, 10) || 0)
  var out = []

  for (var i = 0; i < times.length && out.length < limit; i++) {
    var time = String(times[i] || "")
    if (wanted && time.slice(0, 13) < wanted) continue
    var tempC = finiteNumber(arrayValue(hourly, "temperature_2m", i))
    var gustKmh = finiteNumber(arrayValue(hourly, "wind_gusts_10m", i))
    var visibility = finiteNumber(arrayValue(hourly, "visibility", i))
    out.push({
      time: time,
      timeLabel: isoTimeLabel(time),
      temperature: tempC === null ? "" : roundedNumber(useImperial ? celsiusToFahrenheit(tempC) : tempC, 0) + "°",
      precipitationProbability: roundedNumber(arrayValue(hourly, "precipitation_probability", i), 0),
      snowfall: roundedNumber(arrayValue(hourly, "snowfall", i), 1),
      gustKmh: gustKmh,
      gust: gustKmh === null ? "" : roundedNumber(useImperial ? gustKmh * 0.621371 : gustKmh, 0),
      visibilityKm: formatVisibilityKm(visibility),
      visibilityKmValue: visibility !== null && visibility > 0 ? visibility / 1000 : null,
      icon: iconForOpenMeteoCode(arrayValue(hourly, "weather_code", i), Number(arrayValue(hourly, "is_day", i)) === 0)
    })
  }
  return out
}

function maxHourlyNumber(rows, key, count) {
  var limit = Math.min(rows ? rows.length : 0, Math.max(0, parseInt(count, 10) || 0))
  var max = null
  for (var i = 0; i < limit; i++) {
    var value = finiteNumber(rows[i] && rows[i][key])
    if (value !== null && (max === null || value > max)) max = value
  }
  return max
}

function sumHourlyNumber(rows, key, count) {
  var limit = Math.min(rows ? rows.length : 0, Math.max(0, parseInt(count, 10) || 0))
  var total = 0
  var found = false
  for (var i = 0; i < limit; i++) {
    var value = finiteNumber(rows[i] && rows[i][key])
    if (value !== null) {
      total += value
      found = true
    }
  }
  return found ? total : null
}

function weatherHighlights(hourlyRows, dayDetails, useImperial) {
  var result = []
  var rain = maxHourlyNumber(hourlyRows, "precipitationProbability", 3)
  var gustKmh = maxHourlyNumber(hourlyRows, "gustKmh", 6)
  var snow = sumHourlyNumber(hourlyRows, "snowfall", 6)
  var uv = finiteNumber(dayDetails && dayDetails.uvMax)

  if (rain !== null && rain >= 40) result.push("RAIN " + Math.round(rain) + "%")
  if (gustKmh !== null && gustKmh >= 50) {
    var gust = useImperial ? gustKmh * 0.621371 : gustKmh
    result.push("GUSTS " + Math.round(gust) + " " + (useImperial ? "MPH" : "KM/H"))
  }
  if (snow !== null && snow >= 0.1) result.push("SNOW " + roundedNumber(snow, 1) + " CM")
  if (uv !== null && uv >= 6) result.push("UV " + roundedNumber(uv, 1))
  return result
}

function airQualityCategory(value) {
  var aqi = finiteNumber(value)
  if (aqi === null) return ""
  if (aqi <= 20) return "Good"
  if (aqi <= 40) return "Fair"
  if (aqi <= 60) return "Moderate"
  if (aqi <= 80) return "Poor"
  if (aqi <= 100) return "Very poor"
  return "Extremely poor"
}

function airQualityLevel(value) {
  var aqi = finiteNumber(value)
  if (aqi === null) return "neutral"
  if (aqi <= 20) return "good"
  if (aqi <= 40) return "fair"
  if (aqi <= 60) return "warning"
  return "danger"
}

function temperatureLevel(celsius) {
  var value = finiteNumber(celsius)
  if (value === null) return "neutral"
  if (value <= 5) return "fair"
  if (value <= 15) return "good"
  if (value <= 23) return "warning"
  return "danger"
}

function semanticHex(level) {
  if (level === "good") return "#8FCB9B"
  if (level === "fair") return "#7AA2F7"
  if (level === "warning") return "#E0AF68"
  if (level === "danger") return "#F7768E"
  return "#A9B1D6"
}

function tooltipPart(icon, label, value, level) {
  return { icon: icon, label: label, value: value, level: level }
}

function airQualitySummary(report) {
  var current = report && report.current ? report.current : null
  if (!current) return {}
  var aqi = roundedNumber(current.european_aqi, 0)
  return {
    aqi: aqi,
    category: airQualityCategory(aqi),
    level: airQualityLevel(aqi),
    pm2_5: roundedNumber(current.pm2_5, 1),
    pm10: roundedNumber(current.pm10, 1)
  }
}

function pollenItems(report, hours) {
  var current = report && report.current ? report.current : {}
  var hourly = report && report.hourly ? report.hourly : {}
  var species = [
    { key: "alder_pollen", label: "Alder" },
    { key: "birch_pollen", label: "Birch" },
    { key: "grass_pollen", label: "Grass" },
    { key: "mugwort_pollen", label: "Mugwort" },
    { key: "olive_pollen", label: "Olive" },
    { key: "ragweed_pollen", label: "Ragweed" }
  ]
  var out = []
  var limit = Math.max(1, parseInt(hours, 10) || 24)

  for (var i = 0; i < species.length; i++) {
    var item = species[i]
    var now = finiteNumber(current[item.key])
    var values = hourly[item.key] || []
    var peak = null
    for (var j = 0; j < values.length && j < limit; j++) {
      var value = finiteNumber(values[j])
      if (value !== null && (peak === null || value > peak)) peak = value
    }
    if (now === null && peak === null) continue
    if ((now || 0) <= 0 && (peak || 0) <= 0) continue
    var trend = now === null ? "Expected" : (peak !== null && peak > now ? "Rising" : "Steady")
    out.push({
      label: item.label,
      current: now === null ? "—" : roundedNumber(now, 1),
      peak: peak === null ? "—" : roundedNumber(peak, 1),
      trend: trend,
      level: trend === "Rising" || trend === "Expected" ? "warning" : "fair"
    })
  }
  return out
}

function hoverItems(current, hourlyRows, airQuality, pollen, useImperial) {
  var parts = []
  if (current) {
    var temp = useImperial ? current.temp_F : current.temp_C
    var feels = useImperial ? current.FeelsLikeF : current.FeelsLikeC
    var icon = currentIcon(current, "󰔏")
    if (temp !== undefined && temp !== null && temp !== "") parts.push(tooltipPart(icon, "Temperature", temp + "°" + (useImperial ? "F" : "C"), temperatureLevel(current.temp_C)))
    if (feels !== undefined && feels !== null && feels !== "") parts.push(tooltipPart("", "Feels", feels + "°", temperatureLevel(current.FeelsLikeC)))
  }
  var rain = maxHourlyNumber(hourlyRows, "precipitationProbability", 3)
  if (rain !== null) parts.push(tooltipPart("󰖗", "Rain", Math.round(rain) + "%", weatherMetricLevel("rain", rain)))
  if (airQuality && airQuality.category) parts.push(tooltipPart("󰌪", "Air", airQuality.category, airQuality.level || "neutral"))
  if (pollen && pollen.length > 0) parts.push(tooltipPart("", "Pollen", pollen[0].label, pollen[0].level || "warning"))
  return parts
}

function hoverSummary(current, hourlyRows, airQuality, pollen, useImperial) {
  return hoverItems(current, hourlyRows, airQuality, pollen, useImperial).map(function(part) {
    return part.icon + " " + part.label + " " + part.value
  }).join(" · ")
}

function normalizedUnit(value) {
  return String(value || "").replace(/^\s+|\s+$/g, "").toLowerCase()
}

function localeUsesImperial(localeName) {
  var name = String(localeName || "").replace(".", "_")
  return /^en[_-]US($|[_.-])/.test(name) || /^en[_-]LR($|[_.-])/.test(name) || /^my($|[_.-])/.test(name)
}

function countryUsesImperial(countryName) {
  var country = String(countryName || "")
    .replace(/^\s+|\s+$/g, "")
    .replace(/[._-]+/g, " ")
    .toLowerCase()
  if (!country) return null
  if (country === "us" || country === "usa" || country === "united states" || country === "united states of america") return true
  if (country === "liberia" || country === "myanmar" || country === "burma") return true
  return false
}

function shouldUseImperial(unitOverride, localeName, countryName) {
  var unit = normalizedUnit(unitOverride)
  if (unit === "imperial") return true
  if (unit === "metric") return false

  var countryPreference = countryUsesImperial(countryName)
  if (countryPreference !== null) return countryPreference

  return localeUsesImperial(localeName)
}

function dayName(dateString, formatter) {
  if (!dateString) return ""
  var d = new Date(dateString + "T12:00:00")
  if (isNaN(d.getTime())) return ""
  if (formatter) return formatter(d)
  return ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][d.getDay()]
}

function openMeteoForecastDays(dailyForecastReport, todayString) {
  var daily = dailyForecastReport && dailyForecastReport.daily ? dailyForecastReport.daily : null
  if (!daily || !daily.time) return []

  var result = []
  for (var i = 0; i < daily.time.length && result.length < 3; ++i) {
    var date = daily.time[i]
    if (!isFutureForecastDate(date, todayString)) continue

    var maxC = daily.temperature_2m_max ? daily.temperature_2m_max[i] : ""
    var minC = daily.temperature_2m_min ? daily.temperature_2m_min[i] : ""
    result.push({
      date: date,
      maxtempC: roundedTemp(maxC),
      mintempC: roundedTemp(minC),
      maxtempF: roundedTemp(celsiusToFahrenheit(maxC)),
      mintempF: roundedTemp(celsiusToFahrenheit(minC)),
      openMeteoWeatherCode: daily.weather_code ? daily.weather_code[i] : null
    })
  }
  return result
}

// Open-Meteo bundles current conditions with the daily forecast request and
// answers far faster than wttr.in. Normalize them to wttr's
// current_condition shape so the panel can use either source
// interchangeably. Open-Meteo reports metric (°C, km/h).
function openMeteoCurrentCondition(dailyForecastReport) {
  var current = dailyForecastReport && dailyForecastReport.current ? dailyForecastReport.current : null
  if (!current || current.temperature_2m === undefined || current.temperature_2m === null) return null
  var visibility = finiteNumber(current.visibility)
  return {
    temp_C: roundedTemp(current.temperature_2m),
    temp_F: roundedTemp(celsiusToFahrenheit(current.temperature_2m)),
    FeelsLikeC: roundedTemp(current.apparent_temperature),
    FeelsLikeF: roundedTemp(celsiusToFahrenheit(current.apparent_temperature)),
    windspeedKmph: roundedTemp(current.wind_speed_10m),
    windspeedMiles: roundedTemp(current.wind_speed_10m * 0.621371),
    windgustKmph: roundedTemp(current.wind_gusts_10m),
    windgustMiles: roundedTemp(current.wind_gusts_10m * 0.621371),
    humidity: roundedTemp(current.relative_humidity_2m),
    visibilityKm: formatVisibilityKm(visibility),
    visibilityKmValue: visibility !== null && visibility > 0 ? visibility / 1000 : null,
    openMeteoWeatherCode: current.weather_code,
    isDay: current.is_day
  }
}

function currentIcon(current, fallback) {
  if (!current) return fallback || ""
  if (current.openMeteoWeatherCode !== undefined && current.openMeteoWeatherCode !== null)
    return iconForOpenMeteoCode(current.openMeteoWeatherCode, Number(current.isDay) === 0)
  if (current.weatherCode !== undefined && current.weatherCode !== null)
    return iconForCode(current.weatherCode, false)
  return fallback || ""
}

// wttr.in has no day/night flag. Use its icon only to fill an empty initial
// state, never to replace a day/night-aware icon resolved by Open-Meteo.
function provisionalCurrentIcon(current, resolvedIcon) {
  return resolvedIcon || currentIcon(current, "")
}

function weatherResponseCompletesSave(hasConfiguredCoordinates, source) {
  return hasConfiguredCoordinates ? source === "open-meteo" : source === "wttr"
}

function wttrNextForecastDays(report, todayString) {
  var days = report && report.weather ? report.weather : []
  var result = []
  for (var i = 0; i < days.length && result.length < 3; ++i) {
    if (isFutureForecastDate(days[i].date, todayString)) result.push(days[i])
  }
  return result
}

function buildForecastDays(report, dailyForecastReport, todayString) {
  var days = openMeteoForecastDays(dailyForecastReport, todayString)
  return days.length > 0 ? days : wttrNextForecastDays(report, todayString)
}

function bareTempForDay(day, kind, useImperial) {
  if (!day) return ""
  var v = useImperial
    ? (kind === "max" ? day.maxtempF : day.mintempF)
    : (kind === "max" ? day.maxtempC : day.mintempC)
  if (v === undefined || v === null || v === "") return ""
  return v + "°"
}

function dayIcon(day) {
  if (!day) return ""
  if (day.openMeteoWeatherCode !== undefined && day.openMeteoWeatherCode !== null)
    return iconForOpenMeteoCode(day.openMeteoWeatherCode)
  if (!day.hourly || day.hourly.length === 0) return ""

  var best = day.hourly[0]
  var bestDist = 9999
  for (var i = 0; i < day.hourly.length; ++i) {
    var t = parseInt(String(day.hourly[i].time || "0"), 10)
    var dist = Math.abs(t - 1200)
    if (dist < bestDist) {
      bestDist = dist
      best = day.hourly[i]
    }
  }
  return iconForCode(best.weatherCode, false)
}

function iconForOpenMeteoCode(code, night) {
  var c = parseInt(String(code || "0"), 10)
  if (c === 0) return iconForCode(113, night)
  if (c === 1 || c === 2) return iconForCode(116, night)
  if (c === 3) return iconForCode(119, night)
  if (c === 45 || c === 48) return iconForCode(143, night)
  if (c === 51 || c === 53 || c === 55 || c === 56 || c === 57 || c === 61) return iconForCode(266, night)
  if (c === 63 || c === 65 || c === 66 || c === 67 || c === 80 || c === 81 || c === 82) return iconForCode(308, night)
  if (c === 71 || c === 73 || c === 75 || c === 77 || c === 85 || c === 86) return iconForCode(338, night)
  if (c === 95 || c === 96 || c === 99) return iconForCode(389, night)
  return iconForCode(119, night)
}

function iconForCode(code, night) {
  var c = parseInt(String(code || "0"), 10)
  switch (c) {
    case 113: return night ? "" : ""
    case 116: return night ? "" : ""
    case 119: case 122: return ""
    case 143: case 248: case 260: return night ? "\ue346" : "\ue313"
    case 176: case 263: case 353: return night ? "" : ""
    case 179: case 227: case 230: case 323: case 326: case 368: return night ? "" : ""
    case 182: case 185: case 281: case 284: case 311: case 314:
    case 317: case 320: case 350: case 362: case 365: case 374: case 377: return ""
    case 200: case 386: case 389: case 392: case 395: return ""
    case 266: case 293: case 296: case 299: case 302: case 305: case 308: case 356: case 359: return ""
    case 329: case 332: case 335: case 338: case 371: return ""
    default: return ""
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    parseLocationFile: parseLocationFile,
    wttrLocationQuery: wttrLocationQuery,
    parseGeocodingResults: parseGeocodingResults,
    locationCommit: locationCommit,
    isFutureForecastDate: isFutureForecastDate,
    roundedTemp: roundedTemp,
    celsiusToFahrenheit: celsiusToFahrenheit,
    formatTemp: formatTemp,
    finiteNumber: finiteNumber,
    roundedNumber: roundedNumber,
    formatVisibilityKm: formatVisibilityKm,
    isoTimeLabel: isoTimeLabel,
    durationLabel: durationLabel,
    moonPhaseLabel: moonPhaseLabel,
    openMeteoDayDetails: openMeteoDayDetails,
    openMeteoHourly: openMeteoHourly,
    weatherMetricLevel: weatherMetricLevel,
    weatherHighlights: weatherHighlights,
    airQualityCategory: airQualityCategory,
    airQualityLevel: airQualityLevel,
    temperatureLevel: temperatureLevel,
    semanticHex: semanticHex,
    airQualitySummary: airQualitySummary,
    pollenItems: pollenItems,
    hoverItems: hoverItems,
    hoverSummary: hoverSummary,
    normalizedUnit: normalizedUnit,
    localeUsesImperial: localeUsesImperial,
    countryUsesImperial: countryUsesImperial,
    shouldUseImperial: shouldUseImperial,
    dayName: dayName,
    openMeteoForecastDays: openMeteoForecastDays,
    openMeteoCurrentCondition: openMeteoCurrentCondition,
    currentIcon: currentIcon,
    provisionalCurrentIcon: provisionalCurrentIcon,
    weatherResponseCompletesSave: weatherResponseCompletesSave,
    wttrNextForecastDays: wttrNextForecastDays,
    buildForecastDays: buildForecastDays,
    bareTempForDay: bareTempForDay,
    dayIcon: dayIcon,
    iconForOpenMeteoCode: iconForOpenMeteoCode,
    iconForCode: iconForCode
  }
}
