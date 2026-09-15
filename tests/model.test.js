"use strict";

const assert = require("node:assert/strict");
const model = require("../Model.js");

assert.deepEqual(model.parseLocationFile(""), { name: "", latitude: null, longitude: null });
assert.deepEqual(
  model.parseLocationFile('{"name":" Oslo ","latitude":59.9139,"longitude":10.7522}'),
  { name: "Oslo", latitude: 59.9139, longitude: 10.7522 },
);
assert.equal(model.wttrLocationQuery("Oslo", 59.9139, 10.7522), "59.9139,10.7522");
assert.equal(model.wttrLocationQuery("New York", null, null), "New%20York");
assert.equal(model.roundedTemp("7.6"), "8");
assert.equal(model.formatTemp("8", false), "8°C");
assert.equal(model.formatTemp("46", true), "46°F");
assert.equal(model.formatVisibilityKm(0), "");
assert.equal(model.formatVisibilityKm(400), "<1");
assert.equal(model.formatVisibilityKm(1450), "1.5");
assert.equal(model.formatVisibilityKm(14200), "14");
assert.equal(model.shouldUseImperial("metric", "en_US", "United States"), false);
assert.equal(model.shouldUseImperial("", "nb_NO", "Norway"), false);
assert.equal(model.shouldUseImperial("", "en_US", "United States"), true);

const current = model.openMeteoCurrentCondition({
  current: {
    temperature_2m: 7.6,
    apparent_temperature: 5.2,
    wind_speed_10m: 10,
    relative_humidity_2m: 81,
    weather_code: 1,
    is_day: 1,
  },
});
assert.equal(current.temp_C, "8");
assert.equal(current.FeelsLikeC, "5");
assert.equal(current.humidity, "81");
assert.equal(model.currentIcon(current, ""), model.iconForOpenMeteoCode(1, false));

const extended = {
  current: {
    temperature_2m: 10.4,
    apparent_temperature: 8.2,
    wind_speed_10m: 7,
    wind_gusts_10m: 23,
    relative_humidity_2m: 95,
    visibility: 14200,
    weather_code: 3,
    is_day: 1,
  },
  hourly: {
    time: ["2026-08-19T05:00", "2026-08-19T06:00", "2026-08-19T07:00"],
    temperature_2m: [10.4, 11.2, 12.1],
    precipitation_probability: [20, 45, 60],
    snowfall: [0, 0, 0],
    weather_code: [3, 61, 63],
    wind_gusts_10m: [23, 28, 31],
    visibility: [14200, 12000, 10000],
    is_day: [1, 1, 1],
  },
  daily: {
    time: ["2026-08-19"],
    sunrise: ["2026-08-19T05:52"],
    sunset: ["2026-08-19T21:28"],
    daylight_duration: [56160],
    uv_index_max: [3.4],
    precipitation_probability_max: [72],
    wind_gusts_10m_max: [41],
    snowfall_sum: [0],
    moonrise: ["2026-08-19T14:10"],
    moonset: ["2026-08-19T22:30"],
    moon_phase: [0.5],
  },
};

const extendedCurrent = model.openMeteoCurrentCondition(extended);
assert.equal(extendedCurrent.windgustKmph, "23");
assert.equal(extendedCurrent.visibilityKm, "14");
assert.equal(extendedCurrent.visibilityKmValue, 14.2);

const hours = model.openMeteoHourly(extended, "2026-08-19T05:00", 2, false);
assert.equal(hours.length, 2);
assert.equal(hours[0].timeLabel, "05:00");
assert.equal(hours[1].precipitationProbability, "45");
assert.equal(hours[1].temperature, "11°");

const details = model.openMeteoDayDetails(extended, "2026-08-19", false);
assert.equal(details.sunrise, "05:52");
assert.equal(details.daylight, "15h 36m");
assert.equal(details.moonPhase, "Full moon");
assert.deepEqual(model.weatherHighlights(hours, details, false), ["RAIN 45%"]);
assert.equal(model.weatherMetricLevel("uv", 2), "good");
assert.equal(model.weatherMetricLevel("uv", 6), "warning");
assert.equal(model.weatherMetricLevel("visibility", 0), "danger");
assert.equal(model.weatherMetricLevel("rain", 45), "fair");

assert.equal(model.airQualityCategory(18), "Good");
assert.equal(model.airQualityCategory(51), "Moderate");
assert.equal(model.airQualityCategory(105), "Extremely poor");
assert.equal(model.airQualityLevel(18), "good");
assert.equal(model.airQualityLevel(51), "warning");
assert.equal(model.airQualityLevel(105), "danger");

const air = {
  current: {
    european_aqi: 18,
    pm2_5: 4.2,
    pm10: 8.1,
    alder_pollen: 0,
    birch_pollen: 12.4,
    grass_pollen: 4,
  },
  hourly: {
    alder_pollen: [0, 0],
    birch_pollen: [12.4, 18.2],
    grass_pollen: [4, 6],
  },
};
assert.deepEqual(model.airQualitySummary(air), {
  aqi: "18",
  category: "Good",
  level: "good",
  pm2_5: "4.2",
  pm10: "8.1",
});
assert.deepEqual(model.pollenItems(air, 24), [
  { label: "Birch", current: "12.4", peak: "18.2", trend: "Rising", level: "warning" },
  { label: "Grass", current: "4", peak: "6", trend: "Rising", level: "warning" },
]);
assert.equal(model.temperatureLevel(-10), "fair");
assert.equal(model.temperatureLevel(5), "fair");
assert.equal(model.temperatureLevel(6), "good");
assert.equal(model.temperatureLevel(15), "good");
assert.equal(model.temperatureLevel(16), "warning");
assert.equal(model.temperatureLevel(23), "warning");
assert.equal(model.temperatureLevel(24), "danger");
assert.equal(model.temperatureLevel(null), "neutral");
assert.equal(model.temperatureLevel("invalid"), "neutral");

const tooltipItems = model.hoverItems(extendedCurrent, hours, model.airQualitySummary(air), model.pollenItems(air, 24), false);
assert.deepEqual(tooltipItems.map((item) => ({ label: item.label, value: item.value, level: item.level })), [
  { label: "Temperature", value: "10°C", level: "good" },
  { label: "Feels", value: "8°", level: "good" },
  { label: "Rain", value: "45%", level: "fair" },
  { label: "Air", value: "Good", level: "good" },
  { label: "Pollen", value: "Birch", level: "warning" },
]);
assert.equal(model.semanticHex("good"), "#8FCB9B");
assert.equal(model.semanticHex("fair"), "#7AA2F7");
assert.equal(model.semanticHex("warning"), "#E0AF68");
assert.equal(model.semanticHex("danger"), "#F7768E");
assert.equal(model.semanticHex("neutral"), "#A9B1D6");
const tooltip = model.hoverSummary(extendedCurrent, hours, model.airQualitySummary(air), model.pollenItems(air, 24), false);
assert.match(tooltip, /Temperature 10°C/);
assert.match(tooltip, /Feels 8°/);
assert.match(tooltip, /Rain 45%/);
assert.match(tooltip, /Air Good/);
assert.match(tooltip, /Pollen Birch/);
assert.doesNotMatch(tooltip, /<[^>]+>/);

console.log("Model tests: PASS");
