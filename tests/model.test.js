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

console.log("Model tests: PASS");
