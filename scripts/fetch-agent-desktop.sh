#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=1.3.1
case "$(uname -m)" in
  arm64) target=aarch64-apple-darwin; expected=9b7b7cfc74892eab46c2c85d6cb7dc4863bf8dab0a222cfcfb8ae4604c69c86c ;;
  *) echo "This preview pins the Apple Silicon release only." >&2; exit 2 ;;
esac
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
curl -fsSL "https://github.com/vercel-labs/agent-desktop/releases/download/v$version/agent-desktop-v$version-$target.tar.gz" -o "$stage/release.tar.gz"
printf '%s  %s\n' "$expected" "$stage/release.tar.gz" | shasum -a 256 -c -
mkdir -p "$stage/bundle"
tar -xzf "$stage/release.tar.gz" -C "$stage/bundle"
curl -fsSL "https://raw.githubusercontent.com/vercel-labs/agent-desktop/v$version/LICENSE" -o "$stage/bundle/LICENSE"
printf '{"version":"%s","target":"%s","sha256":"%s"}\n' "$version" "$target" "$expected" > "$stage/bundle/provenance.json"
mkdir -p dist
rm -rf dist/agent-desktop
mv "$stage/bundle" dist/agent-desktop
