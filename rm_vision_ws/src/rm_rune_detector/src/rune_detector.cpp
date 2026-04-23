/**
  ****************************(C) COPYRIGHT 2023 Polarbear*************************
  * @file       rune_detector.cpp
  * @brief      Energy rune detector: finds rune strike plates in images
  * @note
  * @history
  *  Version    Date            Author          Modification
  *  V1.0.0     2023-12-11      Penguin         
  *
  @verbatim
  =================================================================================

  =================================================================================
  @endverbatim
  ****************************(C) COPYRIGHT 2023 Polarbear*************************
  */
// OpenCV
#include <opencv2/core.hpp>
#include <opencv2/core/base.hpp>
#include <opencv2/core/mat.hpp>
#include <opencv2/core/types.hpp>
#include <opencv2/imgproc.hpp>

// STD
#include <algorithm>
#include <cmath>
#include <vector>

#include "rm_rune_detector/rune_detector.hpp"
#include "rm_rune_detector/rune.hpp"

namespace rm_rune_detector
{
    /**
     * @brief Construct RuneDetector
     * @param bin_thres Grayscale binarization threshold
     * @param color Target color id
     * @param t Target geometry thresholds
     * @param hsv Red / blue HSV thresholds
     */
    RuneDetector::RuneDetector(const int &bin_thres, const int &color, const TargetParams &t, const HSVParams &hsv)
        : binary_thres(bin_thres), detect_color(color), t(t), hsv(hsv)
    {
    }

    /**
     * @brief Run detection on the input image
     * @param input BGR or RGB image (per pipeline)
     * @return Detected rune targets
     */
    std::vector<Target> RuneDetector::Detect(const cv::Mat &input)
    {
        // TODO: detect rune plates and classify activation state
        binary_img = PreprocessImage(input);
        std::vector<Target> res_tmp;
        targets_ = res_tmp;
        return targets_;
    }

    /**
     * @brief Preprocess input image
     * @param rgb_img Input image
     */
    cv::Mat RuneDetector::PreprocessImage(const cv::Mat &rgb_img)
    {
        cv::Mat gray_img;
        cv::cvtColor(rgb_img, gray_img, cv::COLOR_RGB2GRAY);

        cv::Mat binary_img;
        cv::threshold(gray_img, binary_img, binary_thres, 255, cv::THRESH_BINARY);

        return binary_img;
    }

    /**
     * @brief Find candidate targets in the image
     * @param rbg_img RGB image
     * @param binary_img Binarized image
     * @return Candidate ellipses / targets
     */
    std::vector<Ellipse> RuneDetector::FindPossibleTargets(const cv::Mat &rbg_img, const cv::Mat &binary_img)
    {
        using std::vector;
        vector<vector<cv::Point>> contours;
        vector<cv::Vec4i> hierarchy;
        cv::findContours(binary_img, contours, hierarchy, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);

        return vector<Ellipse>();
    }
} // namespace rm_rune_detector
