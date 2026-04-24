#!/usr/bin/env bash

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SENTRY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BT_STYLE="${BT_STYLE:-center_attack_simple}"
USE_SIM_TIME="${USE_SIM_TIME:-True}"
WATCH_STATE="${WATCH_STATE:-1}"
BT_RESPAWN="${BT_RESPAWN:-False}"
ENABLE_GROOT="${ENABLE_GROOT:-False}"
GROOT_PORT="${GROOT_PORT:-1667}"

cleanup() {
  echo ">>> Stopping debug session..."
  kill $(jobs -p) 2>/dev/null || true
}
trap cleanup EXIT INT TERM

if [ ! -w "$HOME/.ros/log" ] 2>/dev/null; then
  export ROS_LOG_DIR="${ROS_LOG_DIR:-/tmp/ros_logs_center_attack_debug}"
  mkdir -p "$ROS_LOG_DIR"
fi

source /opt/ros/humble/setup.bash
[ -f "$SENTRY_ROOT/rm_vision_ws/install/setup.bash" ] && source "$SENTRY_ROOT/rm_vision_ws/install/setup.bash"
[ -f "$SENTRY_ROOT/rm_decision_ws/install/setup.bash" ] && source "$SENTRY_ROOT/rm_decision_ws/install/setup.bash"

echo ">>> Cleaning stale debug processes..."
pkill -f "$SENTRY_ROOT/scripts/watch_center_attack_state.py" 2>/dev/null || true
pkill -f "$SENTRY_ROOT/scripts/bt_comm_adapter.py" 2>/dev/null || true
pkill -f "$SENTRY_ROOT/rm_decision_ws/install/rm_behavior_tree/lib/rm_behavior_tree/rm_behavior_tree" 2>/dev/null || true
sleep 1

echo ">>> Starting bt_comm_adapter..."
python3 "$SENTRY_ROOT/scripts/bt_comm_adapter.py" &
sleep 2

echo ">>> Checking navigate_to_pose action..."
if ros2 action list 2>/dev/null | grep -q "navigate_to_pose"; then
  echo ">>> navigate_to_pose is available"
else
  echo ">>> Warning: navigate_to_pose not seen yet"
  echo ">>> Confirm the Gazebo/Nav2 terminal has finished starting"
fi

echo ">>> Starting rm_behavior_tree ($BT_STYLE)..."
ros2 launch rm_behavior_tree rm_behavior_tree.launch.py \
  style:="$BT_STYLE" \
  use_sim_time:="$USE_SIM_TIME" \
  respawn:="$BT_RESPAWN" \
  enable_groot:="$ENABLE_GROOT" \
  groot_port:="$GROOT_PORT" &
sleep 3

if [ "$WATCH_STATE" = "1" ]; then
  echo ">>> Starting center/home state watcher..."
  python3 "$SENTRY_ROOT/scripts/watch_center_attack_state.py" &
  sleep 1
fi

cat <<'EOF'

>>> Debug session running — publish topics manually to test branches:

source /opt/ros/humble/setup.bash
source ~/sentry_planner/rm_decision_ws/install/setup.bash

# In match + healthy HP: go to center
ros2 topic pub -r 1 /game_status rm_decision_interfaces/msg/GameStatus \
  "{game_progress: 4, stage_remain_time: 220}"
ros2 topic pub -r 10 /robot_status rm_decision_interfaces/msg/RobotStatus \
  "{robot_id: 7, current_hp: 600, shooter_heat: 0, team_color: false, is_attacked: false}"

# Low HP: go home
ros2 topic pub -r 10 /robot_status rm_decision_interfaces/msg/RobotStatus \
  "{robot_id: 7, current_hp: 200, shooter_heat: 0, team_color: false, is_attacked: false}"

# Pre-match: home standby
ros2 topic pub -r 1 /game_status rm_decision_interfaces/msg/GameStatus \
  "{game_progress: 0, stage_remain_time: 220}"

Press Ctrl+C to end this debug session.
EOF

wait
