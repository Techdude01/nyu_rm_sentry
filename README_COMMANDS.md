

# NYUSH sentry: common commands and data flow

Last updated: 2026-04-11

Use this file together with `[communication command.txt](communication%20command.txt)`: **principles, data flow, and parameter meaning live here**; `communication command.txt` is mainly **copy-paste snippets**. Protocol details remain authoritative in `[README_COMMUNICATION.md](README_COMMUNICATION.md)`.

---

## 0. How the five READMEs split work


| Document                                                     | Role                                                                                                      |
| ------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------- |
| [README.md](README.md)                                       | **Central index**: one-page overview, diagram, build order, shortest startup                              |
| [README_COMMUNICATION.md](README_COMMUNICATION.md)           | **Comms and protocol**: frames, PTY, `serial_sender`, `bt_comm_adapter` (depth in that file **§5–§15**)   |
| [README_BEHAVIOR_TREE_FLOW.md](README_BEHAVIOR_TREE_FLOW.md) | **Behavior trees**: XML, nodes, `RobotControl` meaning, Groot2, **§5.1** coordinates and watcher          |
| [README_LIDAR.md](README_LIDAR.md)                           | **LiDAR + Nav2**: Mid360, FAST-LIO, parameters, **§10.8** hardware localization prerequisites             |
| **This file**                                                | **Commands and data flow**: runnable commands, environment variables, script map, end-to-end path summary |


**How to choose:** copy commands, understand `**MAP_FILE` / goals**, phased hardware steps → **this file**; protocol fields and MCU frames → [README_COMMUNICATION.md](README_COMMUNICATION.md); how the tree branches and what XML says → [README_BEHAVIOR_TREE_FLOW.md](README_BEHAVIOR_TREE_FLOW.md); LiDAR and costmap behavior → [README_LIDAR.md](README_LIDAR.md).

**Section index**


| Section    | Content                                                                                                                |
| ---------- | ---------------------------------------------------------------------------------------------------------------------- |
| **§1**     | MCU / LiDAR / vision / BT / host–MCU, four paths A–D                                                                   |
| **§2**     | Bridge auto port pick and PTY                                                                                          |
| **§3**     | Vision web UI and how it relates to BT / `RobotControl`                                                                |
| **§4**     | `nav_ws/start_robot.sh` environment variables; **§4.4** `11_map` / `RMUL2026`, PCD / PGM / YAML, map swap and BT goals |
| **§5–§6**  | Referee topics, `watch_`*, hotkeys                                                                                     |
| **§7**     | `rotate_pcd` → `pcd2pgm` → `map_saver_cli`; **§7.4** `map_point_picker.py`                                             |
| **§8–§11** | `autostart`, script table, minimal terminals, `communication command.txt` notes                                        |
| **§12**    | **Hardware bring-up**: bench → small field → full field, safety, terminals, checklist, mock referee                    |
| **§13**    | **Which README for which question**                                                                                    |


**Boundaries:** **§1** here is the **end-to-end overview**; **SP/SX/ST** byte layout is in [README_COMMUNICATION.md](README_COMMUNICATION.md). **§4.4, §7** are map and mapping **commands**; **Gazebo RMUL2026, Sim2Real first step, Groot2 vs sim** follow [README_LIDAR.md §6.4](README_LIDAR.md#nyush-gazebo-sim2real) (step-by-step also in [mid360 command.txt](mid360%20command.txt)). **Tilted LiDAR TF and performance** → [README_LIDAR.md](README_LIDAR.md).

---

## 1. End-to-end data paths and responsibilities

### 1.1 Physical layers: what runs where


| Layer                        | Hardware / process                                                          | Notes                                                                                  |
| ---------------------------- | --------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| **Host (NUC, etc.)**         | ROS 2: LiDAR driver, FAST-LIO, Nav2, BT, `serial_sender`, `bt_comm_adapter` | Localization, planning, decision; packs **velocity + mode** into serial-side protocol  |
| **Bridge (usually on host)** | `sentry_bridge.py`                                                          | **Only** process holding USB CDC; splits **Vision PTY** and **Radar PTY**              |
| **MCU**                      | STM32 (`nyush-rm-control`)                                                  | Parses **SX/ST, SP**; fuses commands; drives chassis / gimbal / shooter; reads referee |


**LiDAR (Mid360)** is on the robot, **Ethernet** to the host, **not** via MCU USB. Point cloud / odometry live as ROS **topics and TF** for Nav2 and BT.

---

### 1.2 Four main data paths (sensor to actuation)

```text
[A — Localization / navigation / chassis translation]
Mid360 -(Ethernet)-> livox_ros_driver2 -> FAST-LIO -> /cloud_registered, odometry, TF
       -> pointcloud_to_laserscan -> /scan -> Nav2 -> /cmd_vel
       -> fake_vel_transform -> /cmd_vel_chassis
       -> bt_comm_adapter (merge chassis_spin_vel) -> /cmd_vel_chassis_bt
       -> serial_sender -> Radar PTY -> bridge -> MCU
       -> SX(vx,vy,wz,...) -> chassis (swerve solve on MCU)

[B — Behavior tree / modes and chassis spin intent]
BT subscribes /game_status, /robot_status, ... -> logic
BT publishes /goal_pose -> Nav2 (path A only, not serial)
BT publishes /robot_control -> serial_sender -> A3 feature frame -> Radar PTY -> bridge -> MCU
       -> SX.control_flags, scan_*, allow_vision_control, ...
       -> robot_cmd.c: whether vision is honored, BT scan, together with vx/vy/wz in state machine

[C — Vision servo / gimbal angles and firing]
Camera -> nyush-rm-vision -> SP(VisionToGimbal) -> Vision PTY -> bridge -> MCU
     -> when allow flags valid, SP yaw/pitch/mode for track and fire
MCU -> SP(GimbalToVision) -> vision loop (pose, bullet speed, etc.)

[D — Referee and robot status to host]
Referee -> MCU -> ST -> bridge -> Radar PTY side 0x5C/0x5D
     -> serial_sender -> /game_status, /robot_status -> BT subscribes
```

A and B merge on **Radar PTY** as **velocity frame + A3**; C uses **Vision PTY** alone; D shares the **Radar return path** with A/B and is unpacked to ROS in the sender.

---

### 1.3 Module responsibilities (quick reference)


| Module                      | Where           | Responsibility                          | Main interface                 |
| --------------------------- | --------------- | --------------------------------------- | ------------------------------ |
| **LiDAR + driver**          | On robot + host | Point cloud                             | `/livox/lidar`, etc.           |
| **FAST-LIO**                | Host            | Odometry, registration                  | `/cloud_registered`, odom, TF  |
| **pointcloud_to_laserscan** | Host            | 2D laser                                | `/scan`                        |
| **Nav2**                    | Host            | Planning, avoidance                     | `/cmd_vel`                     |
| **fake_vel_transform**      | Host            | Velocity frame change                   | `/cmd_vel_chassis`             |
| **bt_comm_adapter**         | Host            | Merge velocity + spin                   | `/cmd_vel_chassis_bt`          |
| **rm_behavior_tree**        | Host            | High-level tactics, goals, RobotControl | `/goal_pose`, `/robot_control` |
| **serial_sender --ros2**    | Host            | ROS ↔ Radar PTY; status inject          | 19 B velocity + A3             |
| **sentry_bridge**           | Host            | One USB ↔ two PTYs; frame conversion    | SP / SX / ST                   |
| **nyush-rm-vision**         | Host            | Detect, track, aim                      | SP                             |
| **MCU**                     | C board         | Execute and fuse                        | SX+SP+RC -> chassis / gimbal   |


---

### 1.4 RobotControl (SX) vs SP


| Channel               | Typical content                                      | Producer     |
| --------------------- | ---------------------------------------------------- | ------------ |
| **SX / RobotControl** | Vision allow, scan params, `chassis_spin_vel`, flags | BT -> sender |
| **SP**                | Target yaw/pitch, auto-aim / fire mode               | Vision       |


MCU uses **SX flags** for `**vision_enabled`**, etc.; only when true does **SP tracking** feed the gimbal loop (see `nyush-rm-control/application/cmd/robot_cmd.c`).

---

### 1.5 Simplified logic (see §1.2)

```text
                    ┌───────────── BT (rm_behavior_tree)
                    │  sub: /game_status, /robot_status, …
                    │  pub: /goal_pose, /robot_control
                    └──────┬───────────────────────┬──────────────┐
                           │                       │
                           ▼                       ▼
                    ┌──────────────┐      ┌─────────────────────────┐
                    │    Nav2      │      │ bt_comm_adapter.py      │
                    │  /cmd_vel    │      │ /cmd_vel_chassis +      │
                    └──────┬───────┘      │ /robot_control →        │
                           │              │ /cmd_vel_chassis_bt     │
                           ▼              └────────────┬────────────┘
                    ┌──────────────┐                 │
                    │fake_vel_     │                 │
                    │transform     │                 │
                    └──────┬───────┘                 │
                           │                         │
                           └────────────┬────────────┘
                                        ▼
                              serial_sender.py --ros2
                                        │
                                        ▼
                              Radar PTY -> sentry_bridge -> MCU (SX)
                                        ▲
MCU referee/status <- ST -- bridge --> 0x5C/0x5D --> serial_sender --> /game_status, /robot_status

Vision: nyush-rm-vision <-> SP <-> Vision PTY <-> bridge <-> MCU
```

---

## 2. Starting the bridge (do not hard-code `/dev/ttyACM0`)

### 2.1 Recommended command

```bash
cd /path/to/nyush-rm-control
just sentry-bridge
```

Same as running `sentry_bridge.py` **without `--port`**.

### 2.2 Auto port behavior

`sentry_bridge.py` `--port` help: **auto-detect by default**. Implementation enumerates USB serial ports and picks MCU CDC by priority (see `resolve_serial_port` / `port_priority` in the script).

After USB replug, `ttyACM0` may become `ttyACM1`; **auto pick** avoids editing commands.

### 2.3 When to pass `--port` explicitly

- Several USB serial devices plugged; wrong auto pick: `just sentry-bridge --port /dev/ttyACM1`
- Debug with a fixed device.

### 2.4 After bridge starts, write these down

The terminal prints **MCU serial** (real port), **Vision PTY**, **Radar PTY**. Unless `--no-links`, stable symlinks (e.g. `/tmp/nyush-rm-sentry-radar`) exist; `**RADAR_PTY` for nav should prefer the symlink** so `/dev/pts/N` does not change every restart.

---

## 3. Vision: `just test detect --web --send`

### 3.1 Command and web UI

```bash
cd /path/to/nyush-rm-vision
just test detect --web --send
```

- `**--web**`: local HTTP server, **default** `http://127.0.0.1:8888` (per vision repo justfile), for debug view and tuning.
- `**--send`**: send vision over serial protocol; **port must be Vision PTY** (set `com_port` in vision config to the bridge Vision path or stable symlink).

### 3.2 Relation to BT: related, but default tree does not subscribe to armor

Two different things:

1. **“Target acquired / auto-aim”** — mainly **vision → Vision PTY → SP → MCU**; detection, tracking, gimbal commands on this path.
2. **“Should BT branch on enemy seen?”** — that is whether BT subscribes `**/detector/armors`** (or other vision topics).

`**center_attack_simple.xml` only has `SubRobotStatus` and `SubGameStatus`, no `SubArmors`, no `IsDetectEnemy`.** So:

- Vision **is** used; the tree **does not** put “saw armor” in conditions.
- At center hold, BT sets `**RobotControl`** e.g. `**allow_vision_control=True`, `stop_gimbal_scan=True**` as **mode bits**; **actual track** is still **vision + SP**, not BT armor subscription.
- In transit with `**allow_vision_control=False`**, behavior leans **scan**; vision can still run and the web UI still shows detections; MCU + flags decide takeover (firmware is source of truth).

**When armor topic matters for BT:** legacy trees with `**SubArmors` + `IsDetectEnemy`** (e.g. `**retreat_attack_left.xml**`): BT **subscribes** `/detector/armors` for **enemy seen / not** branches.

**Optional third path:** `bt_comm_adapter.py` can synthesize `**/detector/armors`** from `**auto_aim_target_pos**` for trees that need it; different from **SP straight to MCU**.

**Summary:**

- **Vision and BT interact:** BT uses `**/robot_control`** for **scan, allow auto-aim, spin**; vision owns **perception and SP**.
- **Default simple tree skips armor subscription** on purpose; **target loop** is **vision–MCU**; BT focuses **match state, HP, go-to-point, home**.


| Path                           | Role                                                                         |
| ------------------------------ | ---------------------------------------------------------------------------- |
| Vision → MCU                   | **SP**: gimbal and fire control, **not** through BT nodes.                   |
| BT → MCU (via `serial_sender`) | **SX** / **RobotControl**: `scan_`*, `allow_vision_control`, etc. **modes**. |
| BT ← `/detector/armors`        | **Legacy trees** only when XML includes `SubArmors` / enemy checks.          |


---



## 4. `~/nav_ws/start_robot.sh`: environment variables for debugging

Typical pattern: **bridge + (optional) vision running** → **your map + Nav + BT**:

```bash
cd ~/nav_ws
MAP_FILE="/home/nyu/Desktop/map/11_map.yaml" \
BT_STYLE=center_attack_fullstack \
BT_START_GOAL="0.407;0.130;0; 0;0;0;1" \
BT_END_GOAL="1.083;0.767;0; 0;0;0;1" \
START_SERIAL_SENDER=1 \
SERIAL_SENDER_DISABLE_STATUS_PUB=0 \
START_BT=1 \
RADAR_PTY=/tmp/nyush-rm-sentry-radar \
START_FAKE_VEL_TRANSFORM=1 \
./start_robot.sh
```

### 4.1 Variable reference


| Variable                               | Meaning                                                                                                                                                                                               |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `**MAP_FILE**`                         | Nav2 `map_server` **map yaml** (references **pgm**). Lab map `**11_map`**; field `**RMUL2026.yaml**`. See **§4.4**.                                                                                   |
| `**BT_STYLE`**                         | Behavior XML **without `.xml`**. `center_attack_fullstack` = full stack; `center_attack_simple` = simple (common default in `sentry_planner/start_robot.sh`).                                         |
| `**BT_START_GOAL` / `BT_END_GOAL**`    | Passed to `rm_behavior_tree` as `**start_goal_pose` / `end_goal_pose**` on the blackboard; format `x;y;z; qx;qy;qz;qw`. After a map swap, reconcile with hard-coded `**SendGoal**` in XML (**§4.4**). |
| `**START_SERIAL_SENDER=1`**            | Starts `**serial_sender.py --ros2**` in the background; writes ROS velocity and control to `**RADAR_PTY**`.                                                                                           |
| `**RADAR_PTY**`                        | **Must match** the current bridge Radar side (prefer `/tmp/nyush-rm-sentry-radar`). Script maps this to `SERIAL_SENDER_PORT`.                                                                         |
| `**START_BT=1`**                       | Starts `**bt_comm_adapter.py**` + `**rm_behavior_tree**`. Forces `**SERIAL_SENDER_TOPIC` to `/cmd_vel_chassis_bt**` (if it was `/cmd_vel_chassis`) so BT `chassis_spin_vel` merges correctly.         |
| `**SERIAL_SENDER_DISABLE_STATUS_PUB**` | Passed to sender as `**--disable-status-pub**`: `0` = **publish** `/game_status`, `/robot_status` (from 0x5C/0x5D); `1` = do not publish (avoid fighting hotkey or other mock referee).               |
| `**START_FAKE_VEL_TRANSFORM=1`**       | Starts `**fake_vel_transform**`: `/cmd_vel` → `/cmd_vel_chassis`. Aligns Nav2 with chassis frame / gimbal compensation.                                                                               |


### 4.2 Workspaces sourced inside the script

By default sources `**~/nav_ws/install**`, `**sentry_planner/install**` (if present), `**rm_vision_ws**`, `**rm_decision_ws**` so `rm_behavior_tree`, `fake_vel_transform`, and `serial_sender` message types resolve.

### 4.3 `nav_ws/start_robot.sh` vs `sentry_planner/start_robot.sh`

- `**nav_ws/start_robot.sh**`: main script when **ICP is not** in the loop; Nav2 via **AMCL + bringup_launch**; env vars as above.
- `**sentry_planner/start_robot.sh`**: longer **Mid360 + Fast-LIO + optional ICP** flow; overlapping names but different defaults (see file header).

### 4.4 Map sources; where `PCD` / `PGM` / `YAML` matter; map swap and BT goals

#### 4.4.1 Two common maps (path convention)


| Scenario              | Typical `MAP_FILE`                                                       | Notes                                                                                                                                                   |
| --------------------- | ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Lab / self-mapped** | `$HOME/Desktop/map/11_map.yaml`                                          | After mapping (**§7**), `map_saver_cli -f 11_map` under `**~/Desktop/map/`** yields `**11_map.yaml` + `11_map.pgm**`. Point `**MAP_FILE**` at the yaml. |
| **RMUL 2026 field**   | `…/sentry_planner/rm_navigation_ws/src/rm_nav_bringup/map/RMUL2026.yaml` | Fixed field layout; `**RMUL2026.pgm`** alongside. Point `**MAP_FILE**` at that yaml.                                                                    |


If `**image:**` in yaml is relative, keep **pgm next to yaml**; do not copy yaml alone.

#### 4.4.2 Roles of `PCD`, `PGM`, `YAML`


| Type                    | Typical path                                 | **Who reads it at runtime**                                                                                                                                |
| ----------------------- | -------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **PCD**                 | e.g. `~/nav_ws/src/FAST_LIO/PCD/scans.pcd`   | **Offline mapping only**: `rotate_pcd` → `**pcd2pgm`**. **Nav2 / `map_server` does not load PCD**.                                                         |
| **PGM**                 | Same dir as map yaml, referenced by `image:` | `**map_server` loads grid via yaml**; global costmap, planner, whether `SendGoal` is in free space use this **2D occupancy grid**.                         |
| **YAML** (map metadata) | The file you pass as `**MAP_FILE`**          | **Single entry** for Nav2 map service: resolution, origin, thresholds, **which pgm**. Swapping map = **change `MAP_FILE`** (and ensure pgm path is valid). |


At runtime Nav2 only cares about **map yaml + referenced pgm**; **PCD** is only before that pipeline.

#### 4.4.3 BT start / end goals: remeasure after map swap

Some trees hard-code `**SendGoal`** world poses in XML. After `**11_map` ↔ `RMUL2026**` (or any new map), the **same numbers may land in obstacles or off-field**; remeasure and:

- **Update env before `start_robot.sh`**: `**BT_START_GOAL**`, `**BT_END_GOAL**` (`x;y;z; qx;qy;qz;qw`), and
- **Check / edit XML** for your actual `**BT_STYLE`** (blackboard and XML can coexist; **what the tree nodes use wins**).

**Where coordinates come from:** after saving the map yaml, on a machine with a **GUI** (field PC often via **VNC**), run `**map_point_picker.py`**, click on the map for `**x, y**` relative to map origin, then fill env or XML. Details **§7.4**.

---

## 5. Whether referee data reaches ROS: `/game_status`, `/robot_status`

```bash
source /opt/ros/humble/setup.bash   # or setup.zsh
source /path/to/sentry_planner/rm_decision_ws/install/setup.bash
ros2 topic echo /game_status
ros2 topic echo /robot_status
```

### 5.1 Data path

1. MCU sends compact referee fields on **ST** to **bridge**.
2. Bridge emits **0x5C / 0x5D** on the Radar PTY.
3. `**serial_sender.py --ros2`** parses and **publishes** `GameStatus`, `RobotStatus`.

If **echo updates with sensible fields**, the **host received the referee path** (at least to sender). All zeros or nothing: check bridge, sender, and whether `SERIAL_SENDER_DISABLE_STATUS_PUB` is 1.

---

## 6. Debugging BT without real referee: `watch` + hotkey

### 6.1 `watch_center_attack_state.py` (read-only)

```bash
source /opt/ros/humble/setup.bash
source /path/to/sentry_planner/rm_decision_ws/install/setup.bash
python3 /path/to/sentry_planner/scripts/watch_center_attack_state.py
```

- **Role**: **subscribes** `/amcl_pose`, `/game_status`, `/robot_status`, `/robot_control`, `/cmd_vel_chassis_bt`; prints one status line on a timer.
- **Use**: monitor **BT + Nav pose + comms output**; **does not publish**.
- Run alongside hotkey script: one changes state, one watches.

### 6.2 `bt_hotkey_debug.py` (mock referee)

```bash
source /opt/ros/humble/setup.bash
source /path/to/sentry_planner/rm_decision_ws/install/setup.bash
python3 /path/to/sentry_planner/scripts/bt_hotkey_debug.py
```

- **Role**: **continuously publishes** `/game_status`, `/robot_status` (and sometimes `/detector/armors`); keyboard presets for pre-match / in-match / low HP / high heat / attacked.
- **Use**: **BT debug**; **overwrites** real referee if `serial_sender` also publishes—usually set `**SERIAL_SENDER_DISABLE_STATUS_PUB=1`**.
- Keys and preset names: see `PRESETS` in the script.

---

## 7. After Fast-LIO mapping: rotate PCD → 2D PGM → save Nav2 map

Matches your usual three-command flow.

### 7.1 Rotate point cloud

```bash
cd ~/nav_ws/src/FAST_LIO/PCD
python3 rotate_pcd.py
```

- **Purpose**: correct pose of `**scans.pcd`** (or path in script) so ground and map axes match Nav2.
- **Note**: if `pcd2pgm` launch hard-codes PCD path, keep it aligned with rotate output.

### 7.2 PCD to 2D grid (pgm)

```bash
export LD_PRELOAD=/lib/x86_64-linux-gnu/libusb-1.0.so.0
cd ~/nav_ws
source install/setup.zsh   # or setup.bash
ros2 launch pcd2pgm pcd2pgm_launch.py
```

- **Purpose**: project **3D cloud** to **2D occupancy** for `map_server`.
- `**LD_PRELOAD`**: mitigates some PCL/Open3D vs **libusb** issues (harmless to keep even without LiDAR plugged).

### 7.3 Save Nav2 map

```bash
cd ~/Desktop/map
ros2 run nav2_map_server map_saver_cli -f 11_map
```

- **Purpose**: save current `**/map`** as `**11_map.yaml` + `11_map.pgm**` (`-f` prefix).
- Point `**MAP_FILE**` at that yaml for `start_robot.sh`.
- **PCD/PGM/YAML roles, field `RMUL2026`, retune BT goals on map change**: **§4.4**.

### 7.4 Pick coordinates with `map_point_picker.py` (needs GUI / VNC)

After `**map_saver_cli`** produced `11_map.yaml` (or any ready yaml), you need a **display or VNC** (opens an image window):

```bash
python3 ~/nav_ws/map_point_picker.py ~/Desktop/map/11_map.yaml
```

- **Purpose**: click on the occupancy image for **map-frame `x, y`** (fill `**BT_START_GOAL` / `BT_END_GOAL**` `x;y` parts or XML `SendGoal`).
- For **field map**, use path `**…/rm_nav_bringup/map/RMUL2026.yaml`**.
- If SSH has no X11, run on **local desktop or VNC session**.

---

## 8. Boot autostart: `autostart_fullstack.sh`

```bash
bash /home/nyu/sentry_planner/scripts/autostart_fullstack.sh
```

### 8.1 What it does

1. Optional cleanup of old processes and PTY symlinks.
2. `**systemctl --user restart sentry_bridge.service**` (bridge under systemd; still uses auto port or service args).
3. Wait until `**/tmp/nyush-rm-sentry-vision**` exists.
4. Start `**just test detect --web --send**` (xterm if graphical, else nohup + logs).
5. After clearing Nav/LIO leftovers, run `**~/nav_ws/./start_robot.sh**` with fixed env (`MAP_FILE`, `BT_STYLE=center_attack_fullstack`, `RADAR_PTY=/tmp/nyush-rm-sentry-radar`, etc.—matches script defaults).

### 8.2 Logs

- Under `/home/nyu/sentry_planner/logs/autostart/`: `**vision_detect.log**`, `**nav_bt.log**`, etc.

### 8.3 Field use

Without a laptop, **one command** brings up bridge (via systemd) + vision + Nav + BT + sender, equivalent to several manual terminals.

---

## 9. Script and node cheat sheet


| Component                      | Path or command        | Comms                                             | Nav                                  | Vision                | BT                             |
| ------------------------------ | ---------------------- | ------------------------------------------------- | ------------------------------------ | --------------------- | ------------------------------ |
| `sentry_bridge.py`             | `just sentry-bridge`   | **Core**: holds MCU port, splits Vision/Radar PTY | —                                    | PTY                   | —                              |
| `serial_sender.py --ros2`      | nyush-rm-vision        | Radar PTY ↔ ROS                                   | consumes `/cmd_vel_chassis_bt`, etc. | —                     | consumes `/robot_control`      |
| `bt_comm_adapter.py`           | sentry_planner/scripts | emits `/cmd_vel_chassis_bt`                       | bridges `/cmd_vel_chassis`           | optional armors adapt | bridges `/robot_control`       |
| `rm_behavior_tree`             | rm_decision_ws         | —                                                 | `SendGoal`                           | optional armors sub   | **decision**                   |
| `fake_vel_transform`           | nav_ws pkg             | —                                                 | `/cmd_vel`→`/cmd_vel_chassis`        | —                     | —                              |
| `watch_center_attack_state.py` | scripts                | watches `cmd_vel_chassis_bt`, `robot_control`     | AMCL pose                            | —                     | watches referee inputs         |
| `bt_hotkey_debug.py`           | scripts                | —                                                 | —                                    | —                     | **mocks** `game`/`robot` state |
| `autostart_fullstack.sh`       | scripts                | starts bridge svc + sender indirectly             | runs `nav_ws/start_robot.sh`         | starts detect         | starts BT                      |


---

## 10. Minimal manual terminal set


| Terminal     | Content                                                                                             |
| ------------ | --------------------------------------------------------------------------------------------------- |
| 1            | `just sentry-bridge` (auto port)                                                                    |
| 2 (optional) | `just test detect --web --send` (Vision PTY)                                                        |
| 3            | `RADAR_PTY=/tmp/nyush-rm-sentry-radar … ./start_robot.sh` (nav_ws or sentry_planner per your setup) |


---

## 11. Easy mistakes in `communication command.txt`

- **Radar mock**: `just radar --port /tmp/nyush-rm-sentry-radar` tests the **PTY**, not “must be ACM0”.
- **Serial permissions**: `nav_ws/start_robot.sh` may still `chmod` `**/dev/ttyACM0`**; if auto-pick lands on **ACM1**, add `chmod` or udev—that is separate from bridge **selection policy**.

---



## 12. Hardware bring-up

### 12.1 Phased strategy

You do not need the full field on day one:


| Phase                         | Goal                                                                                                            | Needs environment matching map?         |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------- | --------------------------------------- |
| **A — Bench**                 | bridge, PTY, `serial_sender`, chassis responds, BT branches, `/robot_control` and `/cmd_vel_chassis_bt` present | **No**                                  |
| **B — Small area, low speed** | stable localization, short moves, `Home`-like poses in free space                                               | **Yes** (roughly matches map)           |
| **C — Full field**            | center approach/hold, low-HP home; tune Nav2 and tactics                                                        | **Yes** (field map like `**RMUL2026`**) |


Without a matching arena you can still tune comms and BT—**do not claim “full hardware Nav2 is verified”** yet. Localization chain, costmap, and `navigate_to_pose` prerequisites: [README_LIDAR.md](README_LIDAR.md) **§10.8**.

### 12.2 Safety before first motion

- Safe muzzle; disable auto fire if not needed for the test.
- First chassis tests: jack up or **limit speed**, spotter present, estop known.

### 12.3 `start_robot.sh`, bridge, sender

- `**start_robot.sh` (nav_ws or sentry_planner) does not start `sentry_bridge`** by default; run bridge in **its own terminal** or systemd.
- To push `**/cmd_vel_chassis_bt`** and `**/robot_control**` to MCU: `**START_SERIAL_SENDER=1 RADAR_PTY=<Radar PTY>**` (same as **§4**).
- On the current field stack, `**/cmd_vel_chassis_bt`** = Nav2 chassis velocity + `**RobotControl.chassis_spin_vel**` via `**bt_comm_adapter**`, then **sender → Radar PTY → MCU**; `**scan_*`, `allow_vision_control`** on `**/robot_control**` go **A3 → MCU** (wire details [README_COMMUNICATION.md](README_COMMUNICATION.md)).

### 12.4 Suggested manual terminals

Rewrite paths for your machine.


| Terminal                   | Content                                                                                                                                                                                                                |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **1 — Nav / localization** | e.g. `ros2 launch rm_nav_bringup bringup_real.launch.py world:=<map_prefix> mode:=nav …` (`world` matches `**MAP_FILE`** / map package; `lio` / `localization` per site)                                               |
| **2 — bridge**             | `cd nyush-rm-control && just sentry-bridge` (or `--port /dev/ttyACM0`); note **Vision / Radar PTY**, prefer `**/tmp/nyush-rm-sentry-radar`**                                                                           |
| **3 — sender**             | after `source /opt/ros/humble/setup.bash`, `python3 …/nyush-rm-vision/serial_sender.py --port <Radar PTY> --ros2 --topic /cmd_vel_chassis_bt`; skip if **§4** `**START_SERIAL_SENDER=1`** already starts it            |
| **4 — BT debug**           | `bash sentry_planner/scripts/run_center_attack_debug_session.sh` (keeps `**bt_comm_adapter`**, `**rm_behavior_tree**`, `**watch_center_attack_state.py**`); **requires** Nav2 and `**navigate_to_pose` action server** |
| **5 — Vision (optional)**  | start `nyush-rm-vision` sentry; `**configs/sentry.yaml` `com_port`** must be current **Vision PTY**                                                                                                                    |


### 12.5 Minimal checklist

After power, before relying on BT:

```bash
ros2 action list | grep navigate_to_pose
ros2 topic echo /robot_control --once
ros2 topic echo /cmd_vel_chassis_bt --once
```

If `**navigate_to_pose**` is missing, `**SendGoal**` will not close the loop.

### 12.6 Mock referee topics (BT branch debug)

(Requires `source rm_decision_ws/install/setup.bash`.)

**In match + healthy HP → expect watcher near `APPROACH_CENTER`, `/cmd_vel_chassis_bt` active:**

```bash
ros2 topic pub -r 1 /game_status rm_decision_interfaces/msg/GameStatus \
  "{game_progress: 4, stage_remain_time: 220}"
ros2 topic pub -r 10 /robot_status rm_decision_interfaces/msg/RobotStatus \
  "{robot_id: 7, current_hp: 600, shooter_heat: 0, team_color: false, is_attacked: false}"
```

**Low HP → expect `HOME_RECOVER`, return `Home`:**

```bash
ros2 topic pub -r 10 /robot_status rm_decision_interfaces/msg/RobotStatus \
  "{robot_id: 7, current_hp: 200, shooter_heat: 0, team_color: false, is_attacked: false}"
```

**Pre-match → expect `HOME_STANDBY`, no rush to center:**

```bash
ros2 topic pub -r 1 /game_status rm_decision_interfaces/msg/GameStatus \
  "{game_progress: 0, stage_remain_time: 220}"
```

If `**serial_sender**` still publishes real referee, these **fight the same topics**; use `**SERIAL_SENDER_DISABLE_STATUS_PUB=1`** (**§5**).

### 12.7 When you are ready for the full field

At minimum: **stable bridge/sender**, **stable localization**, `**navigate_to_pose` OK**, `**APPROACH_CENTER` / `HOME_RECOVER` / `HOME_STANDBY` switch correctly**, `**Home` / center poses are free space** on the loaded map (remap: **§4.4**, **§7.4**).

### 12.8 Common pitfalls

- **PTY numbers change** after each bridge restart; do not keep stale `**/dev/pts/N`**; see [README_COMMUNICATION.md](README_COMMUNICATION.md) **§15.2**.
- `**watch_center_attack_state.py` defaults for `--home-x/y`, `--center-x/y` may not match XML `SendGoal`**; align args with the tree ([README_BEHAVIOR_TREE_FLOW.md](README_BEHAVIOR_TREE_FLOW.md) **§5.1**).

---



## 13. Which README should I open?


| Question                                                                            | Open first                                                                                                 |
| ----------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| Who owns serial, what is PTY, 19-byte / A3 / SP, where topics come from             | [README_COMMUNICATION.md](README_COMMUNICATION.md)                                                         |
| Which XML runs, `SendGoal`/`RobotControl`, Groot2, hotkeys                          | [README_BEHAVIOR_TREE_FLOW.md](README_BEHAVIOR_TREE_FLOW.md)                                               |
| **Gazebo RMUL2026, Sim2Real, Groot AppImage, `bringup_sim`**                        | [README_LIDAR.md §6.4](README_LIDAR.md#nyush-gazebo-sim2real) + [mid360 command.txt](mid360%20command.txt) |
| Mid360, FAST-LIO, Nav2 tuning, clouds, costmap, TF                                  | [README_LIDAR.md](README_LIDAR.md)                                                                         |
| One-liner commands, `MAP_FILE`, mapping, `start_robot` env, hardware terminal order | **This file** (§1, §4, §7, §12)                                                                            |
| Still unsure                                                                        | [README.md](README.md) central index                                                                       |


---

To embed a command in systemd or change `MAP_FILE` / BT goals inside `autostart_fullstack.sh`, edit the env block in that script directly.