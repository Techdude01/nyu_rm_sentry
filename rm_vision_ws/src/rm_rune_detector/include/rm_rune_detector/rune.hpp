/**
  ****************************(C) COPYRIGHT 2023 Polarbear*************************
  * @file       rune.hpp
  * @brief      Energy rune (game element) data structures
  * @note
  * @history
  *  Version    Date            Author          Modification
  *  V1.0.0     2023-12-11      Penguin         1. done
  *
  @verbatim
  =================================================================================

  =================================================================================
  @endverbatim
  ****************************(C) COPYRIGHT 2023 Polarbear*************************
  */

#ifndef RUNE_DETECTOR__ARMOR_HPP_
#define RUNE_DETECTOR__ARMOR_HPP_

#include <opencv2/core.hpp>

// STL
#include <string>

/**
 * @brief Namespace for rune-detection structs and enums
 */
namespace rm_rune_detector
{

    /**
     * @brief Target activation state
     */
    enum class TargetType
    {
        DISACTIVED, /* Inactive target */
        ACTIVED,    /* Active target */
        INVALID     /* Invalid target */
    };

    const int RED = 0;  /* Red alliance */
    const int BLUE = 1; /* Blue alliance */

    const std::string ARMOR_TYPE_STR[3] = {"disactived", "actived", "invalid"}; /* String labels for TargetType */

    /**
     * @brief Ellipse for rune detection; extends cv::RotatedRect
     */
    struct Ellipse : public cv::RotatedRect
    {
        /**
         * @brief Default constructor
         */
        Ellipse() = default;

        /**
         * @brief Build ellipse from a rotated rectangle
         * @param box Source rotated rect
         */
        explicit Ellipse(cv::RotatedRect box) : cv::RotatedRect(box)
        {
            // Major and minor axis lengths
            major_axis = std::max(box.size.width, box.size.height);
            minor_axis = std::min(box.size.width, box.size.height);
        }

        float major_axis; /* Major axis length */
        float minor_axis; /* Minor axis length */
        int color;        /* Bar / ellipse color id */
    };

    /**
     * @brief Rune target (one strike plate)
     */
    struct Target
    {
        /**
         * @brief Default constructor
         */
        Target() = default;

        /**
         * @brief Construct from an ellipse
         * @param ellipse Fitted ellipse
         */
        Target(Ellipse &ellipse)
        {
            target_ellipse = ellipse;
        }

        Ellipse target_ellipse; /* Fitted ellipse */
        TargetType type;        /* Activation state */
    };
} // namespace rm_rune_detector

#endif // RUNE_DETECTOR__ARMOR_HPP_