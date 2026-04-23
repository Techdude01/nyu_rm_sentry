# Polar Bear vision stack

> ROS 2–based vision stack for multiple RoboMaster vehicle roles.

`rm_vision` was integrated into this system with armor aiming; energy rune detection, ore pickup, and exchange-station recognition are in development.

## 1. Environment setup and build

```sh
rosdep install --from-paths src --ignore-src -r -y
sudo apt install ros-humble-serial-driver
```

```sh
git clone https://gitee.com/SMBU-POLARBEAR/PB_RM_Vision
cd PB_RM_Vision
```

```sh
colcon build --symlink-install
```

## 2. Usage

### 2.1 Launch all modules

Available launch files and roles:

<!-- markdownlint-disable MD033 -->

- <details>

    <summary>rm_vision</summary>

    Armor detection only.

    ```sh
    sudo chmod 777 /dev/ttyACM0

    source install/setup.bash
    ros2 launch rm_vision_bringup vision_bringup.launch.py
    ```

  </details>

<!-- markdownlint-enable MD033 -->

- Infantry: armor detection and energy rune detection

  ```sh
  sudo chmod 777 /dev/ttyACM0

  source install/setup.bash
  ros2 launch rm_vision_bringup infantry_bringup.launch.py
  ```

- Hero: armor detection

  ```sh
  sudo chmod 777 /dev/ttyACM0

  source install/setup.bash
  ros2 launch rm_vision_bringup hero_bringup.launch.py
  ```

- Engineer: exchange-station and ore detection (planned)

- Sentry: armor detection

### 2.2 Visualization

```sh
source install/setup.bash
ros2 launch foxglove_bridge foxglove_bridge_launch.xml port:=8765
```

### 2.3 Run a single sub-package

Optional; useful when debugging a node in isolation with RViz or similar.

- Auto-aim

    ```sh
    source install/setup.bash
    ros2 launch auto_aim_bringup auto_aim.launch.py 
    ```

- Hikvision camera

    ```sh
    source install/setup.bash
    ros2 launch hik_camera hik_camera.launch.py
    ```

- Serial driver

    ```sh
    sudo chmod 777 /dev/ttyACM0

    source install/setup.bash
    ros2 launch rm_serial_driver serial_driver.launch.py
    ```

- Energy rune detector

    ```sh
    source install/setup.bash
    ros2 launch rm_rune_detector rm_rune_detector.launch.py
    ```

## 3. Reference

### 3.1 Serial protocol

See [rm_serial_driver README](src/rm_serial_driver/README.md).

## Other documentation

- rm_vision deployment: [HuaShi vision deployment (Flowus)](https://flowus.cn/lihanchen/share/0d472992-f136-4e0e-856f-89328e99c684) 

- Camera intrinsics and distortion: [Camera calibration (Flowus)](https://flowus.cn/lihanchen/share/02a518a0-f1bb-47a5-8313-55f75bab21b5)

- [Progress and roadmap](docs/progress-and-roadmap.md) · [Using ROS 2](docs/ros2-usage.md)
