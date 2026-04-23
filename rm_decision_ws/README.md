# rm_behavior_tree

> This repo is a submodule of [RM2024_SMBU_auto_sentry_ws](https://gitee.com/SMBU-POLARBEAR/RM2024_SMBU_auto_sentry_ws) and **depends on other modules in the parent repo**.

RoboMaster sentry behavior trees on BehaviorTree.CPP, talking to navigation and auto-aim over ROS 2 topics and actions. Develop presets in [simulation](https://gitee.com/SMBU-POLARBEAR/pb_rmsimulation), then deploy on hardware.

## Layout

- BehaviorTree.ROS2

    Forked from [BehaviorTree/BehaviorTree.ROS2](https://github.com/BehaviorTree/BehaviorTree.ROS2), provides a standard pattern for:

  - Action clients
  - Service clients
  - Topic subscribers
  - Topic publishers

- rm_behavior_tree

    RoboMaster sentry behavior trees

- rm_decision_interfaces

    Custom ROS messages for the referee protocol

## Setup

Tested on Ubuntu 22.04, ROS 2 Humble, BehaviorTree.CPP 4.5.

1. Dependencies

    ```sh
    sudo apt install ros-humble-behaviortree-cpp
    ```

2. Clone

    ```sh
    git clone https://gitee.com/SMBU-POLARBEAR/rm_behavior_tree.git
    cd rm_behavior_tree
    ```

3. Build

    ```sh
    colcon build --symlink-install --cmake-args -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
    ```

## Usage

1. Start [mock referee publishers](./rm_decision_interfaces/publish_script.sh)

    ```sh
    ./rm_decision_ws/rm_decision_interfaces/publish_script.sh
    ```

2. Launch the behavior tree

    ```sh
    ros2 launch rm_behavior_tree rm_behavior_tree.launch.py \
    style:=retreat_attack_left \
    use_sim_time:=True
    ```

    `style` matches a behavior XML preset name (see below).

## Behavior presets

- `center_attack_simple`

    Simplified for current mechanics. After match start with healthy state, go to a free point near the center of `RMUL2026`; while moving, keep gimbal scanning and no chassis spin; near center, stop scanning, hand gimbal to auto-aim, spin chassis in place; on low HP or high heat, return to `(0, 0)` and resume scanning.

- `attack_left`

    When healthy, attack left; if ally average HP is below enemy, fall back to center buff; low HP → supply; if attacked while retreating, re-evaluate whether to abort retreat; when attacked, can juke in place.

- `attack_right`

    Same as left, but attacks to the right.

- `retreat_attack_left`

    Same as left attack, plus: in the last 1:30, always fall back to the wall in front of the ally base.

- `protect_supply`

    Conservative: after start, shield the ally supply; after a timer, retreat to the left side of the ally base. Keeps heal and basic jukes.

- `rmuc_01`

    After start, block the ramp area; if attacked while holding, small jukes. If sentry HP is low, prioritize healing. Lowest priority: if outpost HP is below threshold, return base.

## Groot

1. Download [Groot Linux installer](https://www.behaviortree.dev/groot)

2. Install

    ```sh
    chmod +x Groot2-*-linux-installer.run
    ./Groot2-*-linux-installer.run
    ```

3. Run

    ```sh
    cd ~/Groot2/bin
    ./groot2
    ```

4. Open [Project.btproj](./rm_behavior_tree/config/Project.btproj) in Groot
