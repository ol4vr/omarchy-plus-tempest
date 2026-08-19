#!/usr/bin/env bash
set -euo pipefail

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

weather_url='https://api.open-meteo.com/v1/forecast?latitude=58.8524&longitude=5.7352&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,daylight_duration,uv_index_max,precipitation_probability_max,wind_gusts_10m_max,snowfall_sum,moonrise,moonset,moon_phase&hourly=temperature_2m,precipitation_probability,snowfall,weather_code,wind_gusts_10m,visibility,is_day&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,wind_gusts_10m,visibility,weather_code,is_day&forecast_days=4&forecast_hours=12&timezone=auto'
air_url='https://air-quality-api.open-meteo.com/v1/air-quality?latitude=58.8524&longitude=5.7352&current=european_aqi,pm2_5,pm10,alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen&hourly=alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen&forecast_hours=24&timezone=auto'

curl -fsS --retry 2 --max-time 15 "$weather_url" >"$temp_dir/weather.json"
curl -fsS --retry 2 --max-time 15 "$air_url" >"$temp_dir/air.json"

python3 - "$temp_dir/weather.json" "$temp_dir/air.json" <<'PY'
from pathlib import Path
import json
import sys

weather = json.loads(Path(sys.argv[1]).read_text())
air = json.loads(Path(sys.argv[2]).read_text())
assert not weather.get("error"), weather
assert not air.get("error"), air

for section in ("current", "hourly", "daily"):
    assert section in weather, section
for key in ("sunrise", "sunset", "daylight_duration", "uv_index_max", "moon_phase"):
    assert key in weather["daily"], key
for key in ("temperature_2m", "precipitation_probability", "weather_code"):
    assert key in weather["hourly"], key

assert "current" in air
assert "hourly" in air
for key in ("european_aqi", "pm2_5", "pm10"):
    assert key in air["current"], key
for key in ("alder_pollen", "birch_pollen", "grass_pollen", "mugwort_pollen"):
    assert key in air["hourly"], key
PY

printf 'Live API contract tests: PASS\n'
