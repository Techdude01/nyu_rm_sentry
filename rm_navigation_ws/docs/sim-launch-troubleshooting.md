# Simulation launch troubleshooting

## Issue 1: `pointcloud_to_laserscan_sim` script not found

**Symptom**: `can't open file '.../pointcloud_to_laserscan_sim.py': No such file or directory`

**Cause**: The script was installed under `lib/`; sourcing order (e.g. nav_ws then rm_navigation_ws) could break path resolution.

**Fix**: Install the script under `share/rm_nav_bringup/scripts/` and have launch use that path.

---

## Issue 2: `spawn_entity` times out / robot not spawned

**Symptom**: `Entity pushed to spawn queue, but spawn service timed out waiting for entity to appear`

**Cause**: Race between `spawn_entity` and `gzserver`, or slow world load.

**Fix** (already applied) in `pb_rm_simulation/launch/rm_simulation.launch.py`:
- Start `gzserver` first, then delay 10s before `spawn_entity`
- Add `-timeout 60` to `spawn_entity`

---

## Issue 3: `map` frame missing / `Invalid frame ID "map"`

**Symptom**:
- RViz: `Invalid frame id: map passed to argument frame does not exist`
- `local_costmap: Timed out waiting for transform... frame does not exist`

**Cause**:
1. `mode:=nav` or `localization` not set, so `map_server` / AMCL did not start
2. `localization:=slam_toolbox` needs a **pose-graph** (`.posegraph`); `map/RMUL` is only a grid (`.yaml` + `.pgm`), so slam_toolbox cannot load it
3. AMCL only publishes `map->odom` after **2D Pose Estimate** in RViz; until then `map` may not exist

**Fix**:
1. Use the correct args (include `mode:=nav` and `localization:=amcl`):

```bash
ros2 launch rm_nav_bringup bringup_sim.launch.py \
  world:=RMUL mode:=nav localization:=amcl lio:=fastlio nav_rviz:=True
```

2. RViz default Fixed Frame is `odom` to avoid errors at start; switch to `map` after AMCL is ready
3. Click **2D Pose Estimate** in RViz and set the robot pose so AMCL publishes `map`
4. For slam_toolbox localization, build a map in mapping mode, save a pose-graph, then load it in localization mode

---

## Issue 4: fastlio / ground_segmentation crash (`libusb_set_option`)

**Symptom**: `symbol lookup error: libusb_set_option`

**Cause**: PCL vs system libusb mismatch.

**Workaround**: In sim you can avoid LIO and use slam_toolbox or AMCL. If you must use fastlio, try:
```bash
export LD_PRELOAD=/lib/x86_64-linux-gnu/libusb-1.0.so.0
```

---

## Suggested command (RMUL sim + nav)

**Gazebo odometry (recommended, stabler, less “flyaway”):**
```bash
ros2 launch rm_nav_bringup bringup_sim.launch.py \
  world:=RMUL mode:=nav localization:=amcl use_gazebo_odom:=true nav_rviz:=True
```
- With `use_gazebo_odom:=true`, Fast-LIO is not started; Gazebo provides `odom->base_link`
- Sim odom has no drift; AMCL is more stable

**Fast-LIO odometry (original):**
```bash
ros2 launch rm_nav_bringup bringup_sim.launch.py \
  world:=RMUL mode:=nav localization:=amcl lio:=fastlio nav_rviz:=True
```

Notes:
- `localization:=amcl` uses `RMUL` grid map (`yaml`/`pgm`)
- Set initial pose in RViz (2D Pose Estimate) before sending nav goals

---

## If sim is still heavy

1. **Headless** (no Gazebo GUI, much lower GPU use):
```bash
ros2 launch rm_nav_bringup bringup_sim.launch.py \
  world:=RMUL mode:=nav localization:=amcl lio:=fastlio headless:=True nav_rviz:=True
```

2. **Turn off Nav RViz** when you do not need it:
```bash
nav_rviz:=False
```

3. The stack is already tuned: Gazebo physics 100Hz, ~1/4 Livox density, and lower Fast-LIO/AMCL/Nav2 settings.
