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
assert manifest["version"] == "1.1.2"
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
assert 'typeof root.bar.setCenterHoverRevealSuppressed === "function"' in panel
assert 'root.bar.setCenterHoverRevealSuppressed(value)' in panel
close_start = panel.index("  function close() {")
close_end = panel.index("\n  }\n\n  function toggle()", close_start)
close_block = panel[close_start:close_end]
assert close_block.index("root.controller.hide()") < close_block.index("setCenterHoverRevealSuppressed(false)")
assert 'tooltipText: ""' in bar
assert 'import "Model.js" as Model' in bar
assert "PopupWindow {" in bar
assert 'id: weatherTooltipWindow' in bar
assert 'color: root.bar ? root.bar.background : "#1A1B26"' in bar
assert "adjustment: PopupAdjustment.Slide" in bar
assert "edges: Edges.Top | Edges.Left" in bar
assert "gravity: Edges.Bottom | Edges.Right" in bar
assert "onAnchoring:" in bar
assert "var localX = button.width / 2 - popupWidth / 2" in bar
assert "window.contentItem.mapFromItem(button, localX, localY)" in bar
assert "implicitWidth: Math.ceil(weatherTooltipBubble.implicitWidth)" in bar
assert "radius: 0" in bar
assert "Controls.ToolTip {" not in bar
assert "import QtQuick.Controls as Controls" not in bar
assert "TEMPEST_TOOLTIP_GEOMETRY" not in bar
assert "Model.semanticHex(modelData.level)" in bar
assert 'icon: ""' in panel
assert 'icon: ""' in panel
assert 'icon: ""' in panel
assert 'icon: ""' in panel
assert 'text: "MOON"' in panel
assert 'label: "MOONRISE"' in panel
assert 'label: "MOONSET"' in panel
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
