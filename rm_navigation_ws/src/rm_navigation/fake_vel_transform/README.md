# fake_vel_transform

This package supports sharing the yaw axis between the lidar and gimbal: even when the gimbal is scanning, velocity transforms still yield relatively stable trajectory tracking.

## How it works

Create a `base_link_fake` frame whose XYZ matches `base_link` and whose RPY aligns with the local planner heading, so Nav2’s local planner treats the robot orientation as aligned with the current path.

Nav2 publishes twists in `base_link_fake`; tf2 maps them to `base_link` so the chassis moves correctly. In simulation this allows trajectory following even when the chassis is spinning.

On the embedded side, the forward driving direction for chassis commands is the barrel / gimbal forward direction.

## fake_vel_transform_node

Subscribes:

- Velocity from Nav2 in `base_link_fake`: `/cmd_vel`
- Local path heading from the Nav2 controller: `/local_path`
- TF from `odom` to `base_link`

Publishes:

- Twist in `base_link` for the chassis: `/cmd_vel_chassis`

Static parameters:

- Chassis fixed spin rate: `spin_speed`

  With a fixed spin rate on the embedded side, set `spin_speed` negative to slow the spin while moving.
