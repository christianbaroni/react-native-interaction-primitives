#import <CoreGraphics/CoreGraphics.h>

namespace rnsidedrawer {

enum class DampingType {
  Underdamped,
  CriticallyDamped,
  Overdamped,
};

struct Spring {
  CGFloat mass;
  CGFloat stiffness;
  CGFloat damping;
  CGFloat naturalFrequencySquared;
  CGFloat dampingRate;
  CGFloat responseRate;
  DampingType dampingType;
};

struct InteractionConfiguration {
  CGFloat springMass;
  CGFloat springStiffness;
  CGFloat springDamping;
  CGFloat overdrag;
  CGFloat releaseOpenThreshold;
  CGFloat releaseVelocitySensitivity;
  CGFloat releaseVelocityTransfer;
};

struct Interaction {
  Spring spring;
  CGFloat overdrag;
  CGFloat releaseOpenThreshold;
  CGFloat releaseVelocitySensitivity;
  CGFloat releaseVelocityTransfer;
};

struct SpringState {
  CGFloat displacement;
  CGFloat velocity;
};

InteractionConfiguration defaultInteractionConfiguration() noexcept;
Interaction resolveInteraction(InteractionConfiguration configuration) noexcept;

SpringState evaluateSpring(
    const Spring &spring,
    CGFloat initialDisplacement,
    CGFloat initialVelocity,
    CFTimeInterval elapsed) noexcept;

CGFloat remapPositionForWidthChange(CGFloat position, CGFloat oldWidth, CGFloat newWidth) noexcept;

CGFloat resistedPosition(
    CGFloat unconstrainedPosition,
    CGFloat lowerBound,
    CGFloat upperBound,
    CGFloat maximumOverdrag) noexcept;

CGFloat resistedVelocity(
    CGFloat unconstrainedPosition,
    CGFloat lowerBound,
    CGFloat upperBound,
    CGFloat maximumOverdrag,
    CGFloat velocity) noexcept;

bool releaseShouldOpen(
    CGFloat position,
    CGFloat velocity,
    CGFloat openPosition,
    CGFloat decelerationRate,
    CGFloat velocitySensitivity,
    CGFloat openThreshold) noexcept;

} // namespace rnsidedrawer
