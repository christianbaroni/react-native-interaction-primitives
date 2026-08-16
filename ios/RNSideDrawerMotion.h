#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

#include <algorithm>
#include <array>
#include <cstddef>
#include <vector>

namespace rnsidedrawer {

enum class MotionChannel : std::size_t {
  DrawerOpacity,
  DrawerScale,
  DrawerTranslationX,
  DrawerTranslationY,
  ContentOpacity,
  ContentScale,
  ContentTranslationX,
  ContentTranslationY,
  OverlayOpacity,
  ContentBorderOpacity,
  ContentShadowOpacity,
  Count,
};

class Motion final {
 public:
  CGFloat evaluate(MotionChannel channel, CGFloat progress, CGFloat fallback) const noexcept
  {
    return interpolations_[static_cast<std::size_t>(channel)].evaluate(progress, fallback);
  }

  bool hasInterpolations() const noexcept
  {
    return hasInterpolations_;
  }

 private:
  struct Segment {
    CGFloat upperInput;
    CGFloat slope;
    CGFloat intercept;
  };

  struct Interpolation {
    CGFloat firstInput{0};
    CGFloat firstOutput{0};
    CGFloat lastInput{0};
    CGFloat lastOutput{0};
    std::vector<Segment> segments;

    CGFloat evaluate(CGFloat progress, CGFloat fallback) const noexcept
    {
      if (segments.empty()) return fallback;
      if (progress <= firstInput) return firstOutput;
      if (progress >= lastInput) return lastOutput;

      const auto segment = std::lower_bound(
          segments.begin(),
          segments.end(),
          progress,
          [](const Segment &candidate, CGFloat value) {
            return candidate.upperInput < value;
          });
      return segment->slope * progress + segment->intercept;
    }
  };

  static constexpr std::size_t kChannelCount = static_cast<std::size_t>(MotionChannel::Count);
  std::array<Interpolation, kChannelCount> interpolations_;
  bool hasInterpolations_{false};

  friend Motion compileMotion(NSArray<NSNumber *> *configuration);
};

Motion compileMotion(NSArray<NSNumber *> *configuration);

} // namespace rnsidedrawer
