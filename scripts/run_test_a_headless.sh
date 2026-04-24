#!/bin/bash
# Plan A: no-LiDAR test — headless (no RViz, for headless/CI)
# Spawns 5 background jobs: fake sensors, Nav2, comm adapter, decision, game_status
# If ~/.ros is not writable, uses /tmp for logs

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SENTRY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Fixed RMUL map; MAP_YAML env is not read
MAP_YAML="$SENTRY_ROOT/rm_navigation_ws/src/rm_nav_bringup/map/RMUL.yaml"
NAV_PARAMS="${NAV_PARAMS:-$HOME/nav_ws/my_nav2_params.yaml}"
ROS_LOG_DIR="${ROS_LOG_DIR:-}"
BT_STYLE="${BT_STYLE:-center_attack_simple}"

trap 'echo ">>> Stopping all..."; kill $(jobs -p) 2>/dev/null; exit' SIGINT

echo "=========================================="
echo "  Plan A: no-LiDAR test (headless)"
echo "  Map: $MAP_YAML"
echo "  Behavior tree: $BT_STYLE"
echo "=========================================="

# Fall back to /tmp if ~/.ros/log not writable
if [ ! -w "$HOME/.ros/log" ] 2>/dev/null; then
    ROS_LOG_DIR="${ROS_LOG_DIR:-/tmp/ros_log_$$}"
    mkdir -p "$ROS_LOG_DIR"
    export ROS_LOG_DIR
    export ROS_HOME="$ROS_LOG_DIR"
    echo "⚠️  ~/.ros/log not writable; using $ROS_LOG_DIR"
    echo "   Suggested: sudo chown -R \$(whoami):\$(whoami) ~/.ros"
fi

# Check map exists
if [ ! -f "$MAP_YAML" ]; then
    echo "❌ Map not found: $MAP_YAML"
    exit 1
fi

echo ">>> [1/5] Starting fake sensors..."
(cd /tmp && unset AMENT_PREFIX_PATH COLCON_PREFIX_PATH && \
 source /opt/ros/humble/setup.bash && \
 python3 "$SCRIPT_DIR/fake_sensors_for_test.py") &
sleep 2

echo ">>> [2/5] Starting Nav2..."
(cd /tmp && unset AMENT_PREFIX_PATH COLCON_PREFIX_PATH && \
 source /opt/ros/humble/setup.bash && \
 source ~/nav_ws/install/setup.bash && \
 ros2 launch nav2_bringup bringup_launch.py \
   use_sim_time:=False map:="$MAP_YAML" params_file:="$NAV_PARAMS") &
sleep 8

echo ">>> [3/5] Starting behavior-tree comm adapter..."
(cd /tmp && unset AMENT_PREFIX_PATH COLCON_PREFIX_PATH && \
 source /opt/ros/humble/setup.bash && \
 source "$SENTRY_ROOT/rm_vision_ws/install/setup.bash" 2>/dev/null; \
 source "$SENTRY_ROOT/rm_decision_ws/install/setup.bash" && \
 python3 "$SENTRY_ROOT/scripts/bt_comm_adapter.py") &
sleep 2

echo ">>> [4/5] Starting decision behavior tree..."
(cd /tmp && unset AMENT_PREFIX_PATH COLCON_PREFIX_PATH && \
 source /opt/ros/humble/setup.bash && \
 source "$SENTRY_ROOT/rm_vision_ws/install/setup.bash" 2>/dev/null; \
 source "$SENTRY_ROOT/rm_decision_ws/install/setup.bash" && \
 ros2 launch rm_behavior_tree rm_behavior_tree.launch.py \
   style:="$BT_STYLE" use_sim_time:=False) &
sleep 3

echo ">>> [5/5] Publishing game_status..."
(cd /tmp && unset AMENT_PREFIX_PATH COLCON_PREFIX_PATH && \
 source /opt/ros/humble/setup.bash && \
 source "$SENTRY_ROOT/rm_decision_ws/install/setup.bash" 2>/dev/null; \
 ros2 topic pub -r 1 /game_status rm_decision_interfaces/msg/GameStatus \
  '{game_progress: 4, stage_remain_time: 180}') &
sleep 1

echo ""
echo "✅ All processes started (no RViz)"
echo "   Default adapter uses vx/vy only; Nav2 angular z is ignored"
echo "   Check with: ros2 topic list / ros2 node list"
echo "   Press Ctrl+C to stop all nodes"
echo ""

wait
