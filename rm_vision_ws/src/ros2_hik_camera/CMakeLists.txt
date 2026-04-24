cmake_minimum_required(VERSION 3.8)
project(hik_camera)

## Use C++14
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

## By adding -Wall and -Werror, the compiler does not ignore warnings anymore,
## enforcing cleaner code.
add_definitions(-Wall -Werror)

## Export compile commands for clangd
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_package(ament_cmake_auto REQUIRED)
ament_auto_find_build_dependencies()

ament_auto_add_library(${PROJECT_NAME} SHARED
  src/hik_camera_node.cpp
)

target_include_directories(${PROJECT_NAME} PUBLIC hikSDK/include)

set(HIK_SDK_ARCH_DIR "")
set(HIK_SDK_LIB_DIR "" CACHE PATH "Override Hik SDK library directory")
if(HIK_SDK_LIB_DIR)
  set(HIK_SDK_ARCH_DIR "${HIK_SDK_LIB_DIR}")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|amd64)$")
  set(HIK_SDK_ARCH_DIR "${CMAKE_CURRENT_SOURCE_DIR}/hikSDK/lib/amd64")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$")
  set(HIK_SDK_ARCH_DIR "${CMAKE_CURRENT_SOURCE_DIR}/hikSDK/lib/arm64")
endif()
if(HIK_SDK_ARCH_DIR STREQUAL "")
  message(FATAL_ERROR "Unsupported host system architecture: ${CMAKE_SYSTEM_PROCESSOR}. Set HIK_SDK_LIB_DIR to a compatible Hik SDK library path.")
endif()
if(NOT EXISTS "${HIK_SDK_ARCH_DIR}")
  message(FATAL_ERROR "Hik SDK library directory does not exist: ${HIK_SDK_ARCH_DIR}")
endif()
target_link_directories(${PROJECT_NAME} PUBLIC "${HIK_SDK_ARCH_DIR}")
install(
  DIRECTORY "${HIK_SDK_ARCH_DIR}/"
  DESTINATION lib
)

target_link_libraries(${PROJECT_NAME}
  FormatConversion
  MediaProcess
  MvCameraControl
  MVRender
  MvUsb3vTL
)

rclcpp_components_register_node(${PROJECT_NAME}
  PLUGIN hik_camera::HikCameraNode
  EXECUTABLE ${PROJECT_NAME}_node
)

if(BUILD_TESTING)
  find_package(ament_lint_auto REQUIRED)
  list(APPEND AMENT_LINT_AUTO_EXCLUDE
    ament_cmake_copyright
    ament_cmake_cpplint
    ament_cmake_uncrustify
  )
  ament_lint_auto_find_test_dependencies()
endif()

ament_auto_package(
  INSTALL_TO_SHARE
  launch
  config
)
