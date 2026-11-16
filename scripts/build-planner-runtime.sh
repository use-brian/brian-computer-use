#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
research_root="${1:?Pass the llm-research checkout path}"
research_root="$(cd "$research_root" && pwd)"
mkdir -p .runtime-build dist/planner-runtime
# Reuse the research environment/dependency recipe, without modifying that repo.
python3 - "$research_root" "$PWD" <<'PY'
from pathlib import Path
import sys
research, repo = map(Path, sys.argv[1:])
spec = (research / 'mac-control.spec').read_text()
spec = spec.replace("['scripts/mac_control_entry.py']", repr([str(repo / 'PlannerRuntime/entry.py')]))
spec = spec.replace("pathex=['src']", 'pathex=' + repr([str(research / 'src'), str(repo / 'PlannerRuntime')]))
# The vision processor and Pillow plugins are needed inside the frozen runtime.
extra = "\nfor package in ['mlx_vlm', 'PIL']:\n    bundle = collect_all(package)\n    datas += bundle[0]; binaries += bundle[1]; hiddenimports += bundle[2]\n"
spec = spec.replace('a = Analysis(', extra + '\na = Analysis(')
(repo / '.runtime-build/planner.spec').write_text(spec)
PY
"$research_root/.venv/bin/pyinstaller" --noconfirm --distpath "$PWD/dist/planner-runtime" \
  --workpath "$PWD/.runtime-build/work" .runtime-build/planner.spec
runtime="$PWD/dist/planner-runtime/mac-control"
# Keep model, adapter and native helper provenance/layout from the research bundle.
cp -cR "$research_root/dist/mac-control/resources" "$runtime/" 2>/dev/null || \
  ditto "$research_root/dist/mac-control/resources" "$runtime/resources"
printf '{"planner_version":5,"model":"Qwen3.5-4B base instruction weights","legacy_adapter":"mac-ax-bootstrap-v0"}\n' > "$runtime/resources/planner-version.json"
printf 'Built planner runtime: %s\n' "$runtime"
