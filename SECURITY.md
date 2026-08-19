# Security

Tempest is an unprivileged Omarchy bar widget. It installs no packages or
services and does not request `sudo`, `pkexec`, or other elevated permissions.

Runtime network requests are limited to the reviewed weather and air-quality
providers documented below:

- `https://wttr.in`
- `https://api.open-meteo.com`
- `https://geocoding-api.open-meteo.com`
- `https://air-quality-api.open-meteo.com`

The widget also calls these existing Omarchy helpers:

- `omarchy-weather-location`
- `omarchy-weather-status`
- `omarchy-notification-send`

The shared location file is owned by Omarchy at
`~/.local/state/omarchy/settings/weather.json`. Tempest stores no credentials.

Air-quality and pollen values are informational model output. Tempest reports
the API's numeric values and European AQI category without making medical or
official-warning claims. Pollen trend colors only compare the current value
with the reported next-24-hour peak. Weather status colors are presentational
thresholds, not official alerts.
