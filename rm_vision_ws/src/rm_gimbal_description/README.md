# rm_gimbal_description

URDF for the RoboMaster vision / auto-aim stack.

<img src="docs/rm_vision.svg" alt="rm_vision" width="200" height="200">

This package is a submodule of [rm_vision](https://github.com/chenjunnn/rm_vision).

## Frame conventions

Units and axis directions follow https://www.ros.org/reps/rep-0103.html

`gimbal_odom`: inertial frame with origin at the gimbal center

`yaw_joint`: rotation between the gimbal yaw axis and the inertial frame

`pitch_joint`: rotation between the gimbal pitch axis and the inertial frame

`camera_joint`: transform from the camera to the inertial frame

`camera_optical_joint`: rotation from the z-forward camera frame to the x-forward optical frame

## Usage

Edit `gimbal_camera_transfrom` in [urdf/rm_gimbal.urdf.xacro](urdf/rm_gimbal.urdf.xacro). 

`xyz` and `rpy` are the camera pose relative to the gimbal center; measure from mechanical drawings or on the robot.
