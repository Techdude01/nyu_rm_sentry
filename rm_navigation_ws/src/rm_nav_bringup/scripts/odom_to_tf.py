#!/usr/bin/env python3
"""
Subscribe to /Odometry and publish the matching TF.
Workaround for gazebo_ros_planar_move not publishing TF.
"""
import rclpy
from rclpy.node import Node
from nav_msgs.msg import Odometry
from tf2_ros import TransformBroadcaster
from geometry_msgs.msg import TransformStamped


class OdomToTF(Node):
    def __init__(self):
        super().__init__('odom_to_tf')
        
        self.declare_parameter('odom_topic', '/Odometry')
        self.declare_parameter('use_current_time_for_tf', True)
        odom_topic = self.get_parameter('odom_topic').get_parameter_value().string_value
        self.use_current_time_for_tf = (
            self.get_parameter('use_current_time_for_tf').get_parameter_value().bool_value
        )
        
        self.tf_broadcaster = TransformBroadcaster(self)
        self.subscription = self.create_subscription(
            Odometry,
            odom_topic,
            self.odom_callback,
            10
        )
        self.get_logger().info(
            f'odom_to_tf: subscribed to {odom_topic}, publishing TF '
            f'(use_current_time_for_tf={self.use_current_time_for_tf})'
        )

    def odom_callback(self, msg: Odometry):
        t = TransformStamped()
        t.header.frame_id = msg.header.frame_id
        if self.use_current_time_for_tf:
            t.header.stamp = self.get_clock().now().to_msg()
        else:
            t.header.stamp = msg.header.stamp
        t.child_frame_id = msg.child_frame_id
        t.transform.translation.x = msg.pose.pose.position.x
        t.transform.translation.y = msg.pose.pose.position.y
        t.transform.translation.z = msg.pose.pose.position.z
        t.transform.rotation = msg.pose.pose.orientation
        self.tf_broadcaster.sendTransform(t)


def main(args=None):
    rclpy.init(args=args)
    node = OdomToTF()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
