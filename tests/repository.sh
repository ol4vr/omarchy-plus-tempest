#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$repo" <<'PYTEST'
from pathlib import Path
import json
import sys

repo = Path(sys.argv[1])
manifest = json.loads((repo / "manifest.json").read_text(encoding="utf-8"))
assert manifest["schemaVersion"] == 1
assert manifest["id"] == "io.github.ol4vr.tempest"
assert manifest["version"] == "1.1.0"
assert manifest["author"] == "Olav Rorvik (ol4vr)"
assert manifest["entryPoints"]["barWidget"] == "BarWidget.qml"
assert manifest["barWidget"]["allowMultiple"] is False
assert manifest["barWidget"]["defaultSection"] == "center"

bar = (repo / "BarWidget.qml").read_text(encoding="utf-8")
panel = (repo / "Panel.qml").read_text(encoding="utf-8")
readme = (repo / "README.md").read_text(encoding="utf-8")
assert 'moduleName: "io.github.ol4vr.tempest"' in bar
assert 'moduleName: "io.github.ol4vr.tempest"' in panel
assert 'ipcTarget: "io.github.ol4vr.tempest"' in panel
assert 'tooltipText: root.hoverSummary' in bar
assert 'icon: ""' in panel
assert 'icon: ""' in panel
assert 'text: "NEXT 6 HOURS"' in panel
assert 'text: "3-DAY OUTLOOK"' in panel
assert 'text: "TODAY\'S DETAILS"' in panel
assert 'text: "AIR QUALITY"' in panel
assert 'text: "POLLEN"' in panel
assert "https://air-quality-api.open-meteo.com/v1/air-quality" in panel
assert "moon_phase" in panel
assert "unleashed-nick.tempest" not in bar
assert "unleashed-nick.tempest" not in panel
assert "github.com/ol4vr/omarchy-plus-tempest.git" in readme

for required in (
    "BarWidget.qml", "Panel.qml", "Model.js", "manifest.json", "LICENSE",
    "README.md", "SECURITY.md", "UPSTREAM.md", "tests/model.test.js",
    "tests/security-static.sh", "tests/repository.sh", "tests/api-contract.sh", "tests/run",
):
    assert (repo / required).is_file(), required
PYTEST

if find "$repo" -type l -print -quit | rg .; then
  printf 'ERROR: repository contains a symbolic link.
' >&2
  false
fi

git -C "$repo" diff --check
printf 'Repository tests: PASS
'
