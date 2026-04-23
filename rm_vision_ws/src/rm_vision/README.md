# rm_vision

<img src="docs/rm_vision.svg" alt="rm_vision" width="200" height="200">

## Overview

There is no official community chat, forum, or board for this project. Any group or site claiming to be an “rm_vision community” is not affiliated—use your judgment.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![State-of-the-art Shitcode](https://img.shields.io/static/v1?label=State-of-the-art&message=Shitcode&color=7B5804)](https://github.com/trekhleb/state-of-the-art-shitcode)

The “Shitcode” badge is intentional: this code is not production-ready. It is for learning and experimentation only. Use it at your own risk.

## Included projects

Armor auto-aim: https://gitlab.com/rm_vision/rm_auto_aim

MindVision camera: https://gitlab.com/rm_vision/ros2_mindvision_camera

Hikvision camera: https://gitlab.com/rm_vision/ros2_hik_camera

Gimbal URDF: https://gitlab.com/rm_vision/rm_gimbal_description

Serial driver: https://gitlab.com/rm_vision/rm_serial_driver

Vision simulator: https://gitlab.com/rm_vision/rm_vision_simulator

## Docker deployment

Pull image:

```
docker pull hezhexi2002/rm_vision:backup
```

Development container:

```
docker run -it --name rv_devel \
--privileged --network host \
-v /dev:/dev -v $HOME/.ros:/root/.ros -v ws:/ros_ws \
hezhexi2002/rm_vision:backup \
ros2 launch foxglove_bridge foxglove_bridge_launch.xml
```

Runtime container:

```
docker run -it --name rv_runtime \
--privileged --network host --restart always \
-v /dev:/dev -v $HOME/.ros:/root/.ros -v ws:/ros_ws \
hezhexi2002/rm_vision:backup \
ros2 launch rm_vision_bringup vision_bringup.launch.py
```

TBD

## Build from source

TBD
