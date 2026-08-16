#import "RNSideDrawerMotion.h"

#include <cmath>

namespace rnsidedrawer {

Motion compileMotion(NSArray<NSNumber *> *configuration)
{
  Motion motion;
  const std::size_t channelCount = static_cast<std::size_t>(MotionChannel::Count);
  if (configuration.count < channelCount) return motion;

  std::size_t cursor = channelCount;
  for (std::size_t channelIndex = 0; channelIndex < channelCount; channelIndex += 1) {
    const double rawPointCount = configuration[channelIndex].doubleValue;
    if (!std::isfinite(rawPointCount) || rawPointCount < 0 || rawPointCount > configuration.count) return {};

    const std::size_t pointCount = static_cast<std::size_t>(rawPointCount);
    if (rawPointCount != pointCount || pointCount == 1 || pointCount > (configuration.count - cursor) / 2) {
      return {};
    }
    if (pointCount == 0) continue;

    motion.hasInterpolations_ = true;
    Motion::Interpolation &interpolation = motion.interpolations_[channelIndex];
    interpolation.firstInput = configuration[cursor].doubleValue;
    interpolation.firstOutput = configuration[cursor + 1].doubleValue;
    interpolation.lastInput = interpolation.firstInput;
    interpolation.lastOutput = interpolation.firstOutput;
    if (!std::isfinite(interpolation.firstInput) || !std::isfinite(interpolation.firstOutput) ||
        interpolation.firstInput < 0 || interpolation.firstInput > 1) {
      return {};
    }

    CGFloat previousInput = interpolation.firstInput;
    CGFloat previousOutput = interpolation.firstOutput;
    cursor += 2;
    interpolation.segments.reserve(pointCount - 1);
    for (std::size_t pointIndex = 1; pointIndex < pointCount; pointIndex += 1) {
      const CGFloat input = configuration[cursor].doubleValue;
      const CGFloat output = configuration[cursor + 1].doubleValue;
      if (!std::isfinite(input) || !std::isfinite(output) || input <= previousInput || input > 1) return {};

      const CGFloat slope = (output - previousOutput) / (input - previousInput);
      interpolation.segments.push_back({input, slope, previousOutput - slope * previousInput});
      interpolation.lastInput = input;
      interpolation.lastOutput = output;
      previousInput = input;
      previousOutput = output;
      cursor += 2;
    }
  }
  return cursor == configuration.count ? motion : Motion{};
}

} // namespace rnsidedrawer
