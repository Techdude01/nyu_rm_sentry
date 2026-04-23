# armor_tracker

- [ArmorTrackerNode](#armortrackernode)
  - [Tracker](#tracker)
    - [KalmanFilter](#kalmanfilter)

## ArmorTrackerNode
Armor tracking node.

Subscribe to detector poses and robot TF; transform armor positions into a chosen inertial frame (typical: gimbal center, X along IMU yaw at power-on), run the tracker, and publish tracked robot state in that frame.

**Subscribes:**
- Detected armors `/detector/armors`
- Transforms `/tf` `/tf_static`

**Publishes:**
- Locked target `/tracker/target`

**Parameters:**
- Tracker `tracker`
  - Max association distance between frames `max_match_distance`
  - `DETECTING` → `TRACKING` threshold `tracking_threshold`
  - `TRACKING` → `LOST` threshold `lost_threshold`

## ExtendedKalmanFilter

$$ x_c = x_a + r * cos (\theta) $$
$$ y_c = y_a + r * sin (\theta) $$

$$ x = [x_c, y_c,z, yaw, v_{xc}, v_{yc},v_z, v_{yaw}, r]^T $$

Kalman filter implemented with Eigen, following OpenCV’s conventions.

[Kalman filter (Wikipedia)](https://en.wikipedia.org/wiki/Kalman_filter)

![](docs/Kalman_filter_model.png)

Auto-aim has sensing only (no control input), so the input–control matrix $B$ and control vector $u$ are omitted.

Prediction and update:

**Predict:**

$$ x_{k|k-1} = F * x_{k-1|k-1} $$

$$ P_{k|k-1} = F * P_{k-1|k-1}* F^T + Q $$

**Update:**

$$ K = P_{k|k-1} * H^T * (H * P_{k|k-1} * H^T + R)^{-1} $$

$$ x_{k|k} = x_{k|k-1} + K * (z_k - H * x_{k|k-1}) $$

$$ P_{k|k} = (I - K * H) * P_{k|k-1} $$

## Tracker

Association follows [SORT (Simple online and realtime tracking)](https://ieeexplore.ieee.org/abstract/document/7533003/); a Kalman filter tracks a single 3D target.

Measurement: position (x, y, z) in the chosen inertial frame. State: position and velocity (x, y, z, vx, vy, vz).

Motion model: constant velocity in that frame, i.e. $x_{pre} = x_{post} + v_{post} * dt$.

Gating: L2 distance in 3D between prediction and detections.

Tracker states:
- `DETECTING` — short detections only; need more frames before track lock
- `TRACKING` — nominal tracking
- `TEMP_LOST` — brief miss; predict with the filter
- `LOST` — track lost

**Flow**

- **init:** pick the closest target to the camera center, initialize the filter with zero velocity

- **update:** predict, match detections to prediction (L2 gate), reset on total miss; otherwise update with the best match and publish the filtered state

