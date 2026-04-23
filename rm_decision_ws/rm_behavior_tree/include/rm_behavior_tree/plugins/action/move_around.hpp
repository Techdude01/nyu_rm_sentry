#ifndef RM_BEHAVIOR_TREE__PLUGINS__ACTION__MOVE_AROUND_HPP_
#define RM_BEHAVIOR_TREE__PLUGINS__ACTION__MOVE_AROUND_HPP_

#include <geometry_msgs/msg/transform_stamped.hpp>
#include <rclcpp/node.hpp>
#include <rclcpp/publisher.hpp>

#include "behaviortree_cpp/action_node.h"
#include "behaviortree_ros2/bt_topic_pub_node.hpp"
#include "geometry_msgs/msg/pose_stamped.hpp"

namespace rm_behavior_tree
{

/**
 * @brief Juke: sample random goals within a disk around the current pose to dodge fire.
 * @param[in] message Current robot pose (TransformStamped)
 * @param[in] expected_nearby_goal_count How many random goals to try
 * @param[in] expected_dis Disk radius (m)
 */
class MoveAroundAction : public BT::StatefulActionNode, rclcpp::Node
{
public:
  MoveAroundAction(const std::string & name, const BT::NodeConfig & config);

  static BT::PortsList providedPorts()
  {
    return {
      BT::InputPort<int>("expected_nearby_goal_count"), BT::InputPort<float>("expected_dis"),
      BT::InputPort<geometry_msgs::msg::TransformStamped>("message")};
  }

  BT::NodeStatus onStart() override;

  BT::NodeStatus onRunning() override;

  void onHalted() override;

  void generatePoints(
    geometry_msgs::msg::TransformStamped location, double distance,
    geometry_msgs::msg::PoseStamped & nearby_random_point);

  void setMessage(geometry_msgs::msg::PoseStamped & msg);

  void sendGoalPose(geometry_msgs::msg::PoseStamped & msg);

private:
  int goal_count;
  int expected_nearby_goal_count;
  float expected_dis;
  geometry_msgs::msg::TransformStamped current_location;
  geometry_msgs::msg::PoseStamped nearby_random_point;
  rclcpp::Publisher<geometry_msgs::msg::PoseStamped>::SharedPtr publisher_goal_pose;
};
}  // namespace rm_behavior_tree

#endif  // RM_BEHAVIOR_TREE__PLUGINS__ACTION__MOVE_AROUND_HPP_
