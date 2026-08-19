#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runtime_files=("$repo/BarWidget.qml" "$repo/Panel.qml" "$repo/Model.js")

for forbidden in sudo pkexec systemctl pacman yay paru doas; do
  if rg -n -F ""$forbidden"" "${runtime_files[@]}"; then
    printf 'ERROR: forbidden privileged or package-management command: %s
' "$forbidden" >&2
    false
  fi
done

if rg -n --pcre2 '(?:bash|zsh|fish|/bin/sh)[[:space:]]+-c|rm[[:space:]]+-rf|chmod[[:space:]]+[ugo+0-7]' "${runtime_files[@]}"; then
  printf 'ERROR: unsafe shell execution or destructive command found.
' >&2
  false
fi

if rg -n --pcre2 '(\.ssh|\.gnupg|keyring|secret[-_ ]?service|/etc/shadow|/etc/sudoers)' "${runtime_files[@]}"; then
  printf 'ERROR: credential or protected-system path access found.
' >&2
  false
fi

if rg -n 'http://' "${runtime_files[@]}"; then
  printf 'ERROR: insecure HTTP endpoint found.
' >&2
  false
fi

actual_hosts="$(rg -o 'https://[A-Za-z0-9.-]+' "${runtime_files[@]}" | sed 's#^[^:]*:##' | sort -u)"
expected_hosts="$(printf '%s
'   'https://api.open-meteo.com'   'https://geocoding-api.open-meteo.com'   'https://wttr.in')"
if [[ "$actual_hosts" != "$expected_hosts" ]]; then
  printf 'ERROR: runtime network allowlist mismatch.
Expected:
%s
Actual:
%s
' "$expected_hosts" "$actual_hosts" >&2
  false
fi

rg -F 'root.bar.run("omarchy-notification-send \"$(omarchy-weather-status)\"")' "$repo/BarWidget.qml" >/dev/null
rg -F 'locationSaveProc.command = ["omarchy-weather-location"' "$repo/Panel.qml" >/dev/null

printf 'Security static tests: PASS
'
