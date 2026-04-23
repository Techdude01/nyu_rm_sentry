#!/usr/bin/env python3
"""
Sim-only pointcloud_to_laserscan: always subscribe and publish /scan (no lazy subscription).
Fixes upstream lazy subscription leaving /scan empty.
"""
import struct
import math
import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy, DurabilityPolicy
from sensor_msgs.msg import PointCloud2, LaserScan


def read_points_xyz(cloud_msg):
    """Parse (x,y,z) from PointCloud2; supports xyz and xyzrgb layouts."""
    points = []
    point_step = cloud_msg.point_step
    offset_x = offset_y = offset_z = None
    for f in cloud_msg.fields:
        if f.name == 'x':
            offset_x = f.offset
        elif f.name == 'y':
            offset_y = f.offset
        elif f.name == 'z':
            offset_z = f.offset
    if offset_x is None or offset_y is None or offset_z is None:
        return points
    data = bytes(cloud_msg.data)
    for i in range(0, len(data), point_step):
        chunk = data[i:i + point_step]
        try:
            x = struct.unpack_from('<f', chunk, offset_x)[0]
            y = struct.unpack_from('<f', chunk, offset_y)[0]
            z = struct.unpack_from('<f', chunk, offset_z)[0]
            points.append((x, y, z))
        except struct.error:
            continue
    return points


class PointcloudToLaserScanSim(Node):
    def __init__(self):
        super().__init__('pointcloud_to_laserscan_sim')
        # Do not declare use_sim_time here; launch passes -p use_sim_time:=true
        self.declare_parameter('cloud_topic', '/livox/lidar/pointcloud')
        self.declare_parameter('scan_topic', '/scan')
        self.declare_parameter('min_height', -0.5)
        self.declare_parameter('max_height', 2.0)
        self.declare_parameter('angle_min', -math.pi)
        self.declare_parameter('angle_max', math.pi)
        # pi/360->pi/180: coarser angular resolution, lighter downstream load
        self.declare_parameter('angle_increment', math.pi / 180.0)
        self.declare_parameter('range_min', 0.1)
        self.declare_parameter('range_max', 20.0)
        self.declare_parameter('scan_time', 0.1)

        cloud_topic = self.get_parameter('cloud_topic').value
        scan_topic = self.get_parameter('scan_topic').value

        qos = QoSProfile(depth=10, reliability=ReliabilityPolicy.BEST_EFFORT, durability=DurabilityPolicy.VOLATILE)
        self.sub = self.create_subscription(PointCloud2, cloud_topic, self.callback, qos)
        self.pub = self.create_publisher(LaserScan, scan_topic, 10)

        self.get_logger().info(f'Sim pointcloud_to_laserscan: {cloud_topic} -> {scan_topic} (always subscribed)')

    def callback(self, msg):
        try:
            points = read_points_xyz(msg)
        except Exception as e:
            self.get_logger().warn(f'Failed to read point cloud: {e}')
            return

        if not points:
            return

        angle_min = self.get_parameter('angle_min').value
        angle_max = self.get_parameter('angle_max').value
        angle_inc = self.get_parameter('angle_increment').value
        range_min = self.get_parameter('range_min').value
        range_max = self.get_parameter('range_max').value
        min_h = self.get_parameter('min_height').value
        max_h = self.get_parameter('max_height').value
        scan_time = self.get_parameter('scan_time').value

        n_rays = int(math.ceil((angle_max - angle_min) / angle_inc))
        ranges = [float('inf')] * n_rays

        for x, y, z in points:
            if math.isnan(x) or math.isnan(y) or math.isnan(z):
                continue
            if z < min_h or z > max_h:
                continue
            r = math.hypot(x, y)
            if r < range_min or r > range_max:
                continue
            angle = math.atan2(y, x)
            if angle < angle_min or angle > angle_max:
                continue
            idx = int((angle - angle_min) / angle_inc)
            if 0 <= idx < n_rays and r < ranges[idx]:
                ranges[idx] = r

        scan = LaserScan()
        scan.header = msg.header
        scan.angle_min = angle_min
        scan.angle_max = angle_max
        scan.angle_increment = angle_inc
        scan.time_increment = 0.0
        scan.scan_time = scan_time
        scan.range_min = range_min
        scan.range_max = range_max
        scan.ranges = [float(r) for r in ranges]
        self.pub.publish(scan)


def main():
    rclpy.init()
    node = PointcloudToLaserScanSim()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
