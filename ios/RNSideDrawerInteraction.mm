#import "RNSideDrawerInteraction.h"

#import <UIKit/UIKit.h>

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
        rnsidedrawer::DampingType::CriticallyDamped};
  }

  if (dampingRate < naturalFrequency) {
    const CGFloat ratio = dampingRate / naturalFrequency;
    return {
        mass,
        stiffness,
        damping,
        naturalFrequencySquared,
        dampingRate,
        naturalFrequency * std::sqrt(std::max<CGFloat>(0, 1 - ratio * ratio)),
        rnsidedrawer::DampingType::Underdamped};
  }

  const CGFloat ratio = naturalFrequency / dampingRate;
  return {
      mass,
      stiffness,
      damping,
      naturalFrequencySquared,
      dampingRate,
      dampingRate * std::sqrt(std::max<CGFloat>(0, 1 - ratio * ratio)),
      rnsidedrawer::DampingType::Overdamped};
}

const rnsidedrawer::Spring kDefaultSpring =
    makeSpring(kDefaultSpringMass, kDefaultSpringStiffness, kDefaultSpringDamping);

rnsidedrawer::Spring resolveSpring(CGFloat mass, CGFloat stiffness, CGFloat damping) noexcept
{
  if (!std::isfinite(mass) || mass <= 0 || !std::isfinite(stiffness) || stiffness <= 0 ||
      !std::isfinite(damping) || damping <= 0) {
    return kDefaultSpring;
  }

  const CGFloat naturalFrequencySquared = stiffness / mass;
  const CGFloat dampingRate = (damping / 2) / mass;

  if (!std::isfinite(naturalFrequencySquared) || naturalFrequencySquared <= 0 ||
      !std::isfinite(dampingRate) || dampingRate <= 0) {
    return kDefaultSpring;
  }

  return makeSpring(mass, stiffness, damping);
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

SpringState evaluateSpring(
    const Spring &spring,
    CGFloat initialDisplacement,
    CGFloat initialVelocity,
    CFTimeInterval elapsed) noexcept
{
  if (elapsed <= 0) return {initialDisplacement, initialVelocity};

  if (spring.dampingType == DampingType::Underdamped) {
    const CGFloat angularFrequency = spring.responseRate;
    const CGFloat sineCoefficient =
        (initialVelocity + spring.dampingRate * initialDisplacement) / angularFrequency;
    const CGFloat angle = angularFrequency * elapsed;
    const CGFloat decay = std::exp(-spring.dampingRate * elapsed);
    const CGFloat oscillation =
        initialDisplacement * std::cos(angle) + sineCoefficient * std::sin(angle);
    const CGFloat oscillationVelocity =
        -initialDisplacement * angularFrequency * std::sin(angle) +
        sineCoefficient * angularFrequency * std::cos(angle);
    return {
        decay * oscillation,
        decay * (oscillationVelocity - spring.dampingRate * oscillation)};
  }

  if (spring.dampingType == DampingType::Overdamped) {
    const CGFloat slowRate =
        -spring.naturalFrequencySquared / (spring.dampingRate + spring.responseRate);
    const CGFloat fastRate = -(spring.dampingRate + spring.responseRate);
    const CGFloat slowCoefficient =
        (initialVelocity - fastRate * initialDisplacement) / (slowRate - fastRate);
    const CGFloat fastCoefficient = initialDisplacement - slowCoefficient;
    const CGFloat slowDecay = std::exp(slowRate * elapsed);
    const CGFloat fastDecay = std::exp(fastRate * elapsed);
    return {
        slowCoefficient * slowDecay + fastCoefficient * fastDecay,
        slowRate * slowCoefficient * slowDecay + fastRate * fastCoefficient * fastDecay};
  }

  const CGFloat coefficient = initialVelocity + spring.dampingRate * initialDisplacement;
  const CGFloat decay = std::exp(-spring.dampingRate * elapsed);

  return {
      (initialDisplacement + coefficient * elapsed) * decay,
      (initialVelocity - spring.dampingRate * coefficient * elapsed) * decay};
}

CGFloat remapPositionForWidthChange(CGFloat position, CGFloat oldWidth, CGFloat newWidth) noexcept
{
  if (position < 0) return position;
  if (position > oldWidth) return newWidth + position - oldWidth;
  return oldWidth > 0 ? position / oldWidth * newWidth : position;
}

CGFloat resistedPosition(
    CGFloat unconstrainedPosition,
    CGFloat lowerBound,
    CGFloat upperBound,
    CGFloat maximumOverdrag) noexcept
{
  if (maximumOverdrag <= 0) return clamp(unconstrainedPosition, lowerBound, upperBound);
  if (unconstrainedPosition < lowerBound) {
    return lowerBound + maximumOverdrag * std::tanh((unconstrainedPosition - lowerBound) / maximumOverdrag);
  }
  if (unconstrainedPosition <= upperBound) return unconstrainedPosition;
  return upperBound + maximumOverdrag * std::tanh((unconstrainedPosition - upperBound) / maximumOverdrag);
}

CGFloat resistedVelocity(
    CGFloat unconstrainedPosition,
    CGFloat lowerBound,
    CGFloat upperBound,
    CGFloat maximumOverdrag,
    CGFloat velocity) noexcept
{
  if (!std::isfinite(velocity)) return 0;

  if (maximumOverdrag <= 0) {
    if ((unconstrainedPosition <= lowerBound && velocity < 0) ||
        (unconstrainedPosition >= upperBound && velocity > 0)) {
      return 0;
    }
    return velocity;
  }

  if (unconstrainedPosition >= lowerBound && unconstrainedPosition <= upperBound) return velocity;

  const CGFloat boundary = unconstrainedPosition < lowerBound ? lowerBound : upperBound;
  const CGFloat normalizedDistance = std::tanh((unconstrainedPosition - boundary) / maximumOverdrag);
  return velocity * (1 - normalizedDistance * normalizedDistance);
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
