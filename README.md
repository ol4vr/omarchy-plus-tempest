# Tempest

Weather for the [Omarchy](https://omarchy.org) bar, with the current temperature
next to the condition icon.

Owned by [ol4vr](https://github.com/ol4vr) for Omarchy+. Based on Omarchy's
built-in weather widget and forked from
[unleashed-nick/omarchy-tempest](https://github.com/unleashed-nick/omarchy-tempest).
The forecast popup, location picker, and data sources are unchanged; the bar
pill shows **icon + temp** instead of the icon alone.

Tempest also adds:

- a six-hour condition, temperature, and precipitation outlook
- rain, wind-gust, snow, and UV heads-up indicators
- sunrise, sunset, daylight, visibility, and moon information
- European Air Quality Index with PM2.5 and PM10
- current and next-24-hour peak pollen concentrations for alder, birch, grass,
  mugwort, olive, and ragweed
- icon-led sections, aligned metric cards, and restrained status colors for
  faster scanning
- a concise hover summary while keeping the bar pill unchanged

![Tempest on the Omarchy bar, showing the condition icon and current temperature](preview.png)

## Install

```bash
omarchy plugin add https://github.com/ol4vr/omarchy-plus-tempest.git --enable
omarchy plugin disable omarchy.weather
```

Disable stock weather or you will have two weather pills. The widget lands in
the center of the bar. Move it if you want:

```bash
omarchy bar move io.github.ol4vr.tempest --section center --after omarchy.clock
```

### Updating

```bash
omarchy plugin update io.github.ol4vr.tempest
omarchy restart shell
```

### Removing it

```bash
omarchy plugin remove io.github.ol4vr.tempest
omarchy plugin enable omarchy.weather
```

That deletes Tempest and its bar entry. It leaves
`~/.local/state/omarchy/settings/weather.json` alone, since that file is owned
by `omarchy-weather-location` and is shared with stock weather.

### Requirements

Omarchy Quattro, and `curl`, which Omarchy already installs. The plugin calls
`omarchy-weather-location`, `omarchy-weather-status`, and
`omarchy-notification-send` — all ship with Omarchy. Nothing else is installed.

## Usage

| | |
| --- | --- |
| Left click | open the forecast popup |
| Right click | send a full weather notification |
| Middle click | refresh |
| Click the location in the popup | search and set a city |

Temperature units follow locale and country (Fahrenheit in the US, Celsius
elsewhere).

Weather data comes from wttr.in and Open-Meteo. Air-quality and pollen data
comes from Open-Meteo's CAMS-backed Air Quality API. Pollen concentrations are
shown in grains/m³ as the current value and next-24-hour peak; they are not
medical guidance. A rising pollen label only means the reported 24-hour peak
is above the current value. Pollen data is available in Europe during pollen
season. Weather colors are informational presentation, not official warnings.

## License

MIT. The forecast panel is derived from Omarchy's `omarchy.weather` plugin.
See [LICENSE](LICENSE).
