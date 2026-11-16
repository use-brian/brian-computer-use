#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
runtime_bundle="${BRIAN_RUNTIME_BUNDLE:-}"
research_root="${BRIAN_RESEARCH_ROOT:-}"
shell_only=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --runtime-bundle) runtime_bundle="${2:?Missing runtime bundle path}"; shift 2 ;;
    --research-root) research_root="${2:?Missing research root path}"; shift 2 ;;
    --shell-only) shell_only=true; shift ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done
if [ "$shell_only" = false ]; then
  if [ -z "$runtime_bundle" ] && [ -n "$research_root" ]; then
    bash scripts/build-planner-runtime.sh "$research_root"
    runtime_bundle="$PWD/dist/planner-runtime/mac-control"
  fi
  if [ -z "$runtime_bundle" ]; then
    printf 'Pass --research-root /path/to/llm-research or --runtime-bundle /path/to/mac-control. Use --shell-only for UI/CI builds.\n' >&2
    exit 2
  fi
  for resource in mac-control _internal resources/planner-version.json resources/build/mac-ax resources/configs/decision-weights.json \
    resources/models/qwen3.5-4b-4bit/model.safetensors resources/models/qwen3.5-4b-4bit/tokenizer.json \
    resources/models/bge-small-en-v1.5/manifest.json resources/models/bge-small-en-v1.5/onnx/model.onnx \
    resources/adapters/mac-ax-bootstrap-v0/adapters.safetensors resources/adapters/mac-ax-bootstrap-v0/adapter_config.json; do
    test -e "$runtime_bundle/$resource" || { printf 'Missing runtime resource: %s\n' "$resource" >&2; exit 2; }
  done
fi
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
mkdir -p dist
stage="$(mktemp -d "$PWD/dist/.Brian-build.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app_dir="$stage/Brian.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/Brian" "$app_dir/Contents/MacOS/Brian"
cp "$binary_dir/brian-runtime-host" "$app_dir/Contents/MacOS/brian-runtime-host"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp -R Resources/Licenses "$app_dir/Contents/Resources/"
cp -R Resources/Brand "$app_dir/Contents/Resources/"
cp Resources/Brand/Brian.icns "$app_dir/Contents/Resources/Brian.icns"
cp Resources/ModelInfo.json "$app_dir/Contents/Resources/"
if [ -d "$PWD/dist/agent-desktop" ]; then
  cp -R "$PWD/dist/agent-desktop" "$app_dir/Contents/Resources/agent-desktop"
fi
if [ "$shell_only" = false ]; then
  # Preserve the PyInstaller layout and frameworks; clone weights on APFS.
  # The supplied research helper targets macOS 27.2; its MLX wheel targets 26.2.
  # Do not advertise the shell's lower minimum for this full runtime build.
  /usr/libexec/PlistBuddy -c 'Set :LSMinimumSystemVersion 27.2' "$app_dir/Contents/Info.plist"
  cp -cR "$runtime_bundle" "$app_dir/Contents/Resources/mac-control" 2>/dev/null || \
    ditto "$runtime_bundle" "$app_dir/Contents/Resources/mac-control"
  if [ -n "$research_root" ]; then
    mkdir -p "$app_dir/Contents/Resources/ModelProvenance"
    cp "$research_root/experiments/002-mac-accessibility/MODEL_CARD.md" \
       "$research_root/experiments/002-mac-accessibility/provenance.json" \
       "$research_root/requirements-lock.txt" "$app_dir/Contents/Resources/ModelProvenance/"
  fi
  (
    cd "$app_dir/Contents/Resources/mac-control"
    shasum -a 256 resources/models/qwen3.5-4b-4bit/model.safetensors \
      resources/adapters/mac-ax-bootstrap-v0/adapters.safetensors > ../ModelSHA256.txt
  )
  # Preserve signatures already present in the frozen runtime. Sign the native
  # launcher and outer app last; no files may change after this point.
fi
codesign --force --sign - "$app_dir/Contents/MacOS/brian-runtime-host"
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
plutil -lint "$app_dir/Contents/Info.plist"
rm -rf "$PWD/dist/Brian.app"
mv "$app_dir" "$PWD/dist/Brian.app"
printf 'Built %s\n' "$PWD/dist/Brian.app"
