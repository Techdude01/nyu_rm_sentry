# Jetson Nav Runbook (Execution + Validation)

This runbook tracks the full Jetson navigation startup and validation flow to confirm the robot stack is healthy before match/field usage.

## 1) Scope and assumptions

This runbook covers:

1. Navigation stack startup (LiDAR, localization, Nav2, behavior actions)
2. Optional full-stack startup (navigation + behavior tree + serial bridge)
3. Post-start validation for topics, TF, and Nav2 action availability

Assume:

- Repository checkout at `~/sentry_planner` (or equivalent workspace path)
- A configured map and serial bridge policy if driving MCU
- Access to one terminal window with ROS 2 humble sourced where needed
- Jetson headless mode expected (RViz optional unless enabled intentionally)

## 2) Quick preflight

1. Confirm workspace

```bash
cd ~/sentry_planner
git status --short
```

- Expected: working tree state is understood and clean enough to proceed.

1. Export base profile knobs (recommended for Jetson nav-only path)

```bash
export JETSON_PROFILE=1
export ENABLE_RVIZ=0
export AGX_DESKTOP_MODE=0
```

- Expected: no command output required.

1. Verify map path exists

```bash
ls -l "$MAP_FILE"
```

- Expected: file exists.

1. Verify serial PTY only if starting serial sender

```bash
ls -l /tmp/nyush-rm-sentry-radar
```

- Expected: symlink or device path exists when `START_SERIAL_SENDER=1`.

## 3) Mandatory communication baseline

Start bridge first unless using an external process supervisor.

1. Base bridge startup

```bash
cd ~/sentry_planner
just sentry-bridge
```

- Expected: bridge process starts and indicates opened MCU channel.

1. If auto-detect fails, pin port

```bash
just sentry-bridge --port /dev/ttyACM0
```

- Expected: serial link bound to specified port without immediate error.

## 4) Startup mode selection

### 4.1 Nav-only (Jetson recommended profile)

Use this for deterministic nav bring-up and early validation:

```bash
cd ~/sentry_planner
ENABLE_RVIZ=0 \
START_SERIAL_SENDER=0 \
START_ROBOT_CONTROL_KEEPALIVE=0 \
WAIT_MANUAL_INITIAL_POSE=0 \
PUBLISH_NAV2_INITIAL_POSE=1 \
NAV2_INITIAL_POSE_X=0.8 \
NAV2_INITIAL_POSE_Y=7.8 \
NAV2_INITIAL_POSE_YAW=0.0 \
./start_nav_clean.sh
```

### 4.2 Full stack (sentry + behavior + serial flow)

Use this when running the complete Jetson stack:

```bash
cd ~/sentry_planner
bash scripts/autostart_fullstack.sh
```

Systemd-driven alternative:

```bash
systemctl --user daemon-reload
systemctl --user enable sentry_autostart.service
systemctl --user start sentry_autostart.service
```

- Expected: startup order includes MCU bridge restart and nav/BT startup.

### 4.3 Manual full stack without wrapper

```bash
cd ~/sentry_planner
START_SERIAL_SENDER=1 RADAR_PTY=/tmp/nyush-rm-sentry-radar ./start_robot.sh
```

## 5) Startup acceptance gates (must pass before proceed)

Run these in order; abort and investigate if any step blocks for > expected timeout.

1. LiDAR topic is alive

```bash
timeout 20 ros2 topic echo /livox/lidar --once
```

- Expected: one message printed.

1. Odometry source is alive

```bash
timeout 20 ros2 topic echo "$NAV_ODOM_TOPIC" --once
```

- Expected: one odometry message printed.

1. TF chain checks

```bash
ros2 run tf2_ros tf2_echo odom "$NAV_BASE_FRAME"
ros2 run tf2_ros tf2_echo map "$NAV_BASE_FRAME"
```

- Expected: transforms resolve without `lookup would fail` errors.

1. Nav stack services start

```bash
ros2 action list | grep navigate_to_pose
```

- Expected: `navigate_to_pose` action is present.

## 6) Post-start quick health checks (copy this as your minimum green set)

```bash
ros2 topic echo /robot_control --once
ros2 topic echo /cmd_vel_chassis_bt --once
ros2 topic echo /livox/lidar --once
ros2 topic echo /scan --once
ros2 topic echo /chassis_odom --once
```

```bash
ros2 run tf2_ros tf2_echo map base_link
ros2 run tf2_ros tf2_echo odom base_link
```

```bash
ros2 topic echo /game_status --once
ros2 topic echo /robot_status --once
```

- Expected: command topics are published and TF is valid for map/base and odom/base at least once.

## 7) Functional smoke checks

1. Behavior + BT integration smoke (headless-safe test)

```bash
python3 scripts/test_behavior_chain.py
```

- Expected: script exits successfully with test assertions passing.

1. Runtime behavior monitor

```bash
python3 scripts/watch_center_attack_state.py --home-x 0.8 --home-y 7.8 --center-x 0.0 --center-y 0.0
```

- Expected: readable state updates, no persistent fallback loop.

## 8) Log locations for incident triage

- Autostart logs: `logs/autostart/` (including `nav_bt.log`, `vision_detect.log`, `sentry_bridge.log`, `autoaim_keepalive.log`)
- ROS logs: `~/.ros/log/` or `/tmp/ros_logs_*` session directories
- Serial bridge service logs:

```bash
journalctl --user -u sentry_bridge.service
```

## 9) Hard-fail conditions (stop, inspect, and fix)

1. `map`/`odom`/`base_link` transform missing
2. LiDAR or scan topic remains silent after startup window
3. `navigate_to_pose` not present
4. `START_SERIAL_SENDER=1` with no valid `RADAR_PTY`
5. `~/.ros` permission or disk-write issues
6. Repeated `libusb_set_option` crashes (recheck script preload branch)
7. Bridge restart loops from invalid PTY/device state

## 10) Runbook completion criteria

- All mandatory startup gates pass.
- `/cmd_vel_chassis_bt` and `/robot_control` are publishing expected control frames.
- `navigate_to_pose` is active.
- Map-based TF chain is stable for at least one minute after startup.
- Logs show no repeated startup crashes in `nav_bt.log` / `sentry_bridge` journal.

When all criteria pass, navigation workflow is ready for controlled operation.