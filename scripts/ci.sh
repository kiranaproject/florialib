#!/usr/bin/env bash
# Reproducible local/CI check for florialib.
#
# Requirements:
#   - FPC 3.2.3+
#   - Pasbuild 1.9+
#   - fpGUI framework + its extras/aggpas package
#   - lazbuild and python3
#
# CI should export FLORIA_REQUIRE_DISPLAY=1 and FLORIA_REQUIRE_GL=1 after
# provisioning Xvfb and a software OpenGL implementation (Mesa llvmpipe).

set -euo pipefail

cd "$(dirname "$0")/.."

export FLORIA_REQUIRE_DISPLAY="${FLORIA_REQUIRE_DISPLAY:-0}"
export FLORIA_REQUIRE_GL="${FLORIA_REQUIRE_GL:-0}"
# If the runner needs Mesa's software GL, set LIBGL_ALWAYS_SOFTWARE=1
# explicitly. Do not force it here: some Mesa/EGL versions crash during
# context teardown when software rendering is forced globally.

for tool in pasbuild python3 lazbuild; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "error: required tool not found: ${tool}" >&2
    exit 1
  fi
done

echo "==> Checking resolved build configuration"
resolve_output="$(pasbuild resolve -p pic)"
if ! grep -q -- '-Cg' <<<"${resolve_output}"; then
  echo "error: the pic profile did not add -Cg to the compiler command" >&2
  exit 1
fi

echo "==> Repository consistency checks"
python3 scripts/check-repo.py

echo "==> Clean build and test suite"
pasbuild clean
if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null 2>&1; then
  xvfb-run -a pasbuild test -p pic
else
  pasbuild test -p pic
fi

echo "==> Installing units to the local Pasbuild repository"
pasbuild install -p pic

echo "==> Building the Lazarus package"
lazbuild src/main/pascal/florialib.lpk

echo "==> All checks passed"
