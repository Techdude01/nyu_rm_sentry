#!/usr/bin/env bash

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VISION_WS_ROOT="${VISION_WS_ROOT:-$SCRIPT_DIR/rm_vision_ws}"
SET_SERIAL_PERMS="${SET_SERIAL_PERMS:-0}"
SERIAL_DEVICE="${SERIAL_DEVICE:-/dev/ttyACM0}"

source /opt/ros/humble/setup.bash

if [ -f "$VISION_WS_ROOT/install/setup.bash" ]; then
  # shellcheck disable=SC1090
  source "$VISION_WS_ROOT/install/setup.bash"
else
  echo "Vision workspace setup not found: $VISION_WS_ROOT/install/setup.bash"
  exit 1
fi

if [ -e "$SERIAL_DEVICE" ] && [ "$SET_SERIAL_PERMS" = "1" ]; then
  echo "Setting permissions on $SERIAL_DEVICE"
  sudo chmod 777 "$SERIAL_DEVICE"
elif [ -e "$SERIAL_DEVICE" ]; then
  echo "Skipping chmod for $SERIAL_DEVICE (set SET_SERIAL_PERMS=1 to opt in)"
else
  echo "Warning: serial device not found: $SERIAL_DEVICE"
fi

ros2 launch rm_vision_bringup vision_bringup.launch.py
