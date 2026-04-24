#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SENTRY_PLANNER_ROOT="${SENTRY_PLANNER_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
NYUSH_CONTROL_ROOT="${NYUSH_CONTROL_ROOT:-}"

LOG_DIR="$SENTRY_PLANNER_ROOT/logs/autostart"
mkdir -p "$LOG_DIR"

export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
unset BASH_ENV || true
unset ZDOTDIR || true
export AMENT_TRACE_SETUP_FILES="${AMENT_TRACE_SETUP_FILES:-}"

resolve_control_root() {
  if [ -n "$NYUSH_CONTROL_ROOT" ] && [ -d "$NYUSH_CONTROL_ROOT" ]; then
    return
  fi

  local candidates=(
    "$SENTRY_PLANNER_ROOT/../nyush-rm-control"
    "$HOME/Projects/nyush-rm-control"
    "$HOME/Codespace/nyush-rm-control"
  )
  local candidate
  for candidate in "${candidates[@]}"; do
    if [ -d "$candidate" ]; then
      NYUSH_CONTROL_ROOT="$candidate"
      return
    fi
  done
}

rm -f /tmp/nyush-rm-sentry-bridge-ttyACM*.lock >/dev/null 2>&1 || true
rm -f /tmp/nyush-rm-sentry-vision /tmp/nyush-rm-sentry-radar >/dev/null 2>&1 || true

resolve_control_root
if [ -z "$NYUSH_CONTROL_ROOT" ] || [ ! -d "$NYUSH_CONTROL_ROOT" ]; then
  echo "Bridge repo not found. Set NYUSH_CONTROL_ROOT to your nyush-rm-control checkout."
  exit 1
fi

set +u
. /opt/ros/humble/setup.bash
[ -f "$SENTRY_PLANNER_ROOT/install/setup.bash" ] && . "$SENTRY_PLANNER_ROOT/install/setup.bash"
set -u

cd "$NYUSH_CONTROL_ROOT"
exec just sentry-bridge ${SENTRY_BRIDGE_ARGS:-}
