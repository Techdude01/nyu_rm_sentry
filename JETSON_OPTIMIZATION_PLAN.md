# Jetson-Oriented Navigation Stack Optimization Plan (No AMCL)

Goal: keep the real-robot behavior stable while reducing memory and CPU usage so NVIDIA Jetson can run FAST-LIO + Nav2 + vision inference with margin.  
Current default assumption: localization uses `LOCALIZATION_MODE=icp` and no AMCL enablement.

## 0) Baseline and constraints

- Confirm baseline launch path
  - `start_robot.sh` launches:
    - FAST-LIO (`ros2 launch fast_lio mapping.launch.py config_file:=mid360.yaml`)
    - `pointcloud_to_laserscan` on `/cloud_registered -> /scan`
    - Nav2 bringup (`map_server_launch.py` for ICP mode or `bringup_launch.py` otherwise)
    - ICP registration when `LOCALIZATION_MODE=icp`
  - Fast-LIO publish section in `rm_navigation_ws/src/rm_nav_bringup/config/reality/fastlio_mid360_real.yaml` currently has:
    - `map_en: true`
    - `scan_publish_en: true`
    - `pcd_save_en: true`
    - `scan_bodyframe_pub_en: true`
- Constraint from user: avoid AMCL, optimize out extra workload first.

## 1) Configuration plan (first implementation pass)

### 1.1 Add Jetson runtime profile in `start_robot.sh`

Create a safe, opt-in profile block:

```bash
JETSON_PROFILE="${JETSON_PROFILE:-1}"
```

When `JETSON_PROFILE=1`:

- force lighter startup defaults
- do not alter control/decision behavior
- keep existing ICP localization

Recommended values:

- `ENABLE_RVIZ=0` (headless baseline)
- `START_SERIAL_SENDER=0` unless needed
- `AGX_DESKTOP_MODE=0` by default, set to `1` only when GUI is required

### 1.2 FAST-LIO reductions (biggest memory wins)

Apply in a Jetson-specific FAST-LIO file:

- create `config/reality/fastlio_mid360_jetson.yaml` as a copy of the current real config, then tune:
  - `point_filter_num: 5` (increase downsample factor)
  - `filter_size_surf: 0.6`
  - `filter_size_map: 0.6`
  - `publish.scan_publish_en: false` (close full scan cloud publishing)
  - `publish.map_en: false` (skip global map cloud publish)
  - `publish.effect_map_en: false`
  - `publish.path_en: true` (keep only if needed for diagnostics)
  - `pcd_save.pcd_save_en: false` unless map capture is required
  - set `scan_rate` conservatively if upstream supports it

Then switch FAST-LIO launch in `start_robot.sh` to this profile file when `JETSON_PROFILE=1`.

### 1.3 `pointcloud_to_laserscan` reductions

Use a Jetson-specific CLI or remap wrapper:

- Reduce angular load: smaller full sweep is still needed for Nav2 local planning
  - keep `angle_min=-3.1415`, `angle_max=3.1415` initially
  - reduce points via larger `range_max` + tighter height/quality filters if your environment allows
- Add downsampling / filtering stage if needed:
  - Increase `min_height` / narrow `[min_height,max_height]` for ground noise rejection
  - keep `use_inf:=true` only if useful for behavior; otherwise evaluate false
- Reduce published rates upstream instead of increasing ROS queues.

### 1.4 Nav2 profile reductions

Create/maintain a Jetson Nav2 config variant:

- In `local_costmap`:
  - `publish_frequency`: reduce from 10.0 to 5.0
  - `update_frequency`: reduce from 20.0 to 10.0
  - resolution check: consider `0.05` if navigation quality allows
  - keep `publish_voxel_map: false` (already false in current real file)
- In `global_costmap`:
  - verify no debug publishers are enabled
  - if stvl layer + extra sources are not required, consider disabling optional obstacle layers after field validation
- Costmap memory and CPU:
  - keep robot footprint/obstacle settings conservative first
  - avoid aggressive planner frequencies in first pass
- Planner/control:
  - reduce heavy planner debug publishing:
    - keep visualization flags false
    - avoid extra costmap observers not required by behavior
  - maintain functionality and validate path quality after each step

### 1.5 Remove non-essential nodes/processes on Jetson

Gate with env vars before process startup:

- point cloud visual/debug nodes
- RViz/Gazebo on headless mode
- serial bridge helpers and adapters only when needed
- one-time startup checks/logging that are not required per run

`start_robot.sh` already has:

- `ENABLE_RVIZ` default `0`
- AMCL branch still present but should remain unused in Jetson profile

Keep this as:

- `LOCALIZATION_MODE=icp` on real hardware
- reject/avoid `LOCALIZATION_MODE=amcl` in deployment scripts unless explicitly opt-in

### 1.6 ROS 2 memory footprint controls

- Cap history/reliability only where safe
- Limit service/action timeouts to avoid backlog
- Reduce TF and logging overhead:
  - avoid continuous debug logs in normal mode
  - keep ROS log target on temp storage if write pressure appears

## 2) Execution order

1. Baseline capture (before any changes)
  - record RAM/CPU deltas for `start_robot.sh` idle and moving states
2. Apply FAST-LIO reductions only
3. Apply Nav2 frequency/costmap reductions
4. Apply command-level reductions (`pointcloud_to_laserscan` and startup gating)
5. Tune only one group at a time and validate
6. After navigation stability passes, test concurrent vision
  - keep vision separate process priority lower than nav
7. Decide if further reductions are needed, then apply second-pass tuning

## 3) Validation checklist

- Functional checks
  - `/Odometry`, `/cloud_registered`, `/scan`, `/cmd_vel_chassis_bt` remain published
  - behavior tree still transitions normally
  - ICP initializes and publishes map->odom when required
- Resource checks
  - sustained memory stays below safe margin (not at OOM risk)
  - average CPU per nav2 group lower than baseline
- Recovery checks
  - recover from SLAM relocalization events after restarts
  - launch/relaunch in less than expected startup time

## 4) Risks and rollback

- Too aggressive downsampling may hurt wall/object clearance fidelity
- Disabling map/scans can hide visual diagnostics that operators rely on
- Vision pipeline may still contend under sustained load if image inference peaks overlap with mapping bursts
- Rollback strategy:
  - restore previous config files
  - restart `start_robot.sh` with `JETSON_PROFILE=0`
  - disable profile-specific launch args without changing core stack

## 5) Suggested default for first run

- Start with:
  - `JETSON_PROFILE=1`
  - `ENABLE_RVIZ=0`
  - `LOCALIZATION_MODE=icp`
  - FAST-LIO Jetson profile (publish outputs reduced, pcd save off)
  - Nav2 costmap publish/update reduced and no optional visual debug chatter
  - pointcloud_to_laserscan tuned to reduce downstream scan density while retaining obstacle recall

Then only unlock visual features (`AGX_DESKTOP_MODE=1`, RViz, verbose logs) after memory and behavior are stable.