# NYUSH sentry communications and protocols

Last updated: 2026-04-11

This document describes the NYUSH sentry **comms path**, **frame formats**, **bridge usage**, **startup order**, and **troubleshooting**.

## 0. How the five READMEs split work

| Document | Role |
|------|------|
| [README.md](README.md) | **Central index**: overview, diagram, build order, shortest startup |
| **This file** | **Comms and protocol**: `sentry_bridge`, SP/SX/ST, PTY, serial frames, `serial_sender`, `bt_comm_adapter`, topic tables, troubleshooting; **§15.3** hardware comms summary |
| [README_BEHAVIOR_TREE_FLOW.md](README_BEHAVIOR_TREE_FLOW.md) | **Behavior trees**: XML, nodes, `RobotControl` semantics (**who publishes `/robot_control`** lives there) |
| [README_LIDAR.md](README_LIDAR.md) | **LiDAR + SLAM + Nav2**: **§6.4 Gazebo Sim2Real**, drivers, FAST-LIO, Nav2 tuning, hardware symptoms |
| [README_COMMANDS.md](README_COMMANDS.md) | **Commands and data flow**: [§1 four paths](README_COMMANDS.md#readme-commands-section-1), bridge auto port, **§4** env vars, **§12** hardware terminals and `ros2 topic pub` |

**How to choose:** bytes, PTY, who owns `/dev/ttyACM0`, sender topics → **this file**; how `RobotControl` is used tactically → [README_BEHAVIOR_TREE_FLOW.md](README_BEHAVIOR_TREE_FLOW.md); end-to-end block diagram → [README_COMMANDS.md §1](README_COMMANDS.md#readme-commands-section-1); phased hardware steps → [README_COMMANDS.md §12](README_COMMANDS.md#readme-commands-section-12).

**Boundaries:** **§5–§8** here own **frame layout, CRC, 0x5C/0x5D**; **§11** owns how **`bt_comm_adapter` merges `chassis_spin_vel` into `/cmd_vel_chassis_bt`**, complementing [README_BEHAVIOR_TREE_FLOW.md §17](README_BEHAVIOR_TREE_FLOW.md).

Also see root `communication command.txt` and `mid360 command.txt` for snippets (semantics in [README_COMMANDS.md](README_COMMANDS.md)).

---

Repositories referenced:

- This repo: `/home/nyu/sentry_planner`
- MCU firmware: `/home/nyu/Codespace/nyush-rm-control`
- Vision host: `/home/nyu/Codespace/nyush-rm-vision`
- Legacy radar forwarder: `nyush-rm-vision/serial_sender.py` (and sometimes `/home/nyu/Desktop/serial_sender.py`)

## 1. Executive summary

Recommended topology:

```text
nyush-rm-vision <-> Vision PTY <-> sentry_bridge.py <-> /dev/ttyACM0 <-> nyush-rm-control
radar / nav     <-> Radar PTY  <-> sentry_bridge.py <-> /dev/ttyACM0 <-> nyush-rm-control
```

Four rules:

1. Only **one** process may open the real MCU USB device (often `/dev/ttyACM0`).
2. That process should be **`nyush-rm-control/scripts/sentry_bridge.py`**.
3. Vision must **not** open the MCU port directly—use the **Vision PTY** printed by the bridge.
4. Radar / nav must **not** open the MCU port directly—use the **Radar PTY**.

If multiple programs open `/dev/ttyACM0` directly you typically see:

- Contention between vision and radar paths
- Interleaved garbage frames
- One side timing out while the other works
- Flaky behavior that changes after reboot

## 2. Role map

### 2.1 Components

- **`nyush-rm-control`** — MCU firmware on the STM32 C board; chassis, gimbal, shooter, referee decode, local state machine.
- **`nyush-rm-vision`** — host vision; armor detect/track/aim, fire decisions, optional ROS 2 hooks.
- **`sentry_planner`** — this repo; Nav2, behavior trees, legacy ROS serial helpers (`rm_serial_driver`, scripts).
- **`serial_sender.py`** — ROS ↔ Radar PTY bridge traffic; not the core vision pipeline.

### 2.2 Hard boundaries

- Vision and radar must not hold the real MCU serial.
- `sentry_bridge` is the **sole** owner of the USB CDC port.
- MCU still sees one wire; logically the bridge exposes:
  - Vision path: **`SP`**
  - Sentry extension path: **`SX` / `ST`**

## 3. Diagrams

### 3.1 Recommended wiring

```text
                      +---------------------------+
                      |   nyush-rm-control MCU    |
                      |  SP + SX/ST on one CDC    |
                      +-------------+-------------+
                                    ^
                                    |
                              /dev/ttyACM0
                                    |
                     +--------------+--------------+
                     |         sentry_bridge.py     |
                     |  own real port, split PTYs   |
                     +--------------+--------------+
                                    |
                 +------------------+------------------+
                 |                                     |
            Vision PTY                            Radar PTY
                 |                                     |
     +-----------+-----------+             +-----------+-----------+
     |     nyush-rm-vision   |             |  radar/nav side tool  |
     |   SP send/recv only   |             |  legacy radar frames  |
     +-----------------------+             +-----------------------+
```

### 3.2 ROS 2 side (high level)

```text
Nav2 -> /cmd_vel -> fake_vel_transform -> /cmd_vel_chassis -> radar sender -> Radar PTY

vision -> /detector/armors -> behavior tree (when subscribed)
behavior tree -> /goal_pose -> Nav2
behavior tree -> /robot_control -> serial_sender -> Radar PTY -> MCU
```

## 4. Suggested source reading order

1. `nyush-rm-control/scripts/sentry_bridge.py` — how Vision/Radar PTYs are created.
2. `nyush-rm-control/modules/master_machine/master_process.h` — struct sizes.
3. `nyush-rm-control/modules/master_machine/master_process.c` — MCU unpack/pack for `SP` / `SX` / `ST`.
4. `nyush-rm-vision/io/gimbal/gimbal.hpp` — vision packet structs.
5. `nyush-rm-vision/io/gimbal/gimbal.cpp` — `com_port`, SP transmit path.
6. `sentry_planner/rm_navigation_ws/src/rm_navigation/fake_vel_transform/src/fake_vel_transform.cpp` — `/cmd_vel` → `/cmd_vel_chassis`.
7. `sentry_planner/rm_decision_ws/rm_behavior_tree/plugins/action/sub_armors.cpp` — armor subscription.
8. `sentry_planner/rm_decision_ws/rm_behavior_tree/plugins/condition/is_detect_enemy.cpp` — enemy-seen logic.
9. `nyush-rm-vision/tasks/omniperception/decider.cpp` — targets for navigation.
10. `nyush-rm-vision/io/ros2/publish2nav.cpp` — ROS 2 publishers from vision.

## 5. Real port vs virtual PTYs

### 5.0 Which repo owns which `just` recipes

`nyush-rm-control` and `nyush-rm-vision` each have their own `justfile`—do not mix commands across repos.

- In **`nyush-rm-control`**: `just bridge` / `just sentry-bridge`, `just logger`, `just logger-cli`, `just vision`.
- In **`nyush-rm-vision`**: `just test detect --web --send`, other `just test …`.

Wrong directory → benign errors:

```text
error: Justfile does not contain recipe `logger`
error: Justfile does not contain recipe `test`
```

### 5.1 Single-owner rule

Only one process may hold the real MCU serial:

```bash
cd /home/nyu/Codespace/nyush-rm-control
just sentry-bridge --port /dev/ttyACM0
```

Typical banner:

```text
MCU serial : /dev/ttyACM0
Vision PTY : /dev/pts/3
Radar PTY  : /dev/pts/4
Press Ctrl+C to stop.
```

Then:

- Vision attaches to `/dev/pts/3` (Vision PTY)
- Radar / nav attaches to `/dev/pts/4` (Radar PTY)

### 5.2 Why the bridge exists

The MCU now multiplexes **vision `SP`** and **sentry `SX`/`ST`** on one CDC link. The bridge:

- Passes **`SP`** for the vision leg
- Converts legacy radar bytes into **`SX`**
- Translates MCU **`ST`** back into legacy-style telemetry toward the Radar PTY

## 6. Protocol conventions

### 6.1 Basics

- Multi-byte fields are little-endian in current code.
- Legacy radar frames use **CRC8**.
- **`SP` / `SX` / `ST`** use **CRC16** from the same codebase—reuse helpers instead of guessing.

Authoritative references:

- `nyush-rm-control/scripts/sentry_bridge.py`
- `nyush-rm-control/modules/master_machine/master_process.h`
- `nyush-rm-vision/io/gimbal/gimbal.hpp`

## 7. SP vision protocol

`SP` is the primary vision ↔ MCU framing.

### 7.1 MCU → vision: `GimbalToVision` (43 bytes)

Sources: `master_process.h`, `gimbal.hpp`.

```text
head[2] = 'S','P'
mode        uint8
q[4]        float[4]
yaw         float   rad
yaw_vel     float   rad/s
pitch       float   rad
pitch_vel   float   rad/s
bullet_speed float  m/s
bullet_count uint16
crc16       uint16
```

`mode`: 0 IDLE, 1 AUTO_AIM, 2 SMALL_BUFF, 3 BIG_BUFF.  
`q[4]`: quaternion `w x y z`.  
`yaw` / `pitch`: current gimbal pose.  
`bullet_speed`, `bullet_count`: shot telemetry.

### 7.2 Vision → MCU: `VisionToGimbal` (29 bytes)

```text
head[2] = 'S','P'
mode         uint8
yaw          float   rad
yaw_vel      float   rad/s
yaw_acc      float   rad/s^2
pitch        float   rad
pitch_vel    float   rad/s
pitch_acc    float   rad/s^2
crc16        uint16
```

`mode`: 0 idle, 1 aim without firing, 2 aim with fire allowed.

**Note:** this uplink carries **how to move / whether to fire**, not a high-level target class string. MCU `target_type` exists but `ApplyVisionPacket()` currently marks vision data as absent (`NO_TARGET_NUM`).

## 8. SX / ST sentry extension

### 8.1 Radar leg → MCU: `SX` (33 bytes)

Sources: `master_process.h`, `master_process.c`, `sentry_bridge.py`.

```text
head[2] = 'S','X'
vx                  float
vy                  float
wz                  float
gimbal_yaw_delta    float
gimbal_pitch_delta  float
control_flags       uint8
scan_yaw_rate_deg_s float
search_pitch_deg    float
crc16               uint16
```

`control_flags` bits (current):

- bit0 `scan_control_valid`
- bit1 `stop_gimbal_scan` (legacy compat)
- bit2 `scan_enabled`
- bit3 `allow_vision_control`
- bit4 `search_when_target_lost`

MCU maps into `sentry_ext.*` then `robot_cmd.c` for chassis commands plus gimbal scan / auto-aim / reacquire behavior.

### 8.2 MCU → radar leg: `ST` (27 bytes)

```text
head[2]            = 'S','T'
cmd_vx             float
cmd_vy             float
cmd_wz             float
robot_status       uint8
game_status        uint8
stage_remain_time  uint16
robot_id           uint8
current_hp         uint16
shooter_heat       uint16
team_color         uint8
is_attacked        uint8
crc16              uint16
```

Summarizes adopted chassis commands plus compact referee fields. `is_attacked` is an MCU-derived latch when HP drops—not a raw referee passthrough.

### 8.3 How the bridge fills `SX` today

- `vx/vy/wz` from the radar-side velocity frame
- `gimbal_yaw_delta` / `gimbal_pitch_delta` currently forced **0**
- `control_flags`, `scan_yaw_rate_deg_s`, `search_pitch_deg` from the **A3 `RobotControl`** side channel

Still TODO: forwarding fine gimbal deltas from the legacy radar tool path.

## 9. Legacy radar-side protocol

The Radar PTY still speaks the **legacy radar tool** wire format.

### 9.1 Radar command frame (19 bytes)

Expected layout:

```text
[0xA5][0x5A][vx:4][vy:4][wz:4][yaw_deg:4][CRC8:1]
```

Total length: **19 bytes**.

- `vx/vy/wz` are translated into **`SX`**
- `yaw_deg` is parsed by the bridge but **not** yet mapped into `SX` gimbal delta fields

### 9.2 Radar-side telemetry: velocity frame + status side channels

The bridge emits **three** frame families toward the Radar PTY:

```text
A6 6A + vx + vy + wz + reserved0 + crc8
5C    + game_progress + stage_remain_time + crc16
5D    + robot_id + current_hp + shooter_heat + team_color + is_attacked + crc16
```

- `A6 6A`: legacy-compatible velocity telemetry
- `0x5C` / `0x5D`: status side channels synthesized from MCU **`ST`**
- `serial_sender.py --ros2` consumes `0x5C/0x5D` and publishes **`/game_status`** and **`/robot_status`**

## 10. `serial_sender.py` vs bridge radar wire format

`nyush-rm-vision/serial_sender.py` now emits **two** bridge-bound frame types:

- 19-byte legacy radar velocity frame
- 16-byte **`A3 RobotControl`** functional frame

### 10.1 Velocity frame is still 19 bytes

Bridge `RADAR_FRAME_SIZE` is **19** and unpacks as:

```text
[0xA5][0x5A][vx:4][vy:4][wz:4][yaw_deg:4][CRC8:1]
```

`serial_sender.py` encodes the same layout.

### 10.2 Field notes

- **`vx/vy/wz`**: chassis velocity command on the radar leg
- **`yaw_deg`**: compatibility field; sender maps legacy `gimbal_yaw_rad` to degrees; bridge **only** applies `vx/vy/wz` today
- **`gimbal_pitch_rad`**: not in the 19-byte wire; kept in signatures for API compat but **ignored** on transmit

### 10.3 Takeaways

- Repo `nyush-rm-vision/serial_sender.py` can attach directly to the **Radar PTY**
- A stale copy e.g. on Desktop must be **synced** with the repo version
- Topology is settled: vision → **Vision PTY**; nav/radar sender → **Radar PTY**; real **`/dev/ttyACM0`** → **`sentry_bridge.py` only**

Recent behavior:

- Bridge writes `vx/vy/wz` into **`SX`** and also maps **`A3 RobotControl`** fields `scan_enabled`, `allow_vision_control`, `search_when_target_lost`, `scan_yaw_rate_deg_s`, `search_pitch_deg` into **`SX`**
- `serial_sender.py --ros2` subscribes to **`/cmd_vel_chassis_bt`** and **`/robot_control`**
- It republishes bridge `0x5C/0x5D` as **`/game_status`** / **`/robot_status`**
- `stop_gimbal_scan` remains for old-tree compat but is demoted
- Fine gimbal **`yaw_delta` / `pitch_delta`** on the radar leg is still **not** wired through

## 11. ROS 2 topic graph

### 11.1 Navigation → chassis

Current `sentry_planner` velocity chain:

```text
Nav2 -> /cmd_vel -> fake_vel_transform -> /cmd_vel_chassis -> bt_comm_adapter.py -> /cmd_vel_chassis_bt
```

- **`/cmd_vel`**: raw Nav2 output
- **`/cmd_vel_chassis`**: frame-transformed chassis twist
- **`/cmd_vel_chassis_bt`**: `bt_comm_adapter.py` merges **`/cmd_vel_chassis`** with **`/robot_control.chassis_spin_vel`**

For the bridged radar path, **`/cmd_vel_chassis_bt`** is the right sink.

**Yaw-rate policy (aligned with `scripts/bt_comm_adapter.py`, from 2026-04):**

- `fake_vel_transform` may reshape Nav2 `wz` per team config (see nav / lidar READMEs).
- **`bt_comm_adapter.py` does not forward `/cmd_vel_chassis.angular.z` into `/cmd_vel_chassis_bt`**. Output **`angular.z` comes only from `/robot_control.chassis_spin_vel`**, so Nav2-planned in-place spin does not fight the “move straight, spin only when holding” sentry policy.
- To let Nav2 drive spin directly again, change the **Python node** (merge or passthrough), not launch params alone.

### 11.2 Decision stack → vision

Listed below are topics the BT code **can** subscribe to via registered plugins; whether a given XML uses one depends on `Sub*` nodes in that tree.

- Default **`center_attack_simple`** uses only **`/game_status`** and **`/robot_status`** (see behavior-tree doc).
- Older trees (e.g. **`retreat_attack_left`**) also pull **`/detector/armors`**, **`/all_robot_hp`**, etc.

Possible subscriptions:

- `/detector/armors`
- `/game_status`
- `/robot_status`
- `/all_robot_hp`

On the real robot, **`/game_status`** / **`/robot_status`** usually come from **`serial_sender.py --ros2`** parsing bridge telemetry. `bt_hotkey_debug.py` can spoof them for debug—that overrides upstream, it is not the default.

Vision-facing input is still primarily **`/detector/armors`**. `IsDetectEnemy` today only checks whether **`armors`** is non-empty—no per-class routing (hero, engineer, infantry, …).

### 11.3 Reserved vision → planner hook

`nyush-rm-vision` already publishes:

- Topic: **`auto_aim_target_pos`**
- Type: `std_msgs/String`
- Payload: `x,y,z,target_id` with `target_id = armor.name + 1` in current code.

So class IDs can leave vision, but **`sentry_planner` does not consume this topic yet.**

## 12. Bring-up procedures

Three layers:

- Bridge self-check
- Vision leg self-check
- Recommended full-stack order on hardware

### 12.1 Bridge self-check

Terminal 1:

```bash
cd /home/nyu/Codespace/nyush-rm-control
just py-bootstrap
just sentry-bridge --self-test
just sentry-bridge --port /dev/ttyACM0
```

Expect:

```text
MCU serial : /dev/ttyACM0
Vision PTY : /dev/pts/3
Radar PTY  : /dev/pts/4
```

Record both PTY paths.

#### MCU dashboard (optional)

For the C-board RTT dashboard instead of bridge logs only:

```bash
cd /home/nyu/Codespace/nyush-rm-control
just logger
```

Open:

```text
http://127.0.0.1:8080
```

That page is the **MCU dashboard**, not the vision detection UI.

### 12.2 Vision protocol self-check

Terminal 2—interactive tool on the **Vision PTY**:

```bash
cd /home/nyu/Codespace/nyush-rm-control
just vision --port /dev/pts/3
```

Useful to:

- Read MCU **`SP`**
- Inject **`VisionToGimbal`**

Validates bridge health, live MCU frames, CRC / length / mode bits before vision stack runs.

### 12.3 Radar protocol self-check

Terminal 3—mock client on **Radar PTY**:

```bash
cd /home/nyu/Codespace/nyush-rm-control
just radar --port /dev/pts/4
```

Interactive commands:

```text
set vx vy wz [yaw_deg]
stop
rate hz
state
pulse vx vy wz sec
```

Checks radar bytes → **`SX`**, MCU **`ST`**, and that chassis commands take effect.

### 12.4 Vision mainline on the bridge

Point vision `com_port` at the bridge’s **Vision PTY** (prefer stable symlinks if the bridge creates them).

Recommended vision command on hardware:

```bash
cd /home/nyu/Codespace/nyush-rm-vision
just test detect --web --send
```

Notes:

- Run inside **`nyush-rm-vision`**, not `nyush-rm-control`.
- Starts detection test and sends control on the configured **`com_port`**.
- Default UI: **`http://127.0.0.1:8888`**
- For real vision takeover, RC **left switch mid** as per firmware policy.
- `detect` path is **track-on-detect**, not a full auto-search program.

Full **`./build/sentry configs/sentry.yaml`** is optional; if used, ensure the binary exists and **`com_port`** matches the current Vision PTY. For bridge + BT + auto-aim bring-up, **`just test detect --web --send`** is the default mainline.

### 12.5 Full hardware stack (recommended)

Assumed topology:

- `nyush-rm-control`: bridge + optional dashboard
- `nyush-rm-vision`: `detect --web --send`
- `sentry_planner`: Mid360 + FAST-LIO + Nav2 + BT + `bt_comm_adapter.py`
- `serial_sender.py` on **Radar PTY** for **`/cmd_vel_chassis_bt`** + **`/robot_control`**, and publishes **`/game_status`** / **`/robot_status`**

Pre-flight:

- MCU flashed with current sentry firmware
- Do **not** run `rm_serial_driver` on the same **`/dev/ttyACM0`**
- If your shell is `bash`, source **`*.bash`** overlays consistently
- `start_robot.sh` does not enable RViz by default; set **`ENABLE_RVIZ=1`** only on a machine with a display

**Terminal 1 — bridge**

```bash
cd /home/nyu/Codespace/nyush-rm-control
just sentry-bridge --port /dev/ttyACM0
```

Note:

```text
Vision PTY : /dev/pts/X
Radar PTY  : /dev/pts/Y
```

Prefer stable links if printed:

```text
/tmp/nyush-rm-sentry-vision
/tmp/nyush-rm-sentry-radar
```

**Terminal 1B (optional) — MCU dashboard**

```bash
cd /home/nyu/Codespace/nyush-rm-control
just logger
```

`http://127.0.0.1:8080`

**Terminal 2 — vision**

```bash
cd /home/nyu/Codespace/nyush-rm-vision
just test detect --web --send
```

`http://127.0.0.1:8888`

**Terminal 3 — nav + BT + serial sender**

```bash
bash
cd /home/nyu/sentry_planner
START_SERIAL_SENDER=1 RADAR_PTY=/tmp/nyush-rm-sentry-radar ./start_robot.sh
```

Without symlinks, substitute the live Radar PTY, e.g.:

```bash
START_SERIAL_SENDER=1 RADAR_PTY=/dev/pts/4 ./start_robot.sh
```

Default map: `.../rm_nav_bringup/map/RMUL2026.yaml`. Override with **`MAP_FILE=...`** if needed.

`start_robot.sh` typically brings up: `livox_ros_driver2`, static TF, `fast_lio`, `pointcloud_to_laserscan`, `nav2_bringup`, `bt_comm_adapter.py`, `rm_behavior_tree`, optional **`serial_sender.py`**.

With RViz:

```bash
ENABLE_RVIZ=1 START_SERIAL_SENDER=1 RADAR_PTY=/tmp/nyush-rm-sentry-radar ./start_robot.sh
```

**Terminal 4 (optional) — BT hotkeys**

```bash
bash
source /opt/ros/humble/setup.bash
source /home/nyu/sentry_planner/rm_decision_ws/install/setup.bash
python3 /home/nyu/sentry_planner/scripts/bt_hotkey_debug.py
```

Keys: `0` HOME_STANDBY, `1` APPROACH_CENTER, `2` low-HP recovery, `3` high-heat recovery, `4` under-attack branch, `p` print preset, `h` help, `q` quit.

Hotkeys can fake game/robot state, but branches like **`CENTER_HOLD_ATTACK`** still need real **`map → base_link`** pose—not hotkey alone.

**Terminal 5 (optional) — Groot2**

```bash
cd ~/Desktop
./Groot2-v1.9.0-x86_64.AppImage
```

**AppImage filename** must match what is on `~/Desktop` (see **[mid360 command.txt](mid360%20command.txt)** §13). Then:

- Open `.../rm_behavior_tree/config/Project.btproj`
- **Monitor** → `127.0.0.1:1667` with `enable_groot:=true` ([README_BEHAVIOR_TREE_FLOW.md §18.1](README_BEHAVIOR_TREE_FLOW.md#181-groot2-workflow))

Full Gazebo + Nav2 + BT order (Sim2Real step 1): [README_LIDAR.md §6.4](README_LIDAR.md#nyush-gazebo-sim2real); staged `topic pub` flows: **mid360 command.txt**.

### 12.6 Hardware smoke checklist

```bash
lsof /dev/ttyACM0
ros2 topic echo /robot_control --once
ros2 topic echo /cmd_vel_chassis_bt --once
ros2 topic echo /game_status --once
ros2 topic echo /robot_status --once
ros2 topic echo /detector/armors --once
```

To confirm referee traffic at rate:

```bash
ros2 topic hz /game_status
ros2 topic hz /robot_status
```

Healthy signs:

- Only **`sentry_bridge.py`** on **`/dev/ttyACM0`**
- **`/robot_control`** shows `scan_*`, `allow_vision_control`, `search_when_target_lost`, etc.
- **`/cmd_vel_chassis_bt`** shows nav linear + small-spin `angular.z`
- **`/game_status`** / **`/robot_status`** live without hand-`pub` when referee is online
- **`/detector/armors`** non-empty when vision sees a target

On-robot RC:

- After power-on, **right switch up** → `READY`
- **Left switch mid** when you want vision takeover semantics
- For BT/nav-only tests you can skip vision takeover
- `detect --web --send` is **not** full search; it is **follow when detected**

### 12.7 Manual ROS 2 debugging (no full BT stack)

To validate **`serial_sender → bridge → MCU`** you do not need `start_robot.sh`.

Minimum setup:

- `just sentry-bridge --port /dev/ttyACM0` in `nyush-rm-control`
- Repo `serial_sender.py --ros2 --topic /cmd_vel_chassis_bt`
- Robot not e-stopped; avoid **right switch mid** sentry spin mode while testing BT gimbal paths

**Minimal chassis takeover** — terminal 1, hold BT flags:

```bash
source /opt/ros/humble/setup.zsh
source /home/nyu/sentry_planner/rm_decision_ws/install/setup.zsh
ros2 topic pub -r 20 /robot_control rm_decision_interfaces/msg/RobotControl \
"{stop_gimbal_scan: false, chassis_spin_vel: 0.0, scan_enabled: true, allow_vision_control: false, search_when_target_lost: false, scan_yaw_rate_deg_s: 90.0, search_pitch_deg: 0.0}"
```

Terminal 2, chassis twist:

```bash
source /opt/ros/humble/setup.zsh
ros2 topic pub -r 20 /cmd_vel_chassis_bt geometry_msgs/msg/Twist \
"{linear: {x: 0.20, y: 0.00, z: 0.00}, angular: {x: 0.00, y: 0.00, z: 0.00}}"
```

Notes:

- Publishing **`/cmd_vel_chassis`** or **`/cmd_vel_chassis_bt` alone is insufficient**; MCU expects **`/robot_control`** to refresh so BT is treated as a valid commander.
- `start_robot.sh`’s sender defaults to **`/cmd_vel_chassis_bt`**, not **`/cmd_vel_chassis`**.
- When velocity is ingested, sender logs e.g. `[NAV2 -> STM32] vx=...`—fast proof the bridge path is live.

**Gimbal scan only** (fixed pitch, yaw sweep):

```bash
source /opt/ros/humble/setup.zsh
source /home/nyu/sentry_planner/rm_decision_ws/install/setup.zsh
ros2 topic pub -r 20 /robot_control rm_decision_interfaces/msg/RobotControl \
"{stop_gimbal_scan: false, chassis_spin_vel: 0.0, scan_enabled: true, allow_vision_control: false, search_when_target_lost: false, scan_yaw_rate_deg_s: 120.0, search_pitch_deg: -6.0}"
```

**Search-then-track** (matches **left switch mid** auto-aim semantics: scan when no target, vision when locked)—use this, not the line above:

```bash
source /opt/ros/humble/setup.zsh
source /home/nyu/sentry_planner/rm_decision_ws/install/setup.zsh
ros2 topic pub -r 20 /robot_control rm_decision_interfaces/msg/RobotControl \
"{stop_gimbal_scan: true, chassis_spin_vel: 0.0, scan_enabled: true, allow_vision_control: true, search_when_target_lost: true, scan_yaw_rate_deg_s: 120.0, search_pitch_deg: -6.0}"
```

With vision:

```bash
cd /home/nyu/Codespace/nyush-rm-vision
just test detect --web --send
```

`http://127.0.0.1:8888`

In `detect --web --send`: **`AUTO_AIM`** only when a target is seen; no auto fire by default; log **`sent_ctl=true`** means vision is commanding.

Common pitfalls:

- Stopping **`/robot_control`** lets BT takeover time out → local RC logic resumes.
- **Right switch mid** sentry spin can override the BT/vision gimbal chain.
- **Functional scan** vs **search semantics**: fixed pitch vs pitch nod; vision packets interrupt scan—stop `just test detect` while isolating pure scan.

### 12.8 `serial_sender --ros2`: `/robot_control` has zero subscribers → no motion

Confirmed on 2026-03-21 bring-up.

Symptoms: bridge running; sender with `--ros2`; **`/cmd_vel_chassis`** has a subscriber; **`/robot_control`** has none; chassis ignores injected velocity.

Cause: environment sourced only:

```bash
source /opt/ros/humble/setup.zsh
```

without the workspace overlay, e.g.:

```bash
source /home/nyu/sentry_planner/install/setup.zsh
```

Then Python cannot import **`rm_decision_interfaces/msg/RobotControl`**, `--ros2` falls back to **Twist-only**, and **`/robot_control`** never reaches the process. MCU still requires valid control flags for bridged chassis.

Check:

```bash
source /opt/ros/humble/setup.zsh
source /home/nyu/sentry_planner/install/setup.zsh
ros2 topic info /cmd_vel_chassis -v
ros2 topic info /robot_control -v
```

Expect **subscription count ≥ 1** on both. If you see:

```text
/cmd_vel_chassis -> Subscription count: 1
/robot_control   -> Subscription count: 0
```

fix the overlay and restart sender—do not blame MCU or bridge framing first.

Example launch:

```bash
source /opt/ros/humble/setup.zsh
source /home/nyu/sentry_planner/install/setup.zsh
python3 /home/nyu/Codespace/nyush-rm-vision/serial_sender.py \
  --port /tmp/nyush-rm-sentry-radar \
  --ros2 \
  --topic /cmd_vel_chassis \
  --robot-control-topic /robot_control
```

**`--keyboard`** emits legacy velocity only—no **`RobotControl`**—and under current MCU policy usually **will not** drive chassis over the bridge. Prefer **`--ros2`** for bridge bring-up.

## 13. What is wired vs reserved

### 13.1 Working or mostly working

- MCU multiplexes vision **`SP`** and sentry **`SX`/`ST`**
- Bridge splits one CDC into Vision + Radar PTYs
- Vision **`io::Gimbal`** attaches to Vision PTY
- Nav2 → **`/cmd_vel_chassis`** path in `sentry_planner` is clear
- **`bt_comm_adapter.py`** fuses **`/cmd_vel_chassis`** + **`/robot_control.chassis_spin_vel`** → **`/cmd_vel_chassis_bt`**
- HP topic for BT is **`/all_robot_hp`**

### 13.2 Reserved / incomplete

- **`auto_aim_target_pos`** vision → planner string channel

**`/robot_control`** is on the bridge/MCU path; the missing piece is higher-level **vision → decision** closure.

### 13.3 Do not mix

**`rm_serial_driver`** and **`sentry_bridge.py`** both want the real serial device. If you standardize on **`nyush-rm-control` + `sentry_bridge.py`**, do not open the same **`/dev/ttyACM0`** with **`rm_serial_driver`**.

## 14. Field troubleshooting

### 14.1 Who owns `/dev/ttyACM0`

```bash
lsof /dev/ttyACM0
```

Expect only **`sentry_bridge.py`**.

### 14.2 PTYs printed

```text
Vision PTY : /dev/pts/X
Radar PTY  : /dev/pts/Y
```

### 14.3 Nav velocities

```bash
source /opt/ros/humble/setup.bash
source /home/nyu/sentry_planner/install/setup.bash
ros2 topic hz /cmd_vel /cmd_vel_chassis
```

### 14.4 Vision detections

```bash
ros2 topic echo /detector/armors --once
```

### 14.5 BT consuming vision

Any non-empty **`armors`** counts as “enemy seen.” Fake feed:

```bash
cd /home/nyu/sentry_planner
source rm_decision_ws/install/setup.bash
source rm_vision_ws/install/setup.bash
./rm_decision_ws/rm_decision_interfaces/publish_script.sh
```

### 14.6 Radar PTY loopback

```bash
cd /home/nyu/Codespace/nyush-rm-control
just radar --port <Radar PTY>
```

Seeing telemetry implies **`Radar PTY → bridge → MCU → ST → bridge → Radar PTY`** at the protocol layer.

## 15. Risks and notes

### 15.1 Protocol drift

At least two “radar host” frame sizes exist in the wild:

- Bridge path: **19 bytes**
- Older **`serial_sender`**: **23 bytes**

Implementation lag, not intentional dual design.

### 15.2 PTY numbers move

After each bridge restart **`/dev/pts/N`** may change. Prefer **symlinks** or export PTYs into your launcher immediately.

### 15.3 Hardware bring-up (comm summary)

- **Topology**: vision ↔ **Vision PTY** ↔ **`sentry_bridge`** ↔ MCU; planner/nav ↔ **Radar PTY**; **real USB serial only for the bridge** (§1).
- **`start_robot.sh` does not start the bridge**; **`serial_sender`** must target the **current Radar PTY** (or **`START_SERIAL_SENDER` + `RADAR_PTY`**); see [README_COMMANDS.md §4](README_COMMANDS.md#readme-commands-section-4) and [§12](README_COMMANDS.md#readme-commands-section-12).
- **`/cmd_vel_chassis_bt`** and **`/robot_control`** (including **`scan_*`**, **`allow_vision_control`**, **`chassis_spin_vel`**) reach MCU via sender/A3; staged checks, fake referee, `navigate_to_pose` prerequisites: same README §12.
- Vision **`com_port`** in **`nyush-rm-vision`** must be the **Vision PTY** from the bridge banner—**not** raw ACM0.

### 15.4 Class ID path not in BT yet

BT mostly keys off **`/detector/armors` non-empty**. **`auto_aim_target_pos`** carries a class index but **`sentry_planner` does not subscribe** today.

### 15.5 `rm_serial_driver` vs bridge

Legacy ROS serial stack vs new multiplex bridge—**never both** on the same ACM port.

### 15.6 Cross-doc index

| Topic | Doc |
|------|-----|
| BT XML, `SendGoal`, `RobotControl`, tactics | [README_BEHAVIOR_TREE_FLOW.md](README_BEHAVIOR_TREE_FLOW.md) |
| End-to-end paths, env, maps, hardware steps | [README_COMMANDS.md](README_COMMANDS.md) (**§1, §4, §12, §13** → anchors **#readme-commands-section-1**, **#readme-commands-section-4**, **#readme-commands-section-12**, **#readme-commands-section-13**) |
| Gazebo RMUL2026, Sim2Real | [README_LIDAR.md §6.4](README_LIDAR.md#nyush-gazebo-sim2real), [mid360 command.txt](mid360%20command.txt) |
| Mid360, FAST-LIO, Nav2, live localization | [README_LIDAR.md](README_LIDAR.md) (§6.4 sim, §10.8 hardware) |
| One-page index | [README.md](README.md) |

## 16. Suggested convergence work

1. Drive **`/robot_control`** deeper into match state machines—`scan_*` / `allow_vision_control` / `search_when_target_lost` already reach MCU; next step is more BT nodes, not RC mimicry.
2. Widen live referee inputs beyond **`/game_status`** / **`/robot_status`**—e.g. richer **`/all_robot_hp`**—to reduce fallback publishers.

---

One-line reminder:

```text
Only sentry_bridge.py on /dev/ttyACM0;
vision on Vision PTY;
nav/radar on Radar PTY;
repo serial_sender.py matches the bridge wire format.
```
