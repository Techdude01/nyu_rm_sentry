#ifndef RM_BEHAVIOR_TREE__PLUGINS__ACTION__IS_GAME_TIME_HPP_
#define RM_BEHAVIOR_TREE__PLUGINS__ACTION__IS_GAME_TIME_HPP_

#include "behaviortree_cpp/condition_node.h"
#include "rm_decision_interfaces/msg/game_status.hpp"

namespace rm_behavior_tree
{

/**
 * @brief Condition: match stage and remaining time vs expected range.
 * Stages: {0, "not started"}, {1, "setup"}, {2, "15s referee self-check"},
 * {3, "5s countdown"}, {4, "match running"}, {5, "match ended / scoring"}
 * @param[in] message Game status (blackboard)
 * @param[in] game_progress Expected stage id
 * @param[in] lower_remain_time Min remaining time (s)
 * @param[in] higher_remain_time Max remaining time (s)
 */
class IsGameTimeCondition : public BT::SimpleConditionNode
{
public:
  IsGameTimeCondition(const std::string & name, const BT::NodeConfig & config);

  BT::NodeStatus checkGameStart();

  static BT::PortsList providedPorts()
  {
    return {
      BT::InputPort<rm_decision_interfaces::msg::GameStatus>("message"),
      BT::InputPort<int>("game_progress"), BT::InputPort<int>("lower_remain_time"),
      BT::InputPort<int>("higher_remain_time")};
  }
};
}  // namespace rm_behavior_tree

#endif  // RM_BEHAVIOR_TREE__PLUGINS__ACTION__IS_GAME_TIME_HPP_
