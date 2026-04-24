#!/bin/bash
# Plan A: no-LiDAR test — one-shot launcher
# Spawns 6 background jobs: fake sensors, Nav2, RViz, comm adapter, decision, game_status
# Ctrl+C stops all

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SENTRY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Fixed RMUL map (university league field); MAP_YAML env is not read
MAP_YAML="$SENTRY_ROOT/rm_navigation_ws/src/rm_nav_bringup/map/RMUL.yaml"
NAV_PARAMS="${NAV_PARAMS:-$HOME/nav_ws/my_nav2_params.yaml}"
BT_STYLE="${BT_STYLE:-center_attack_simple}"

trap 'echo ">>> Stopping all..."; kill $(jobs -p) 2>/dev/null; exit' SIGINT

echo "=========================================="
echo "  Plan A: no-LiDAR test"
echo "  Map: $MAP_YAML"
echo "  Behavior tree: $BT_STYLE"
echo "=========================================="

# Check ~/.ros permissions
if [ ! -w "$HOME/.ros/log" ] 2>/dev/null; then
    echo "⚠️  ~/.ros/log is not writable; run:"
    echo "   sudo chown -R \$(whoami):\$(whoami) ~/.ros"
    exit 1
fi

# Check map exists
if [ ! -f "$MAP_YAML" ]; then
    echo "❌ Map not found: $MAP_YAML"
    echo "   Set MAP_YAML or create the map"
    exit 1
fi

echo ">>> [1/6] Starting fake sensors..."
(cd /tmp && unset AMENT_PREFIX_PATH COLCON_PREFIX_PATH && \
 source /opt/ros/humble/setup.bash && \
 python3 "$SCRIPT_DIR/fake_sensors_for_test.py") &
sleep 2

echo ">>> [2/6] Starting Nav2..."
(cd /tmp && unset AMENT_PREFIX_PATH COLCON_PREFIX_PATH && \
 source /opt/ros/humble/setup.bash && \
 source ~/nav_ws/install/setup.bash && \
 ros2 launch nav2_bringup bringup_launch.py \
   use_sim_time:=False map:="$MAP_YAML" params_file:="$NAV_PARAMS") &
sleep 8

echo ">>> [3/6] Starting RViz (bringup_launch does not include RViz by default)..."
(cd /tmp && unset AMENT_PREFIX_PATH COLCON_PREFIX_PATH && \
 source /opt/ros/humble/setup.bash && \
 source ~/nav_ws/install/setup.bash && \
 ros2 run rviz2 rviz2 -d $(ros2 pkg prefix nav2_bringup)/share/nav2_bringup/rviz/nav2_default_view.rviz) &
sleep 2

echo ">>> [4/6] Starting behavior-tree comm adapter..."
(cd /tmp && unset AMENT_PREFIX_PATH COLCON_PREFIX_PATH && \
 source /opt/ros/humble/setup.bash && \
 source "$SENTRY_ROOT/rm_vision_ws/install/setup.bash" && \
 source "$SENTRY_ROOT/rm_decision_ws/install/setup.bash" && \
 python3 "$SENTRY_ROOT/scripts/bt_comm_adapter.py") &
sleep 2

echo ">>> [5/6] Starting decision behavior tree..."
(cd /tmp && unset AMENT_PREFIX_PATH COLCON_PREFIX_PATH && \
 source /opt/ros/humble/setup.bash && \
 source "$SENTRY_ROOT/rm_vision_ws/install/setup.bash" && \
 source "$SENTRY_ROOT/rm_decision_ws/install/setup.bash" && \
 ros2 launch rm_behavior_tree rm_behavior_tree.launch.py \
   style:="$BT_STYLE" use_sim_time:=False) &
sleep 3

echo ">>> [6/6] Publishing game_status..."
(cd /tmp && unset AMENT_PREFIX_PATH COLCON_PREFIX_PATH && \
 source /opt/ros/humble/setup.bash && \
 source "$SENTRY_ROOT/rm_decision_ws/install/setup.bash" 2>/dev/null || true && \
 ros2 topic pub -r 1 /game_status rm_decision_interfaces/msg/GameStatus \
  '{game_progress: 4, stage_remain_time: 180}') &
sleep 1

echo ""
echo "✅ All processes started."
echo "   - RViz should open; use 'Nav2 Goal' on the map to send a goal"
echo "   - Decision tree receives game_progress=4 for match navigation"
echo "   - Comm adapter uses vx/vy only; Nav2 angular z is ignored"
echo "   - Press Ctrl+C to stop all nodes"
echo ""

wait
