#!/usr/bin/env sh
# roblox-gpu-model launcher (macOS / Linux).
# Runs run_pipeline.py with the tools venv, else `uv run` (downloads Python 3.11 if needed),
# else python3.
# Usage: sh .agents/skills/roblox-gpu-model/scripts/rgm.sh doctor
set -e
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../../.." && pwd)
script="$here/run_pipeline.py"
for py in "${ROBLOX_GPU_MODEL_TOOLS:+$ROBLOX_GPU_MODEL_TOOLS/venv/bin/python}" \
          "$repo/.tools/roblox-gpu-model/venv/bin/python" \
          "$repo/.tools/roblox-model/venv/bin/python"; do
    if [ -n "$py" ] && [ -x "$py" ]; then exec "$py" "$script" "$@"; fi
done
if command -v uv >/dev/null 2>&1; then exec uv run --no-project --python 3.11 "$script" "$@"; fi
if command -v python3 >/dev/null 2>&1; then exec python3 "$script" "$@"; fi
echo "No Python found. Install uv (brew install uv), then re-run." >&2
exit 1
