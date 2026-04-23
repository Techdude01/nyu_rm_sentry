#ifndef RM_BEHAVIOR_TREE__PLUGINS__ACTION__IS_FRIEND_OK_HPP_
#define RM_BEHAVIOR_TREE__PLUGINS__ACTION__IS_FRIEND_OK_HPP_

#include "behaviortree_cpp/condition_node.h"
#include "rm_decision_interfaces/msg/all_robot_hp.hpp"

namespace rm_behavior_tree
{

/**
 * @brief Condition: whether ally average HP is greater than enemy average HP.
 * @param[in] message All-robot HP topic (blackboard)
 * @param[in] friend_color Ally team: "red" or "blue"
 */
class IsFriendOKAction : public BT::SimpleConditionNode
{
public:
  IsFriendOKAction(const std::string & name, const BT::NodeConfig & config);

  // BT::NodeStatus checkGameStart(BT::TreeNode & self_node)
  BT::NodeStatus checkFriendStatus();

  static BT::PortsList providedPorts()
  {
    return {
      BT::InputPort<rm_decision_interfaces::msg::AllRobotHP>("message"),
      BT::InputPort<std::string>("friend_color")};
  }
};
}  // namespace rm_behavior_tree

#endif  // RM_BEHAVIOR_TREE__PLUGINS__ACTION__IS_FRIEND_OK_HPP_
