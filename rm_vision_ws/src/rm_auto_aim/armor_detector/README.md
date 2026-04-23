# armor_detector

- [Detector node](#detector-node)
  - [DetectorNode](#detectornode)
  - [Detector](#detector)
    - [NumberClassifier](#numberclassifier)
  - [PnPSolver](#pnpsolver)

## Detector node

Subscribe to camera info and images, detect armor plates, and publish 3D positions in the input frame (typically the camera frame at the optical center).

### DetectorNode
Armor detector node.

Includes [Detector](#detector) and [PnPSolver](#pnpsolver).

**Subscribes:**
- Camera info `/camera_info`
- Color image `/image_raw`

**Publishes:**
- Detections `/detector/armors`

**Static parameters:**
- Light bar filter `light`
  - Aspect ratio range `min/max_ratio` 
  - Max tilt `max_angle`
- Light-pair / armor filter `armor`
  - Min length ratio (short / long) `min_light_ratio `
  - Center distance range, large armor `min/max_large_center_distance`
  - Center distance range, small armor `min/max_small_center_distance`
  - Max armor tilt `max_angle`

**Dynamic parameters:**
- Publish debug output `debug`
- Target color `detect_color`
- Binarization threshold `binary_thres`
- Digit classifier `classifier`
  - Confidence threshold `threshold`

## Detector
Armor detector implementation.

### preprocessImage
Preprocessing

| ![](docs/raw.png) | ![](docs/hsv_bin.png) | ![](docs/gray_bin.png) |
| :---------------: | :-------------------: | :--------------------: |
|       Input       |   HSV thresholding   |   Grayscale threshold   |

Industrial cameras often lack dynamic range: to read the digit clearly, the bar centers blow out (R≈B). Color-only thresholding is weak here, so we threshold on grayscale and classify bar color in a later step.

### findLights
Find light bars

`findContours` + `minAreaRect` gives oriented rectangles; aspect ratio and tilt drop spurious blobs.

Bar color: sum R vs. B inside each contour; `sum_r > sum_b` → red bar, else blue.

| ![](docs/red.png) | ![](docs/blue.png) |
| :---------------: | :----------------: |
| Red bars extracted  |  Blue bars extracted  |

### matchLights
Pair light bars

Using `detect_color`, pair same-color bars: drop pairs with another bar between them, then filter by length ratio, center distance, and paired tilt to keep armor-shaped pairs.

## NumberClassifier
Digit classifier.

### extractNumbers
Digit ROI

| ![](docs/num_raw.png) | ![](docs/num_warp.png) | ![](docs/num_roi.png) | ![](docs/num_bin.png) |
| :-------------------: | :--------------------: | :-------------------: | :-------------------: |
|         Input          |     Perspective warp     |         ROI crop         |    Binarization         |

Corner points along each bar are pushed to the armor top/bottom edges, then warped; ROI is cropped. Digits are dark on bright background, so Otsu thresholding is used.

### Classify
Classification

ROI quality is high: digits stay legible across range and rotation with few pixels, so a small MLP is sufficient.

Two hidden layers plus a classification head; flattened 20×28 = 560 inputs.

Network structure:

![](docs/model.svg)

<!-- Result image: -->

<!-- ![](docs/result.png) -->

## PnPSolver
Perspective-n-point solver

[OpenCV solvePnP](https://docs.opencv.org/4.x/d5/d1f/calib3d_solvePnP.html)

Wraps `cv::solvePnP()`; pass an `Armor` to get `geometry_msgs::msg::Point` in 3D.

Armor corners are coplanar; we use `cv::SOLVEPNP_IPPE` (T. Collins and A. Bartoli, [Infinitesimal Plane-Based Pose Estimation](https://link.springer.com/article/10.1007/s11263-014-0725-5); requires coplanar object points.)
