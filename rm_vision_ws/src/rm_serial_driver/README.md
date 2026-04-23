# rm_serial_driver

Serial communication between the RoboMaster perception stack and the embedded controller.

This repository is a submodule of [pb_rm_vision](https://gitee.com/SMBU-POLARBEAR/PB_RM_Vision).

This branch targets the **sentry** platform. `rm_serial_driver` was extended with several custom message types for the behavior tree; it is tightly coupled with [rm_behavior_tree](https://gitee.com/SMBU-POLARBEAR/rm_behavior_tree).

## Overview

Built on [transport_drivers](https://github.com/ros-drivers/transport_drivers), this package bridges the host PC and the MCU.

## Usage

Install dependency: `sudo apt install ros-humble-serial-driver`

Edit [serial_driver.yaml](config/serial_driver.yaml) to match the serial device used for MCU communication.

Grant access: `sudo chmod 777 /dev/ttyACM0`

Launch: `ros2 launch rm_serial_driver serial_driver.launch.py`

## Packet interface

| **packet**          | **header** | **information** |
|:-------------------:|:----------:|:---------------:|
| SendPacketVision    | 0xA5       | Target observations for the MCU (ballistics solved on MCU) |
| SendPacketTwist     | 0xA4       | Chassis navigation |
| SendPacketTwist     | 0xA3       | Robot control commands   |
| ReceivePacketVision | 0x5A       | Gimbal pose for auto-aim         |
| ReceivePacketAllRobotHP  | 0x5B  | HP for all robots           |
| ReceivePacketGameStatus  | 0x5C  | Match phase and time           |
| ReceivePacketRobotStatus | 0x5D  | Robot status          |

See [packet.hpp](include/rm_serial_driver/packet.hpp) and [rm_decision_interfaces](https://gitee.com/SMBU-POLARBEAR/rm_behavior_tree/tree/master/rm_decision_interfaces/msg).

### SendPacketVision

- Sends `armor_tracker` output: target observation; motion prediction, armor selection, and ballistics run on the MCU.

### SendPacketTwist (navigation)

- Output from the navigation stack for sentry chassis control.

- `linear`: linear velocity with x, y, z in m/s (axis per [REP-103](https://www.ros.org/reps/rep-0103.html)).
- `angular`: angular velocity with x, y, z in rad/s.

### SendPacketRobotControl

- `stop_gimbal_scan`: bool — stop gimbal scan mode.
- `chassis_spin_vel`: float — chassis “spin” angular rate, rad/s.

### ReceivePacketVision

- `robot_color` — ally/enemy color for detection targets.
- Gimbal `pitch` and `yaw` — units and axes per <https://www.ros.org/reps/rep-0103.html>.
- Current aim point `aim_x, aim_y, aim_z` — for visualization Markers.

### ReceivePacketAllRobotHP

Referee system HP for all robots, outposts, and base: [AllRobotHP.msg](https://gitee.com/SMBU-POLARBEAR/rm_behavior_tree/blob/master/rm_decision_interfaces/msg/AllRobotHP.msg)

### ReceivePacketGameStatus

Match phase and time from the referee: [GameStatus.msg](https://gitee.com/SMBU-POLARBEAR/rm_behavior_tree/blob/master/rm_decision_interfaces/msg/GameStatus.msg)

### ReceivePacketRobotStatus

Referee data for this robot (sentry): [RobotStatus.msg](https://gitee.com/SMBU-POLARBEAR/rm_behavior_tree/blob/master/rm_decision_interfaces/msg/RobotStatus.msg)

  `robot_id` — forwarded by referee, this robot’s ID.

  `current_hp` — forwarded by referee, live HP.

  `shooter_heat` — forwarded by referee, barrel heat (single barrel).

  `team_color` — processed on MCU, ally color: 0 Red, 1 Blue.

  `is_attacked` — processed on MCU, whether HP dropped: 0 False, 1 True.
