# RoboMaster sentry autonomous navigation (LiDAR + Nav2)

[![ROS2 Humble](https://img.shields.io/badge/ROS2-Humble-blue)](https://docs.ros.org/en/humble/)
[![Ubuntu 22.04](https://img.shields.io/badge/Ubuntu-22.04-orange)](https://ubuntu.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

> **LiDAR SLAM + Nav2 autonomous navigation for the RoboMaster sentry platform.**  
> **NYUSH add-ons (§0, §6.4 Sim2Real / Gazebo / Groot2, §10.8):** 2026-04-11

---

## 0. How the five READMEs split work

| Document | Role |
|------|------|
| [README.md](README.md) | **Central index**: overview, diagram, build order, shortest startup |
| [README_COMMUNICATION.md](README_COMMUNICATION.md) | **Comms and protocol**: `sentry_bridge`, PTY, `serial_sender`, `bt_comm_adapter`, frames |
| [README_BEHAVIOR_TREE_FLOW.md](README_BEHAVIOR_TREE_FLOW.md) | **Behavior trees**: XML, `SendGoal` / `RobotControl`, debug scripts |
| **This file** | **LiDAR + SLAM + Nav2**: Mid360, FAST-LIO, `my_nav2_params`, **§6.4 Gazebo (Sim2Real first step)**, hardware launch, TF, mapping, troubleshooting; [**§10.8 hardware navigation prerequisites**](#108-nyush-hardware-navigation-prerequisites) |
| [README_COMMANDS.md](README_COMMANDS.md) | **Commands and data flow**: **§7** mapping (`rotate_pcd` / `pcd2pgm` / `map_saver_cli`), **§4.4** map files, **§12** hardware bring-up |

**How to choose:** **Gazebo, RMUL2026, `bringup_sim`, Sim2Real** → **§6.4 here** + [mid360 command.txt](mid360%20command.txt); LiDAR offline, point clouds, FAST-LIO, Nav2 tuning, costmap, TF → **rest of this file**; **shell and `MAP_FILE`** → [README_COMMANDS.md](README_COMMANDS.md) **§7, §4.4**; **behavior tree / Groot2** → [README_BEHAVIOR_TREE_FLOW.md](README_BEHAVIOR_TREE_FLOW.md); **serial and PTY** → [README_COMMUNICATION.md](README_COMMUNICATION.md).

**Boundaries:** **§1–§9** keep the original Polar Bear stack generic notes in English; **NYUSH hardware closed loop** starts at **§10.8**, aligned with [README_COMMANDS.md §12](README_COMMANDS.md#readme-commands-section-12). One-shot **`sentry_planner/start_robot.sh`** brings up Mid360, FAST-LIO, `pointcloud_to_laserscan`, Nav2, etc.; **MCU serial** still only via **bridge + `serial_sender`** (see comms doc).

### NYUSH: recommended Sim2Real (simulation → hardware)

Default workflow: **tune parameters and `center_attack_simple` (approach center / hold / home) in Gazebo RMUL2026 + Nav2, then switch to Mid360 + FAST-LIO on the robot.**

| Phase | Where to read |
|------|--------|
| **Single Gazebo launch, `run_center_attack_debug_session`, mock `/game_status`, step-by-step pubs** | Root **[mid360 command.txt](mid360%20command.txt)** (copy-paste) |
| **Launch parameters vs hardware** | **§6.4** here; longer package notes [rm_navigation_ws/README.md](rm_navigation_ws/README.md) |
| **Behavior tree + Groot2 port, `Project.btproj`** | [README_BEHAVIOR_TREE_FLOW.md](README_BEHAVIOR_TREE_FLOW.md) **§18.1** |
| **Hardware terminals, bridge, PTY** | [README_COMMUNICATION.md](README_COMMUNICATION.md), [README_COMMANDS.md §12](README_COMMANDS.md#readme-commands-section-12) |

---

## Table of contents

| Section | Topic |
|---------|------|
| [1. Project overview](#1-project-overview) | Goals and results |
| [2. System architecture](#2-system-architecture) | Diagrams, TF, data flow |
| [3. Hardware configuration](#3-hardware-configuration) | Compute, LiDAR, chassis |
| [4. Software stack](#4-software-stack) | ROS packages and topics |
| [5. Installation guide](#5-installation-guide) | Prerequisites and build |
| [6. Quick start](#6-quick-start) | Launch and mapping (includes **§6.4** NYUSH Gazebo) |
| [7. Configuration](#7-configuration) | Nav2 / FAST-LIO / network |
| [8. Performance metrics](#8-performance-metrics) | Resources and latency |
| [9. Troubleshooting](#9-troubleshooting) | Common failures |
| [10. Development notes](#10-development-notes) | Field notes (includes **§10.8**) |
| [10.8 NYUSH hardware navigation prerequisites](#108-nyush-hardware-navigation-prerequisites) | `map→odom→base_link`, `navigate_to_pose`, map vs arena |
| [11. Future plans](#11-future-plans) | Roadmap |
| [12. References](#12-references) | Links |

---

## 1. Project overview

### 1.1 Introduction

This project implements a complete autonomous navigation system for the RoboMaster sentry robot. It integrates LiDAR SLAM for real-time localization and mapping with Nav2 for path planning and obstacle avoidance.

### 1.2 Key features

| Feature | Description |
|---------|-------------|
| **SLAM** | Real-time 3D LiDAR odometry with FastLIO2 / Point-LIO |
| **Mapping** | 3D PCD to 2D PGM map conversion |
| **Navigation** | Nav2 global/local planning with DWB controller |
| **Obstacle avoidance** | Real-time static and dynamic obstacle handling |
| **Chassis control** | Serial link to STM32 C-board |

### 1.3 Performance achieved

**Indoor navigation (5×5 m area):**

| Metric | Value |
|--------|-------|
| Cruise speed | 0.2–0.26 m/s |
| Obstacle clearance | ≥ 0.3 m |
| Position error | ≤ 0.2 m |
| Success rate | ≥ 90% (20 trials) |
| Collision-free | Yes (5+ consecutive runs) |

---

## 2. System architecture

### 2.1 System diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    SENTRY NAVIGATION SYSTEM                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────────────┐   │
│  │   LiDAR      │───▶│  SLAM Node   │───▶│   /Odometry              │   │
│  │ Mid-360/L2   │    │ FastLIO/PLIO │    │   /cloud_registered      │   │
│  └──────────────┘    └──────────────┘    └──────────────────────────┘   │
│         │                   │                        │                   │
│         ▼                   ▼                        ▼                   │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────────────┐   │
│  │  IMU Data    │    │   TF Tree    │    │  pointcloud_to_laserscan │   │
│  │  200 Hz      │    │  Transforms  │    │     /scan (10 Hz)        │   │
│  └──────────────┘    └──────────────┘    └──────────────────────────┘   │
│                             │                        │                   │
│                             ▼                        ▼                   │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                         NAV2 STACK                               │    │
│  │  ┌───────────┐  ┌─────────────┐  ┌───────────┐  ┌───────────┐   │    │
│  │  │  AMCL     │  │   Planner   │  │Controller │  │ Costmap2D │   │    │
│  │  │Localization│  │  NavFn/A*  │  │   DWB     │  │  Layers   │   │    │
│  │  └───────────┘  └─────────────┘  └───────────┘  └───────────┘   │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                    │                                     │
│                                    ▼                                     │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                    /cmd_vel (20 Hz)                              │    │
│  │              Twist: linear.x, linear.y, angular.z                │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                    │                                     │
│                                    ▼                                     │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                    serial_sender.py                               │   │
│  │     ROS2 → UART (115200 baud) → STM32 C-Board → Chassis          │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.2 TF tree structure

```
                    map
                     │
                     ▼
                   odom ─────────────────────────┐
                     │                            │
                     ▼                            │ (static: 0,0,0)
               camera_init                        │
                     │                            │
                     ▼                            │
            body / aft_mapped                     │
                     │                            │
                     ▼                            │
               base_link ◀───────────────────────┘
                     │         (static: pitch -50°)
                     ▼
              base_footprint
```

### 2.3 Data flow

```
LiDAR (10Hz) ──▶ SLAM ──▶ /cloud_registered ──▶ /scan ──▶ Nav2 ──▶ /cmd_vel ──▶ Chassis
                  │
                  ▼
              /Odometry (10Hz)
                  │
                  ▼
          TF: odom → base_link
```

---

## 3. Hardware configuration

### 3.1 Computing platform

| Component | NUC 12 Pro (primary) | Jetson Orin Nano (backup) |
|-----------|---------------------|---------------------------|
| CPU | Intel i7-1260P (16 threads) | ARM Cortex-A78AE (6 cores) |
| RAM | 16 GB DDR4 | 8 GB LPDDR5 |
| Storage | 512 GB NVMe SSD | 128 GB eMMC |
| OS | Ubuntu 22.04 LTS | Ubuntu 22.04 (JetPack 6) |
| Power | 19V DC | 9-20V DC |
| Suitability | Full stack (recommended) | Edge compute, mapping only |

### 3.2 LiDAR sensors

| Specification | Livox Mid-360 ✅ | Unitree L2 ⚠️ |
|---------------|------------------|---------------|
| Role | **Primary LiDAR** | **Experimental** |
| FOV | 360° × 59° | 360° × 90° |
| Range | 40 m | 30 m |
| Points/sec | 200,000 | 43,200 |
| IMU | Built-in (stable) | Built-in (noisy on gimbal) |
| Interface | Ethernet (UDP) | USB Serial (ttyACM0) |
| Data Format | CustomMsg (offset_time) | PointCloud2 |
| Time Sync | ✅ Excellent | ⚠️ Weak |
| Tilted Mount | ✅ Supported | ⚠️ IMU drift issue |
| Status | **Production Ready** | **Experimental** |

**Mid-360 network configuration:**
- LiDAR IP: `192.168.1.182`
- Host IP: `192.168.1.2`
- UDP Ports: 56101-56501

### 3.3 Chassis controller

| Item | Specification |
|------|---------------|
| Controller | STM32 C-board (RoboMaster) |
| Interface | UART via USB |
| Baud rate | 115200 |
| Protocol | Binary (15 bytes) |
| Frame format | `0xA5 0x5A [vx:4B] [vy:4B] [wz:4B] [CRC8]` |
| Port | `/dev/ttyACM0` |

### 3.4 Remote access

| Service | Port | Address | Use |
|---------|------|---------|------|
| SSH | 9913 | 42.192.208.124:9913 | Terminal access |
| VNC | 9914 | 42.192.208.124:9914 | Desktop view |

```bash
# SSH
ssh nyu@42.192.208.124 -p 9913

# VNC viewer
VNC Viewer → 42.192.208.124:9914
```

---

## 4. Software stack

### 4.1 Core dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| ROS 2 | Humble | Middleware |
| Nav2 | Humble | Navigation stack |
| FastLIO2 | Latest | SLAM (Mid-360) |
| Point-LIO | ROS 2 fork | SLAM (Unitree L2) |
| livox_ros_driver2 | 1.1.2 | Mid-360 driver |
| unitree_lidar_ros2 | Latest | Unitree L2 driver |
| pcd2pgm | Latest | Map conversion |
| pointcloud_to_laserscan | Latest | 3D to 2D scan |

### 4.2 Workspace layout

```
~/nav_ws/
├── src/
│   ├── FAST_LIO/                # FastLIO2 SLAM
│   │   ├── config/mid360.yaml   # LiDAR config
│   │   └── PCD/scans.pcd        # Saved point cloud
│   ├── point_lio_ros2/          # Point-LIO SLAM
│   │   └── config/unilidar_l2.yaml
│   ├── livox_ros_driver2/       # Mid-360 driver
│   │   └── config/MID360_config.json
│   ├── unitree_lidar_ros2/      # Unitree L2 driver
│   ├── pcd2pgm/                 # PCD → PGM converter
│   └── pointcloud_to_laserscan/ # 3D → 2D converter
├── install/                     # Compiled packages
├── my_nav2_params.yaml          # Nav2 parameters (production)
├── my_nav2_params_test.yaml     # Nav2 parameters (testing)
├── start_robot.sh               # One-click launch script
└── serial_sender.py             # Chassis control bridge
```

### 4.3 Key ROS 2 topics

| Topic | Type | Frequency | Description |
|-------|------|-----------|-------------|
| `/livox/lidar` | CustomMsg | 10 Hz | Raw point cloud |
| `/livox/imu` | Imu | 200 Hz | IMU data |
| `/Odometry` | Odometry | 10 Hz | Pose from SLAM |
| `/cloud_registered` | PointCloud2 | 10 Hz | Registered cloud |
| `/scan` | LaserScan | 10 Hz | 2D laser scan |
| `/cmd_vel` | Twist | 20 Hz | Velocity commands |
| `/map` | OccupancyGrid | Static | Navigation map |

---

## 5. Installation guide

### 5.1 Prerequisites

```bash
# Install ROS 2 Humble (if not installed)
sudo apt update && sudo apt install -y ros-humble-desktop

# Install Nav2
sudo apt install -y ros-humble-navigation2 ros-humble-nav2-bringup

# Other dependencies
sudo apt install -y \
  ros-humble-pcl-ros \
  ros-humble-tf2-tools \
  ros-humble-pointcloud-to-laserscan \
  python3-serial \
  libpcl-dev
```

### 5.2 Clone and build

```bash
# Create workspace
mkdir -p ~/nav_ws/src && cd ~/nav_ws/src

# Clone repositories
git clone https://github.com/Livox-SDK/livox_ros_driver2.git
git clone https://github.com/hku-mars/FAST_LIO.git
git clone https://github.com/LihanChen2004/pcd2pgm.git

# Build
cd ~/nav_ws
source /opt/ros/humble/setup.bash
colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release
source install/setup.bash
```

### 5.3 Network setup (Mid-360)

```bash
# Set static IP
sudo nmcli con mod "Wired connection 1" ipv4.addresses 192.168.1.2/24
sudo nmcli con mod "Wired connection 1" ipv4.method manual
sudo nmcli con up "Wired connection 1"

# Disable firewall
sudo ufw disable

# Increase UDP buffer
sudo sysctl -w net.core.rmem_max=26214400
sudo sysctl -w net.core.rmem_default=26214400
```

---

## 6. Quick start

### 6.1 One-click launch (recommended)

```bash
cd ~/nav_ws
./start_robot.sh
```

This script automatically:

1. Sources workspaces
2. Launches LiDAR driver
3. Starts SLAM
4. Publishes TF
5. Converts point cloud to `LaserScan`
6. Launches Nav2
7. Opens RViz2

### 6.2 Manual launch steps

**Step 1: LiDAR driver**
```bash
cd ~/nav_ws && source install/setup.bash
ros2 launch livox_ros_driver2 msg_MID360_launch.py
```

**Step 2: SLAM**
```bash
export LD_PRELOAD=/lib/x86_64-linux-gnu/libusb-1.0.so.0
ros2 launch fast_lio mapping.launch.py config_file:=mid360.yaml
```

**Step 3: TF transforms**
```bash
ros2 run tf2_ros static_transform_publisher 0 0 0 0 0 0 odom camera_init &
ros2 run tf2_ros static_transform_publisher 0 0 0 0 -0.873 0 body base_link &
ros2 run tf2_ros static_transform_publisher 0 0 0 0 0 0 base_link base_footprint &
```

**Step 4: Point cloud to LaserScan**
```bash
ros2 run pointcloud_to_laserscan pointcloud_to_laserscan_node --ros-args \
  -p target_frame:=base_link \
  -p min_height:=-0.4 -p max_height:=1.0 \
  -p range_min:=0.1 -p range_max:=20.0 \
  -r cloud_in:=/cloud_registered -r scan:=/scan &
```

**Step 5: Nav2**
```bash
ros2 launch nav2_bringup bringup_launch.py \
    use_sim_time:=False \
    map:=/home/nyu/Desktop/map/my_map.yaml \
    params_file:=/home/nyu/nav_ws/my_nav2_params.yaml &
```

**Step 6: Chassis control**
```bash
sudo chmod 777 /dev/ttyACM0
python3 serial_sender.py --port /dev/ttyACM0 --ros2
```

### 6.3 Creating a map

```bash
# 1. Run SLAM to collect point cloud
ros2 launch fast_lio mapping.launch.py config_file:=mid360.yaml

# 2. Save point cloud (automatic when stopping)
# Location: ~/nav_ws/src/FAST_LIO/PCD/scans.pcd

# 3. Rotate if tilted mount (optional)
python3 rotate_pcd.py

# 4. Convert 3D PCD to 2D PGM
ros2 launch pcd2pgm pcd2pgm_launch.py

# 5. Save map
ros2 run nav2_map_server map_saver_cli -f /home/nyu/Desktop/map/my_map
```

<a id="nyush-gazebo-sim2real"></a>

### 6.4 NYUSH Gazebo simulation (RMUL2026 + Nav2, Sim2Real first step)

**Environment:** ROS 2 Humble, **Gazebo Classic 11** (same as [README.md](README.md)). Simulation uses **Gazebo odometry + AMCL**; no physical Mid360 required—use this to stabilize **Nav2 costmaps, velocities, `SendGoal`**, and behavior-tree branches before hardware.

**Terminal 1 — world + Nav2 + RViz:**

```bash
cd /path/to/sentry_planner/rm_navigation_ws
source ~/nav_ws/install/setup.bash    # or your nav workspace
source install/setup.bash
ros2 launch rm_nav_bringup bringup_sim.launch.py \
  world:=RMUL2026 \
  mode:=nav \
  localization:=amcl \
  use_gazebo_odom:=true \
  nav_rviz:=True
```

**Terminal 2 — long-running BT debug (keeps `bt_comm_adapter` + `rm_behavior_tree` + `watch_center_attack_state.py`):**

```bash
bash /path/to/sentry_planner/scripts/run_center_attack_debug_session.sh
```

Script defaults **`USE_SIM_TIME=True`** to match Gazebo. For **Groot2 remote monitor**, launch with **`enable_groot:=true`** (port **1667** by default; see [README_BEHAVIOR_TREE_FLOW.md §18.1](README_BEHAVIOR_TREE_FLOW.md#181-groot2-workflow)).

**Terminal 3 — mock referee, test center / hold / home:** copy **`ros2 topic pub` examples from [mid360 command.txt](mid360%20command.txt) §4–§8**; expected watcher states (`APPROACH_CENTER`, `CENTER_HOLD_ATTACK`, `HOME_RECOVER`, etc.) are documented there.

**Simulation vs hardware:**

| Aspect | Gazebo (this section) | Hardware (see §10.8, [README_COMMANDS.md §12](README_COMMANDS.md#readme-commands-section-12)) |
|------|------------------|------------------------------------------------------------------------|
| Localization | `use_gazebo_odom:=true` + **AMCL** | FAST-LIO / `bringup_real`, etc. |
| Time | **`use_sim_time`** | Usually `use_sim_time:=false` |
| Velocities to MCU | Often ROS-only debug; to exercise **Radar PTY + sender** | **bridge + `serial_sender`** |

**Optional — Groot2 GUI (same as mid360 command.txt §13):**

```bash
cd ~/Desktop
./Groot2-v1.9.0-x86_64.AppImage
```

In Groot2 open **`rm_decision_ws/rm_behavior_tree/config/Project.btproj`**, Monitor to **`127.0.0.1:1667`** (or your `groot_port`). **AppImage filename** varies with download—use the file on your `~/Desktop`.

More sim maps, Docker, and history: **[rm_navigation_ws/README.md](rm_navigation_ws/README.md)**.

---

## 7. Configuration

### 7.1 Nav2 parameters

Path: `~/nav_ws/my_nav2_params.yaml`

| Parameter | Value | Description |
|-----------|-------|-------------|
| `max_vel_x` | 0.26 m/s | Max forward speed |
| `max_vel_y` | 0.26 m/s | Max lateral speed |
| `max_vel_theta` | 0.0 rad/s | Rotation disabled |
| `acc_lim_x/y` | 2.5 m/s² | Acceleration limit |
| `min_speed_xy` | 0.05 m/s | Min speed (deadband) |
| `controller_frequency` | 10.0 Hz | Control loop rate |

### 7.2 FastLIO parameters

Path: `~/nav_ws/src/FAST_LIO/config/mid360.yaml`

```yaml
lidar_type: 2          # 2 = Livox CustomMsg
scan_line: 4           # Number of scan lines
scan_rate: 10          # Hz
point_filter_num: 3    # Point decimation factor
```

### 7.3 Mid-360 network config

Path: `~/nav_ws/src/livox_ros_driver2/config/MID360_config.json`

```json
{
  "host_net_info": {
    "cmd_data_ip": "192.168.1.2",
    "point_data_ip": "192.168.1.2",
    "imu_data_ip": "192.168.1.2"
  },
  "lidar_configs": [{
    "ip": "192.168.1.182"
  }]
}
```

---

## 8. Performance metrics

### 8.1 System resource usage

**Platform: NUC 12 Pro (i7-1260P, 16 GB RAM)**

| Metric | Value |
|--------|-------|
| CPU peak | ~40% |
| CPU average | ~36% |
| Memory | ~6.3 GB |
| Network RX | ~3.15 MB/s |

### 8.2 Topic frequencies

| Topic | Measured | Expected | Status |
|-------|----------|----------|--------|
| `/livox/lidar` | 10 Hz | 10 Hz | ✅ |
| `/livox/imu` | 200 Hz | 200 Hz | ✅ |
| `/Odometry` | 10 Hz | 10-100 Hz | ⚠️ |
| `/scan` | 7-9 Hz | 10 Hz | ⚠️ |
| `/cmd_vel` | 20 Hz | 20 Hz | ✅ |

### 8.3 Latency measurements

| Pipeline | Latency | Target | Status |
|----------|---------|--------|--------|
| `/cmd_vel` → Serial | 0.34 ms (median) | < 1 ms | ✅ |
| Point cloud → LaserScan | 15 ms/frame | < 5 ms | ⚠️ |
| End-to-end control | ~20 ms | < 50 ms | ✅ |

### 8.4 Performance benchmarks

| Metric | Good | Acceptable | Needs work |
|--------|------|------------|------------|
| Control latency | < 1 ms | 1–5 ms | > 5 ms |
| Cloud to scan | < 5 ms | 5–20 ms | > 20 ms |
| Frame drop rate | < 5% | 5–20% | > 20% |
| CPU peak | < 50% | 50–80% | > 80% |

### 8.5 Debugging commands

```bash
# Monitor topic frequencies
ros2 topic hz /scan /Odometry /cmd_vel

# Measure latency
python3 measure_pointcloud_latency.py --cloud /cloud_registered --scan /scan --duration 30

# System resources
./monitor_resources.sh --interval 1 --duration 60

# TF tree
ros2 run tf2_tools view_frames
```

---

## 9. Troubleshooting

### 9.1 Common issues

#### Issue 1: No LiDAR data

**Symptoms:** no data on Livox topics

```bash
# Check network
ping 192.168.1.182

# Check topics
ros2 topic list | grep livox

# Disable firewall
sudo ufw disable
```

#### Issue 2: TF transform errors

**Symptoms:** `Transform from map to base_link failed`

```bash
# View TF tree
ros2 run tf2_tools view_frames

# Check specific transform
ros2 run tf2_ros tf2_echo map base_link
```

#### Issue 3: AMCL message filter dropping

**Symptoms:** `Message Filter dropping message`

**Mitigations:**

- Increase `queue_size` in AMCL config
- Increase `transform_tolerance`
- Reduce `/scan` frequency
- Check system time sync

#### Issue 4: Serial port failed

**Symptoms:** `Failed to open serial port`

```bash
sudo chmod 777 /dev/ttyACM0
lsof /dev/ttyACM0
python3 serial_sender.py --port /dev/ttyACM0 --vx 0.1 --duration 1.0
```

#### Issue 5: Localization loss on gimbal rotation

**Causes:**

- IMU saturation
- Extrinsic calibration error
- Time synchronization drift

**Mitigations:**

- Reduce gimbal rotation speed
- Use higher-range IMU
- Recalibrate extrinsics
- Preheat IMU, calibrate bias

---

## 10. Development notes

> Field notes from bring-up and tuning.

### 10.1 LiDAR selection summary

| Aspect | Mid-360 | Unitree L2 |
|--------|---------|------------|
| Time sync | ✅ CustomMsg with offset_time | ⚠️ Standard PointCloud2 |
| IMU stability | ✅ Stable | ⚠️ Noisy on gimbal |
| Tilted mount | ✅ Works with TF rotation | ⚠️ IMU drift issues |
| Production ready | ✅ Yes | ⚠️ Experimental |

**Conclusion:** Mid-360 wins on time sync and IMU stability; **it is the primary LiDAR**. Unitree L2 remains experimental until further study.

---

### 10.2 Unitree L2 LiDAR notes

#### 10.2.1 Connection types

**Config:** `unilidar_sdk2/unitree_lidar_ros2/launch/launch.py`

| Type | Configuration | Notes |
|------|---------------|----------|
| **USB serial** | `serial_port: '/dev/ttyACM0'`, `initialize_type: 2` | Direct USB |
| **Ethernet UDP** | `lidar_ip: '10.10.10.10'`, `initialize_type: 1` | Needs static IP |

```bash
ls /dev/ttyACM*
```

#### 10.2.2 Known issues

1. **Dynamic balance and IMU:** Unitree units can show balance and IMU issues; clouds may spin or diverge at init; official docs suggest raising `cloud_scan_num` toward 72 with limited benefit—needs more tuning.
2. **IMU acceleration spikes:** expect ~9.8 m/s² (`acc_norm: 10.2`); sudden spikes can blow up the cloud; gimbal or wall contact can jump toward ~14 m/s²—main blocker for tilted installs.
3. **Cloud spinning:** insufficient balance; raising `cloud_scan_num` helps only a little.

#### 10.2.3 Debug commands

```bash
# Official serial example when cloud disappears or driver fails
cd ~/nav_ws/src/unilidar_sdk2/unitree_lidar_sdk/build
sudo chmod 777 /dev/ttyACM0
../bin/example_lidar_serial
```

---

### 10.3 Point-LIO configuration

**Why Point-LIO?** Unitree lidars fit poorly with many odometry stacks; [dfloreaa/point_lio_ros2](https://github.com/dfloreaa/point_lio_ros2) adapts for them. Performance is broadly similar to FastLIO2.

**Config:** `~/nav_ws/src/point_lio_ros2/config/unilidar.yaml`

| Parameter | Value | Description |
|-----------|-------|-------------|
| `start_in_aggressive_motion` | `true` | Use preset gravity to avoid IMU divergence |
| `gravity_init` | `[0.0, 0.0, -9.810]` | Preset gravity |
| `extrinsic_est_en` | `false` | Off for aggressive motion |
| `acc_norm` | `10.2` | Expected linear accel from `ros2 topic echo /unilidar/imu` (m/s²) |
| `b_acc_cov` / `b_gyr_cov` | `0.0001` | Bias covariance |
| `imu_meas_acc_cov` | `0.1` | Accel measurement noise |
| `imu_meas_omg_cov` | `0.1` | Gyro measurement noise |

**Extrinsic rotation warning:**

```yaml
# Often suggested online for tilted installs—not recommended here
extrinsic_T: [0.007698, 0.014655, -0.00667]
extrinsic_R: [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
# Rotating the cloud this way misaligns IMU vs gravity when moving
```

**Launch tuning:** `~/nav_ws/src/point_lio_ros2/launch/mapping_unilidar_l2.launch.py`

| Parameter | NUC | Jetson | Description |
|-----------|-----|--------|-------------|
| `point_filter_num` | 3 | 1 | Point decimation |
| `filter_size_surf` | 0.5 | 0.3 | Surface filter size |
| `filter_size_map` | 0.5 | 0.3 | Map filter size |

> Match CPU headroom to avoid timestamp issues and “queue is full”. Defaults are fine on NUC; lower on Jetson.

---

### 10.4 Mid-360 configuration

**Config:** `~/nav_ws/src/livox_ros_driver2/config/MID360_config.json`

```json
{
  "host_net_info": {
    "cmd_data_ip": "192.168.1.2",
    "cmd_data_port": 56101,
    "push_msg_ip": "192.168.1.2",
    "push_msg_port": 56201,
    "point_data_ip": "192.168.1.2",
    "point_data_port": 56301,
    "imu_data_ip": "192.168.1.2",
    "imu_data_port": 56401,
    "log_data_ip": "",
    "log_data_port": 56501
  },
  "lidar_configs": [{
    "ip": "192.168.1.182",
    "pcl_data_type": 0,
    "pattern_mode": 0,
    "extrinsic_parameter": {
      "roll": 0.0, "pitch": 0.0, "yaw": 0.0,
      "x": 0, "y": 0, "z": 0
    }
  }]
}
```

> Mid-360 is Ethernet-only in this stack—tune both host and lidar JSON for your network.

**Launch:** `~/nav_ws/src/livox_ros_driver2/launch_ROS2/msg_MID360_launch.py`

```python
xfer_format = 1   # 0 PointCloud2 (PointXYZRTL), 1 Livox CustomMsg
```

> Prefer **`xfer_format = 1` (CustomMsg)** for `offset_time` and better time sync. PointCloud2 mode can run FastLIO but often triggers missing-parameter warnings from the Livox launch—CustomMsg is the supported path.

---

### 10.5 Tilted LiDAR mount

Many teams tilt the lidar on the gimbal for coverage; that tilts `camera_init` clouds and hurts mapping unless corrected.

**Mitigation:**

| Step | Action |
|------|--------|
| 1 | Static TF `body` → `base_link` pitch −50° |
| 2 | Run `rotate_pcd.py` on saved PCD before `pcd2pgm` |
| 3 | Avoid extrinsic rotation hacks inside Point-LIO for this case |

```bash
ros2 run tf2_ros static_transform_publisher 0 0 0 0 -0.873 0 body base_link
# -0.873 rad ≈ -50°
python3 rotate_pcd.py
```

> Keeps Nav2 maps upright and scans consistent.

---

### 10.6 Mapping workflow

With `PCD_save=True`, FastLIO / Point-LIO writes `scans.pcd` after runs. Use [pcd2pgm](https://github.com/LihanChen2004/pcd2pgm) for Nav2-ready PGMs.

```bash
ros2 launch fast_lio mapping.launch.py config_file:=mid360.yaml
cd ~/nav_ws/src/FAST_LIO/PCD/
pcl_viewer scans.pcd
python3 rotate_pcd.py
ros2 launch pcd2pgm pcd2pgm_launch.py
cd ~/Desktop/map
ros2 run nav2_map_server map_saver_cli -f my_map
```

More commands: [mid360 command.txt](mid360%20command.txt)

---

### 10.7 Navigation status (lab)

Nav2 parameters live in `my_nav2_params.yaml`. Observed indoors (5×5 m):

- Map A → goal B with one static obstacle, dynamic avoidance on, clearance ≥ 0.3 m, cruise ~0.2 m/s, end error ≤ 0.2 m, collision-free streaks.
- Dynamic avoidance trials: clearance ≥ 0.5 m, cruise 0.26 m/s, five consecutive collision-free runs, ≥90% success over 20 tries.

> This section reflects milestone testing; update as the stack evolves.

---

<a id="108-nyush-hardware-navigation-prerequisites"></a>

### 10.8 NYUSH hardware navigation prerequisites

Unlike **“comms only”**, a **closed navigation loop** needs the **arena to match the loaded 2D map** (field **`RMUL2026`**, lab **`11_map`**, etc.—see [README_COMMANDS.md](README_COMMANDS.md) **§4.4** for swaps). **Recommended:** prove `navigate_to_pose` and BT branches in **§6.4 Gazebo** on **`RMUL2026`**, then execute this hardware checklist.

**Stable chain:**

- **`map` → `odom` → `base_link`** with sane lidar inputs and localization (no wild jumps).

**Minimum on the robot:**

- **`navigate_to_pose` action server online** (otherwise BT **`SendGoal`** cannot close); check `ros2 action list | grep navigate_to_pose` (full steps [README_COMMANDS.md §12](README_COMMANDS.md#readme-commands-section-12)).
- **RViz** pose roughly matches the map; local **costmap** is not ballooning pathologically.
- **`Home` / center hold poses** sit in **free space** on the occupancy grid; origin/orientation mismatches often look like “Nav2 is broken” when the map is wrong.

**Phasing:** bench → small mapped area → full field for center/hold/home. Without a matching field, do not claim **hardware Nav2 is fully validated**.

**Cross-links:** when BT publishes goals → [README_BEHAVIOR_TREE_FLOW.md](README_BEHAVIOR_TREE_FLOW.md); serial / bridge / referee → [README_COMMUNICATION.md](README_COMMUNICATION.md); which README to open → [README_COMMANDS.md §13](README_COMMANDS.md#readme-commands-section-13).

---

## 11. Future plans

- [ ] Automatic initialization for Unitree L2
- [ ] IMU calibration procedure
- [ ] Dynamic obstacle avoidance improvements
- [ ] Battery monitoring via ROS
- [ ] Multi-floor navigation
- [ ] Web-based monitoring dashboard
- [ ] Automatic recovery behaviors
- [ ] Further LiDAR evaluation for radar-station layouts

---

## 12. References

### Official documentation
- [Livox Mid-360 Manual](https://www.livoxtech.com/mid-360/downloads)
- [FAST-LIO GitHub](https://github.com/hku-mars/FAST_LIO)
- [Nav2 Documentation](https://docs.nav2.org/)
- [ROS 2 Humble Documentation](https://docs.ros.org/en/humble/)

### Related projects
- [Sentry Chassis Control](https://github.com/NYUSH-Robotics-Club/robomaster-control/tree/alan_sentry_radar)
- [Livox ROS Driver 2](https://github.com/Livox-SDK/livox_ros_driver2)
- [Point-LIO](https://github.com/hku-mars/Point-LIO)
- [Point-LIO ROS2 (Unitree adapted)](https://github.com/dfloreaa/point_lio_ros2)
- [pcd2pgm](https://github.com/LihanChen2004/pcd2pgm)

### Useful tools

- **pcl_viewer:** point cloud visualization
- **foxglove:** advanced ROS 2 visualization
- **plotjuggler:** real-time plotting

---

## Contributing

If you find bugs or have suggestions:

1. Open an issue in the repository
2. Fork and open a pull request
3. Contact: Yanheng Zhu (yz11502@nyu.edu)

---

## License

This project integrates multiple open-source components:

- **FAST-LIO:** HKU Mars Lab (GPLv2)
- **Nav2:** ROS 2 Navigation Team (Apache 2.0)
- **Livox SDK:** Livox Technology
- **Unitree SDK:** Unitree Robotics

**Thanks**

- NYU Shanghai Robotics Club
- All contributors and testers

---

**Last updated:** January 2025  
**Maintained by:** Yanheng Zhu  
**Contact:** yz11502@nyu.edu
