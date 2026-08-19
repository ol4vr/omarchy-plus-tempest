# Security

Tempest is an unprivileged Omarchy bar widget. It installs no packages or
services and does not request `sudo`, `pkexec`, or other elevated permissions.

Runtime network requests are limited to the weather providers already used by
Omarchy's stock weather widget:

- `https://wttr.in`
- `https://api.open-meteo.com`
- `https://geocoding-api.open-meteo.com`

The widget also calls these existing Omarchy helpers:

- `omarchy-weather-location`
- `omarchy-weather-status`
- `omarchy-notification-send`

The shared location file is owned by Omarchy at
`~/.local/state/omarchy/settings/weather.json`. Tempest stores no credentials.
