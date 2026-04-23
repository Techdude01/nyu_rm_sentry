#ifndef RM_BEHAVIOR_TREE__PLUGINS__ACTION__IS_STATUS_OK_HPP_
#define RM_BEHAVIOR_TREE__PLUGINS__ACTION__IS_STATUS_OK_HPP_

#include "behaviortree_cpp/condition_node.h"
#include "rm_decision_interfaces/msg/robot_status.hpp"

namespace rm_behavior_tree
{
/**
 * @brief Condition: whether robot status is within HP/heat limits.
 *
 * Reads `RobotStatus`, HP threshold, and heat threshold. Fails if HP is below threshold or heat
 * is above threshold; succeeds otherwise.
 * @param[in] message Robot status (blackboard)
 * @param[in] hp_threshold Minimum HP (sentry max HP 600)
 * @param[in] heat_threshold Maximum heat (sentry max heat 400)
 */
class IsStatusOKAction : public BT::SimpleConditionNode
{
public:
  IsStatusOKAction(const std::string & name, const BT::NodeConfig & config);

  // BT::NodeStatus checkGameStart(BT::TreeNode & self_node)
  BT::NodeStatus checkRobotStatus();

  static BT::PortsList providedPorts()
  {
    return {
      BT::InputPort<rm_decision_interfaces::msg::RobotStatus>("message"),
      BT::InputPort<int>("hp_threshold"), BT::InputPort<int>("heat_threshold")};
  }
};
}  // namespace rm_behavior_tree

#endif  // RM_BEHAVIOR_TREE__PLUGINS__ACTION__IS_STATUS_OK_HPP_
