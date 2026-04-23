# Using ROS 2

- [Creating a package](#creating-a-package)
  - [Editing CMakeLists.txt](#editing-cmakeliststxt)
  - [Editing package.xml](#editing-packagexml)
- [Building the project](#building-the-project)
- [Troubleshooting](#troubleshooting)
  - [Editor cannot find ROS 2 headers](#editor-cannot-find-ros-2-headers)
  - [undefined symbol](#undefined-symbol)

## Creating a package

In ROS 2, use `ros2 pkg create` to create a new C++ package.

Example: create a package named `rm_rune_detector` that depends on `rclcpp` and `std_msgs`:

```shell
ros2 pkg create --build-type ament_cmake rm_rune_detector --dependencies rclcpp std_msgs
```

This creates a directory `rm_rune_detector` with a basic ROS 2 package layout and a `CMakeLists.txt` already configured for `rclcpp` and `std_msgs`.

Adjust the command as needed: change the package name and replace `rclcpp` / `std_msgs` with your dependencies.

### Editing CMakeLists.txt

`CMakeLists.txt` configures how the project is built.

Below is an example; focus on the **Build** section (`ament_auto_add_library` and `rclcpp_components_register_node`):

```cmake
cmake_minimum_required(VERSION 3.10)
project(rm_rune_detector)

## Use C++14
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

## By adding -Wall and -Werror, the compiler does not ignore warnings anymore,
## enforcing cleaner code.
add_definitions(-Wall -Werror)

## Export compile commands for clangd
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

#######################
## Find dependencies ##
#######################

find_package(ament_cmake_auto REQUIRED)
ament_auto_find_build_dependencies()

###########
## Build ##
###########

ament_auto_add_library(${PROJECT_NAME} SHARED
  src/rm_rune_detector.cpp
)

rclcpp_components_register_node(${PROJECT_NAME}
  PLUGIN rm_rune_detector::RMRuneDetector
  EXECUTABLE ${PROJECT_NAME}_node
)

#############
## Testing ##
#############

if(BUILD_TESTING)
  find_package(ament_lint_auto REQUIRED)
  list(APPEND AMENT_LINT_AUTO_EXCLUDE
    ament_cmake_copyright
    ament_cmake_uncrustify
  )
  ament_lint_auto_find_test_dependencies()
endif()

#############
## Install ##
#############

ament_auto_package(
  INSTALL_TO_SHARE
  launch
)
```

### Editing package.xml

`package.xml` defines package metadata and dependencies.

Add dependencies with `depend` elements:

```xml
<depend></depend>
```


## Building the project

Use `colcon build` to build the workspace.

> Tip: `--symlink-install` symlinks install-space files so config changes often do not require a rebuild.

Example:

```shell
colcon build --symlink-install
```

## Troubleshooting

### Editor cannot find ROS 2 headers

ROS headers may show as missing in the editor.

```cpp
#include <rclcpp/publisher.hpp>
#include <rclcpp/rclcpp.hpp>
#include <rclcpp/subscription.hpp>
```

Use **Quick Fix** → **Edit includePath**, open **Include path**, and add (replace `humble` with your distro if different):

```
/opt/ros/humble/**
```

### undefined symbol

Errors like the following often mean some sources were not linked or compiled (CMakeLists issue):

```shell
[rm_rune_detector_node-3] /home/polarbear/Desktop/Polarbear_Vision_ws/PB_RM_Vision/install/rm_rune_detector/lib/rm_rune_detector/rm_rune_detector_node: symbol lookup error: /home/polarbear/Desktop/Polarbear_Vision_ws/PB_RM_Vision/install/rm_rune_detector/lib/librm_rune_detector.so: undefined symbol: _ZN16rm_rune_detector9PnPSolverC1ERKSt5arrayIdLm9EERKSt6vectorIdSaIdEE
```

If `ament_auto_add_library` lists only some files:

```cmake
ament_auto_add_library(${PROJECT_NAME} SHARED
  src/rm_rune_detector.cpp
)
```

use the `src` directory form so all sources under `src` are included:

```cmake
ament_auto_add_library(${PROJECT_NAME} SHARED
  DIRECTORY src
)
```
