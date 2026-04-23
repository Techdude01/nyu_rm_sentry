# RViz map not showing — troubleshooting

## 1. Confirm `/map` is published

```bash
ros2 topic list | grep map
ros2 topic echo /map --once
ros2 topic hz /map
```

If there is no `/map` or it never gets data, `map_server` or `slam_toolbox` is not healthy.

---

## 2. Plan A (fake sensors + saved map)

- The map is loaded from yaml by **map_server**
- If `map_server` fails or is not running, `/map` is not published
- Check: `ros2 topic list` should include `/map`

**Likely cause:** Nav2 controller failed earlier so lifecycle never fully activated; `map_server` may not be up.  
**Fix:** Restart the full test, or bring up `map_server` alone to verify.

---

## 3. Plan B (Gazebo simulation, mapping mode)

- The map is built live by **slam_toolbox**
- `slam_toolbox` needs **/scan**
- Chain: Gazebo Livox → Fast-LIO → `/cloud_registered` → segmentation → pointcloud_to_laserscan → **/scan**

**Likely cause:** `segmentation` `input_topic` is `/livox/lidar/pointcloud`, which may be missing in sim (sim often publishes `CustomMsg` on `/livox/lidar` only), so no `/scan`, no map, `/map` empty or very late.

---

## 4. RViz display settings

1. **Fixed Frame** should be `map`
   - Left: Global Options → Fixed Frame → `map`
   - If you use `base_link` etc., the map may be missing or misaligned

2. **Map display**
   - Under Displays, ensure "Map" exists
   - Expand Map; Topic should be `/map`
   - Map must be enabled (checkbox)

3. **QoS mismatch**
   - If Map shows "Status: Ok" but no image, try:
   - When adding Map, set QoS to `transient_local` + `reliable`

---

## 5. TF check

```bash
ros2 run tf2_tools view_frames
ros2 run tf2_ros tf2_echo map odom
```

Map display does not strictly need TF, but if Fixed Frame is `map` and `map` is missing from TF, other displays may error.
