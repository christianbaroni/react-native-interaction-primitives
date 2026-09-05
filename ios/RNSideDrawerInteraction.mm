#include "RNSideDrawerInteraction.h"

#include <UIKit/UIKit.h>

#include <algorithm>
#include <cmath>
#include <limits>

namespace {

constexpr CGFloat kDefaultSpringMass = 0.8;
constexpr CGFloat kDefaultSpringStiffness = 680;
constexpr CGFloat kDefaultSpringDamping = 46;
constexpr CGFloat kDefaultOverdrag = 4;
constexpr CGFloat kMillisecondsPerSecond = 1000;

CGFloat clamp(CGFloat value, CGFloat minimum, CGFloat maximum) noexcept
{
  return std::min(maximum, std::max(minimum, value));
}

CGFloat peakDisplacementPerVelocity(CGFloat naturalFrequency, CGFloat peakDecay) noexcept
{
  if (!std::isfinite(naturalFrequency) || naturalFrequency <= 0 ||
      !std::isfinite(peakDecay) || peakDecay < 0) {
    return 0;
  }
  return std::exp(-peakDecay - std::log(naturalFrequency));
}

rnsidedrawer::Spring makeSpring(CGFloat mass, CGFloat stiffness, CGFloat damping) noexcept
{
  const CGFloat naturalFrequencySquared = stiffness / mass;
  const CGFloat dampingRate = (damping / 2) / mass;
  const CGFloat naturalFrequency = std::sqrt(naturalFrequencySquared);
  const CGFloat tolerance =
      32 * std::numeric_limits<CGFloat>::epsilon() * std::max(dampingRate, naturalFrequency);

  if (std::abs(dampingRate - naturalFrequency) <= tolerance) {
    return {
        mass,
        stiffness,
        damping,
        naturalFrequencySquared,
        dampingRate,
        0,
        peakDisplacementPerVelocity(naturalFrequency, 1),
        rnsidedrawer::DampingType::CriticallyDamped};
  }

  const CGFloat dampingRatio = dampingRate / naturalFrequency;

  if (dampingRate < naturalFrequency) {
    const CGFloat normalizedResponse =
        std::sqrt(std::max<CGFloat>(0, (1 - dampingRatio) * (1 + dampingRatio)));
    const CGFloat responseRate = naturalFrequency * normalizedResponse;
    const CGFloat peakDecay =
        dampingRatio * std::atan2(normalizedResponse, dampingRatio) / normalizedResponse;
    return {
        mass,
        stiffness,
        damping,
        naturalFrequencySquared,
        dampingRate,
        responseRate,
        peakDisplacementPerVelocity(naturalFrequency, peakDecay),
        rnsidedrawer::DampingType::Underdamped};
  }

  const CGFloat normalizedResponse =
      std::sqrt(std::max<CGFloat>(0, dampingRatio - 1)) *
      std::sqrt(std::max<CGFloat>(0, dampingRatio + 1));
  const CGFloat responseRate = naturalFrequency * normalizedResponse;
  const CGFloat peakDecay =
      (dampingRatio / normalizedResponse) * std::acosh(dampingRatio);
  return {
      mass,
      stiffness,
      damping,
      naturalFrequencySquared,
      dampingRate,
      responseRate,
      peakDisplacementPerVelocity(naturalFrequency, peakDecay),
      rnsidedrawer::DampingType::Overdamped};
}

bool springIsRepresentable(const rnsidedrawer::Spring &spring) noexcept
{
  if (!std::isfinite(spring.mass) || spring.mass <= 0 ||
      !std::isfinite(spring.stiffness) || spring.stiffness <= 0 ||
      !std::isfinite(spring.damping) || spring.damping <= 0 ||
      !std::isfinite(spring.naturalFrequencySquared) || spring.naturalFrequencySquared <= 0 ||
      !std::isfinite(spring.dampingRate) || spring.dampingRate <= 0 ||
      !std::isfinite(spring.peakDisplacementPerVelocity) || spring.peakDisplacementPerVelocity <= 0) {
    return false;
  }
  if (spring.dampingType == rnsidedrawer::DampingType::CriticallyDamped) {
    return spring.responseRate == 0;
  }
  if (!std::isfinite(spring.responseRate) || spring.responseRate <= 0) return false;
  return spring.dampingType != rnsidedrawer::DampingType::Overdamped ||
      std::isfinite(spring.dampingRate + spring.responseRate);
}

const rnsidedrawer::Spring kDefaultSpring =
    makeSpring(kDefaultSpringMass, kDefaultSpringStiffness, kDefaultSpringDamping);

rnsidedrawer::Spring resolveSpring(CGFloat mass, CGFloat stiffness, CGFloat damping) noexcept
{
  const CGFloat resolvedMass =
      std::isfinite(mass) && mass > 0 ? mass : kDefaultSpringMass;
  const CGFloat resolvedStiffness =
      std::isfinite(stiffness) && stiffness > 0 ? stiffness : kDefaultSpringStiffness;
  const CGFloat resolvedDamping =
      std::isfinite(damping) && damping > 0 ? damping : kDefaultSpringDamping;

  const CGFloat naturalFrequencySquared = resolvedStiffness / resolvedMass;
  const CGFloat dampingRate = (resolvedDamping / 2) / resolvedMass;
  const CGFloat naturalFrequency = std::sqrt(naturalFrequencySquared);
  const CGFloat dampingRatio = dampingRate / naturalFrequency;

  if (!std::isfinite(naturalFrequencySquared) || naturalFrequencySquared <= 0 ||
      !std::isfinite(dampingRate) || dampingRate <= 0 ||
      !std::isfinite(naturalFrequency) || naturalFrequency <= 0 ||
      !std::isfinite(dampingRatio) || dampingRatio <= 0) {
    return kDefaultSpring;
  }

  const rnsidedrawer::Spring spring =
      makeSpring(resolvedMass, resolvedStiffness, resolvedDamping);
  return springIsRepresentable(spring) ? spring : kDefaultSpring;
}

} // namespace

namespace rnsidedrawer {

InteractionConfiguration defaultInteractionConfiguration() noexcept
{
  return {
      kDefaultSpringMass,
      kDefaultSpringStiffness,
      kDefaultSpringDamping,
      kDefaultOverdrag,
      0.5,
      1,
      1};
}

Interaction resolveInteraction(InteractionConfiguration configuration) noexcept
{
  return {
      resolveSpring(configuration.springMass, configuration.springStiffness, configuration.springDamping),
      configuration.overdrag,
      configuration.releaseOpenThreshold,
      configuration.releaseVelocitySensitivity,
      configuration.releaseVelocityTransfer};
}

Spring criticallyDampedSpring(const Spring &spring) noexcept
{
  if (spring.dampingType != DampingType::Overdamped) return spring;
  return makeSpring(
      spring.mass,
      spring.stiffness,
      2 * spring.mass * std::sqrt(spring.naturalFrequencySquared));
}

SpringState evaluateSpring(
    const Spring &spring,
    CGFloat initialDisplacement,
    CGFloat initialVelocity,
    CFTimeInterval elapsed) noexcept
{
  if (elapsed <= 0) return {initialDisplacement, initialVelocity};

  // Exact basis functions for x'' + 2αx' + ω₀²x = 0. Expressing the
  // solution through its unit-velocity response avoids the large opposing
  // modal coefficients that become ill-conditioned near critical damping
  // and can overflow for otherwise representable overdamped springs.
  CGFloat phaseResponse;
  CGFloat unitVelocityResponse;

  if (spring.dampingType == DampingType::Underdamped) {
    const CGFloat angle = spring.responseRate * elapsed;
    const CGFloat decay = std::exp(-spring.dampingRate * elapsed);
    const CGFloat sinc = angle == 0 ? 1 : std::sin(angle) / angle;
    phaseResponse = decay * std::cos(angle);
    unitVelocityResponse = decay * elapsed * sinc;
  } else if (spring.dampingType == DampingType::Overdamped) {
    const CGFloat slowRate =
        -spring.naturalFrequencySquared / (spring.dampingRate + spring.responseRate);
    const CGFloat slowDecay = std::exp(slowRate * elapsed);
    const CGFloat angle = spring.responseRate * elapsed;
    const CGFloat relativeFastDecay = std::exp(-2 * angle);
    phaseResponse = slowDecay * (1 + relativeFastDecay) / 2;
    unitVelocityResponse = angle == 0
        ? slowDecay * elapsed
        : slowDecay * -std::expm1(-2 * angle) / (2 * spring.responseRate);
  } else {
    const CGFloat decay = std::exp(-spring.dampingRate * elapsed);
    phaseResponse = decay;
    unitVelocityResponse = decay * elapsed;
  }

  return {
      initialDisplacement * (phaseResponse + spring.dampingRate * unitVelocityResponse) +
          initialVelocity * unitVelocityResponse,
      initialVelocity * (phaseResponse - spring.dampingRate * unitVelocityResponse) -
          spring.naturalFrequencySquared * initialDisplacement * unitVelocityResponse};
}

CGFloat limitReleaseVelocity(
    const Spring &spring,
    CGFloat velocity,
    CGFloat limitDistance) noexcept
{
  if (!std::isfinite(velocity)) return 0;

  if (velocity == 0 || !std::isfinite(limitDistance) || limitDistance <= 0 ||
      !std::isfinite(spring.peakDisplacementPerVelocity) ||
      spring.peakDisplacementPerVelocity <= 0) {
    return velocity;
  }

  const CGFloat velocityAtLimitDistance =
      limitDistance / spring.peakDisplacementPerVelocity;
  if (!std::isfinite(velocityAtLimitDistance)) return velocity;
  if (velocityAtLimitDistance == 0) return 0;

  const CGFloat normalizedVelocity = std::abs(velocity) / velocityAtLimitDistance;
  if (normalizedVelocity == 0) return velocity;

  constexpr CGFloat kCubicInputScale = 2.598076211353316;
  constexpr CGFloat kCubicOutputScale = 1.154700538379252;

  // Exact positive root of u² = s² + s⁶. Its cubic asymptote avoids
  // squaring overflow without introducing a threshold in the curve.
  const CGFloat squaredVelocity = normalizedVelocity * normalizedVelocity;
  if (squaredVelocity == 0) return velocity;
  const CGFloat scaledSquare = kCubicInputScale * squaredVelocity;
  CGFloat limitedMagnitude;
  if (std::isfinite(scaledSquare)) {
    const CGFloat normalizedLimit = std::sqrt(
        kCubicOutputScale *
        std::sinh(std::asinh(scaledSquare) / 3));
    limitedMagnitude = velocityAtLimitDistance * normalizedLimit;
  } else if (std::isfinite(normalizedVelocity)) {
    limitedMagnitude = velocityAtLimitDistance * std::cbrt(normalizedVelocity);
  } else {
    const CGFloat cubeRootScale = std::cbrt(velocityAtLimitDistance);
    limitedMagnitude = std::cbrt(std::abs(velocity)) * cubeRootScale * cubeRootScale;
  }
  return std::copysign(std::min(limitedMagnitude, std::abs(velocity)), velocity);
}

WidthChangeState remapStateForWidthChange(
    CGFloat position,
    CGFloat velocity,
    CGFloat oldWidth,
    CGFloat newWidth) noexcept
{
  CGFloat remappedPosition = position;
  if (position > oldWidth) {
    remappedPosition = newWidth + position - oldWidth;
  } else if (position >= 0 && oldWidth > 0) {
    remappedPosition = position / oldWidth * newWidth;
  }

  CGFloat velocityScale = 1;
  if (oldWidth > 0 && position >= 0 && position <= oldWidth) {
    const bool exitsThroughLowerBound = position == 0 && velocity < 0;
    const bool exitsThroughUpperBound = position == oldWidth && velocity > 0;
    if (!exitsThroughLowerBound && !exitsThroughUpperBound) {
      velocityScale = newWidth / oldWidth;
    }
  }

  const CGFloat remappedVelocity = velocity * velocityScale;
  return {
      remappedPosition,
      std::isfinite(remappedVelocity) ? remappedVelocity : 0};
}

CGFloat remapPositionForWidthChange(CGFloat position, CGFloat oldWidth, CGFloat newWidth) noexcept
{
  return remapStateForWidthChange(position, 0, oldWidth, newWidth).position;
}

CGFloat resistedPosition(
    CGFloat unconstrainedPosition,
    CGFloat lowerBound,
    CGFloat upperBound,
    CGFloat resistanceDistance) noexcept
{
  if (resistanceDistance <= 0) return clamp(unconstrainedPosition, lowerBound, upperBound);

  if (unconstrainedPosition < lowerBound) {
    return lowerBound + resistanceDistance * std::asinh((unconstrainedPosition - lowerBound) / resistanceDistance);
  }

  if (unconstrainedPosition <= upperBound) return unconstrainedPosition;

  return upperBound + resistanceDistance * std::asinh((unconstrainedPosition - upperBound) / resistanceDistance);
}

CGFloat resistedVelocity(
    CGFloat unconstrainedPosition,
    CGFloat lowerBound,
    CGFloat upperBound,
    CGFloat resistanceDistance,
    CGFloat velocity) noexcept
{
  if (!std::isfinite(velocity)) return 0;

  if (resistanceDistance <= 0) {
    if ((unconstrainedPosition <= lowerBound && velocity < 0) ||
        (unconstrainedPosition >= upperBound && velocity > 0)) {
      return 0;
    }
    return velocity;
  }

  if (unconstrainedPosition >= lowerBound && unconstrainedPosition <= upperBound) return velocity;

  const CGFloat boundary = unconstrainedPosition < lowerBound ? lowerBound : upperBound;
  const CGFloat normalizedDistance = (unconstrainedPosition - boundary) / resistanceDistance;
  return velocity / std::hypot(1, normalizedDistance);
}

bool releaseShouldOpen(
    CGFloat position,
    CGFloat velocity,
    CGFloat openPosition,
    CGFloat decelerationRate,
    CGFloat velocitySensitivity,
    CGFloat openThreshold) noexcept
{
  const CGFloat rate = std::isfinite(decelerationRate)
      ? clamp(decelerationRate, 0, 0.999999)
      : UIScrollViewDecelerationRateNormal;
  const CGFloat boundedPosition = clamp(position, 0, openPosition);
  const CGFloat scaledVelocity = velocity * velocitySensitivity;

  CGFloat projectedPosition = boundedPosition;

  if (std::isnan(scaledVelocity)) {
    projectedPosition = boundedPosition;
  } else if (std::isinf(scaledVelocity)) {
    projectedPosition = scaledVelocity;
  } else {
    projectedPosition += scaledVelocity / kMillisecondsPerSecond * rate / (1 - rate);
  }

  return clamp(projectedPosition, 0, openPosition) >= openPosition * openThreshold;
}

} // namespace rnsidedrawer
