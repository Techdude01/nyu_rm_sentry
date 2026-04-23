# rm_auto_aim

## Overview

RoboMaster armor auto-aim stack.

<img src="docs/rm_vision.svg" alt="rm_vision" width="200" height="200">

This package is a submodule of [rm_vision](https://github.com/chenjunnn/rm_vision).

If you find it useful, please star the project.

### License

The source code is released under a [MIT license](rm_auto_aim/LICENSE).

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

Author: Chen Jun

Tested on Ubuntu 22.04 / ROS 2 Humble (other setups not verified).

![Build Status](https://github.com/chenjunnn/rm_auto_aim/actions/workflows/ros_ci.yml/badge.svg)

## Building from Source

### Building

Install [ROS 2 Humble](https://docs.ros.org/en/humble/Installation/Ubuntu-Install-Debians.html) on Ubuntu 22.04.

Create a workspace, clone, install dependencies with rosdep, then build:

	cd ros_ws/src
	git clone https://github.com/chenjunnn/rm_auto_aim.git
	cd ..
	rosdep install --from-paths src --ignore-src -r -y
	colcon build --symlink-install --packages-up-to auto_aim_bringup

### Testing

Run the tests with

	colcon test --packages-up-to auto_aim_bringup

## Packages

- [armor_detector](armor_detector)

	Subscribe to camera info and images, detect armor, and publish 3D positions in the input frame (typically camera frame at the optical center).

- [armor_tracker](armor_tracker)

	Subscribe to detector output and TF; transform armor poses into a chosen inertial frame (typical: gimbal center, X aligned with IMU yaw at power-on). Feeds the tracker and publishes tracked target state in that frame.

- auto_aim_interfaces

	Message definitions for the detector, tracker, and debug topics.

- auto_aim_bringup

	Default parameters, launch files, and bringup for detector + tracker.
