#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SENTRY_PLANNER_ROOT="${SENTRY_PLANNER_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
NYUSH_CONTROL_ROOT="${NYUSH_CONTROL_ROOT:-$HOME/Codespace/nyush-rm-control}"

LOG_DIR="$SENTRY_PLANNER_ROOT/logs/autostart"
mkdir -p "$LOG_DIR"

export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
unset BASH_ENV || true
unset ZDOTDIR || true
export AMENT_TRACE_SETUP_FILES="${AMENT_TRACE_SETUP_FILES:-}"

rm -f /tmp/nyush-rm-sentry-bridge-ttyACM*.lock >/dev/null 2>&1 || true
rm -f /tmp/nyush-rm-sentry-vision /tmp/nyush-rm-sentry-radar >/dev/null 2>&1 || true

set +u
. /opt/ros/humble/setup.bash
. "$SENTRY_PLANNER_ROOT/install/setup.bash"
set -u

cd "$NYUSH_CONTROL_ROOT"
exec just sentry-bridge ${SENTRY_BRIDGE_ARGS:-}
