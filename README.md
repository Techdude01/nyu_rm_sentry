# RM2025 Auto Sentry — NYUSH Robotics

Forked from the SMBU-POLARBEAR open stack for **NYUSH Robotics** sentry: LiDAR localization, Nav2, **BehaviorTree** decision-making, and **bridge + serial** communication with **nyush-rm-control / nyush-rm-vision**.

**Environment:** Ubuntu 22.04 · ROS 2 Humble · (optional) Gazebo Classic 11  

---

## How to read the docs (central index)

This file is **overview and entry points** only; **details, protocols, tuning, troubleshooting, and hardware bring-up** are in the four topic READMEs below (**the five-doc role table at §0 in each topic is the same**, for cross-reference).

| Document | Role (details in each file) |
|------|------------------------------|
| [**README_COMMUNICATION.md**](README_COMMUNICATION.md) | **Communications & protocol**: single port, `sentry_bridge`, SP/SX/ST, frames, `serial_sender`, `bt_comm_adapter`, topics; **§15.3** hardware comms summary |
| [**README_BEHAVIOR_TREE_FLOW.md**](README_BEHAVIOR_TREE_FLOW.md) | **Behavior trees**: default `center_attack_simple`, XML/nodes/plugins, `RobotControl` vs Nav2, Groot2, debug scripts; **§5.1** goals and watcher alignment |
| [**README_LIDAR.md**](README_LIDAR.md) | **LiDAR + SLAM + Nav2**: **§6.4 Gazebo RMUL2026 (Sim2Real recommended)**, Mid360, FAST-LIO, parameters, mapping, TF, troubleshooting; **§10.8** hardware localization prerequisites |
| [**README_COMMANDS.md**](README_COMMANDS.md) | **Commands & data flow**: **§1** four paths, [§4](README_COMMANDS.md#readme-commands-section-4) env vars, **§4.4** maps, **§7** mapping, [§12 hardware bring-up](README_COMMANDS.md#readme-commands-section-12), [**§13** which README to open](README_COMMANDS.md#readme-commands-section-13) |

**Other common appendices:**

| File | Purpose |
|------|------|
| [communication command.txt](communication%20command.txt) | Copy-paste command snippets; **semantics and parameters are authoritative in README_COMMANDS.md** |
| [mid360 command.txt](mid360%20command.txt) | **Gazebo + Nav2 + BT** step-by-step (go to center / hold / home), Groot2 AppImage; **theory in README_LIDAR §6.4** |

---

## Architecture at a glance

```text
        Mid360 ──► livox_ros_driver2 ──► FAST-LIO ──► /cloud_registered, odometry
                        │
                        └──► pointcloud_to_laserscan ──► /scan ──► Nav2
                                      │
Nav2 /cmd_vel ──► fake_vel_transform ──► /cmd_vel_chassis ──► bt_comm_adapter ──► /cmd_vel_chassis_bt
                                                                              │
Behavior tree /goal_pose ──► Nav2          Behavior tree /robot_control ──► serial_sender ────┤
                                                                              ▼
Vision ◄──► Vision PTY ◄──► sentry_bridge ◄──► /dev/ttyACM0 ◄──► nyush-rm-control (MCU)
Radar side ◄──► Radar PTY ◄──┘
```

- **Only `sentry_bridge` uses the real USB serial**; vision and navigation each attach to a **PTY** from the bridge (see the comms README).  
- **Planar rotation** is driven by **`/robot_control.chassis_spin_vel`** via `bt_comm_adapter` into `/cmd_vel_chassis_bt.angular.z`, **not** Nav2 `angular.z` (see `scripts/bt_comm_adapter.py`).  
- **End-to-end data paths and roles** (paths A–D, SX vs SP): [README_COMMANDS.md §1](README_COMMANDS.md#readme-commands-section-1).

---

## Repository roles

| Path / repo | Role |
|-------------|------|
| **This repo `sentry_planner`** | `start_robot.sh`, `rm_navigation_ws`, `rm_decision_ws`, `scripts/bt_comm_adapter.py`, etc. |
| **`~/nav_ws`** (or your nav workspace) | Livox driver, FAST-LIO, `my_nav2_params.yaml`, etc.; sourced by `start_robot.sh` |
| **`nyush-rm-control`** | STM32 firmware, `just sentry-bridge` |
| **`nyush-rm-vision`** | Vision, `serial_sender.py --ros2` |

---

## Build order (summary)

Full commands and troubleshooting are in the topic READMEs; typical order:

1. `nav_ws` (includes `livox_ros_driver2`)  
2. `sentry_planner/rm_vision_ws`  
3. `sentry_planner/rm_decision_ws` (often needs `rm_vision_ws` sourced first)  
4. `sentry_planner/rm_navigation_ws` (**must source `nav_ws` before `colcon build`**)

---

## Shortest hardware bring-up (summary)

1. **MCU bridge** (holds USB CDC, often `/dev/ttyACM0`): in `nyush-rm-control` run **`just sentry-bridge`** (auto port) or explicit `--port`; note **Radar / Vision PTY** (prefer stable symlinks; see comms README).  
2. **This repo**: `START_SERIAL_SENDER=1 RADAR_PTY=<Radar_PTY> ./start_robot.sh` (**`start_robot.sh` does not start the bridge**; details in [README_COMMANDS.md §4](README_COMMANDS.md#readme-commands-section-4)).  
3. **Vision** (if needed): set **`com_port` to the Vision PTY** in `sentry.yaml`, then follow `nyush-rm-vision` startup.

**Bring-up order**: **Sim2Real is recommended** — tune in **Gazebo RMUL2026 + Nav2** and `center_attack_simple` first (**[README_LIDAR.md §6.4](README_LIDAR.md#nyush-gazebo-sim2real)**, steps in **[mid360 command.txt](mid360%20command.txt)**), then move to the robot. You do not need the full field on day one: **bench comms + BT → small area low-speed localization and home → full field**. Steps and checklists: **[README_COMMANDS.md §12](README_COMMANDS.md#readme-commands-section-12)**.

**Avoid** `scripts/start_fullstack_sequence.sh` unless you want **gnome-terminal to spawn many windows**; for daily use prefer multiple manual terminals (see `README_COMMUNICATION.md`).

---

## Changes and references

NYUSH protocol and chassis differences vs the upstream stack (19-byte radar frame, `ref_yaw`, swerve sentry, etc.) are defined in **README_COMMUNICATION.md** and the firmware repo; upstream SMBU-POLARBEAR is on Gitee.

---

*This central README only holds the index and shared assumptions; details live in the four topic READMEs.*
