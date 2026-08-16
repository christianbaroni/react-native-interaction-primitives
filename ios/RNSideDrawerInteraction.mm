#import "RNSideDrawerInteraction.h"

#import <UIKit/UIKit.h>

#include <algorithm>
#include <cmath>
#include <limits>

namespace {

constexpr CGFloat kDefaultSpringMass = 1;
constexpr CGFloat kDefaultSpringStiffness = 49 * M_PI * M_PI;
constexpr CGFloat kDefaultSpringDamping = 14 * M_PI;
constexpr CGFloat kDefaultOverdrag = 4;
constexpr CGFloat kMillisecondsPerSecond = 1000;

CGFloat clamp(CGFloat value, CGFloat minimum, CGFloat maximum) noexcept
{
  return std::min(maximum, std::max(minimum, value));
}

rnsidedrawer::Spring resolveSpring(CGFloat mass, CGFloat stiffness, CGFloat damping) noexcept
{
  const rnsidedrawer::Spring defaultSpring = {
      kDefaultSpringMass,
      kDefaultSpringStiffness,
      kDefaultSpringDamping,
      kDefaultSpringStiffness / kDefaultSpringMass,
      kDefaultSpringDamping / (2 * kDefaultSpringMass),
      0,
      rnsidedrawer::DampingType::CriticallyDamped};
  if (!std::isfinite(mass) || mass <= 0 || !std::isfinite(stiffness) || stiffness <= 0 ||
      !std::isfinite(damping) || damping <= 0) {
    return defaultSpring;
  }

  const CGFloat naturalFrequencySquared = stiffness / mass;
  const CGFloat dampingRate = damping / (2 * mass);
  if (!std::isfinite(naturalFrequencySquared) || naturalFrequencySquared <= 0 ||
      !std::isfinite(dampingRate) || dampingRate <= 0) {
    return defaultSpring;
  }

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

CGFloat outwardDistanceAtTime(
    const rnsidedrawer::Spring &spring,
    CGFloat displacement,
    CGFloat velocity,
    CFTimeInterval time,
    CGFloat outwardDirection) noexcept
{
  if (time <= 0 || !std::isfinite(time)) return 0;
  const rnsidedrawer::SpringState state =
      rnsidedrawer::evaluateSpring(spring, displacement, velocity, time);
  return std::isfinite(state.displacement)
      ? outwardDirection * state.displacement
      : std::numeric_limits<CGFloat>::infinity();
}

CGFloat maximumOutwardDistance(
    CGFloat position,
    CGFloat velocity,
    CGFloat target,
    const rnsidedrawer::Spring &spring) noexcept
{
  const CGFloat outwardDirection = target > 0 ? 1 : -1;
  const CGFloat displacement = position - target;
  CGFloat maximumDistance = std::max<CGFloat>(0, outwardDirection * displacement);

  if (spring.dampingType == rnsidedrawer::DampingType::Underdamped) {
    const CGFloat angularFrequency = spring.responseRate;
    const CGFloat sineCoefficient =
        -(spring.dampingRate * velocity + spring.naturalFrequencySquared * displacement) / angularFrequency;
    const CGFloat phase = std::atan2(velocity, sineCoefficient);
    const CGFloat rootIndex = std::floor(phase / M_PI) + 1;
    const CFTimeInterval firstExtremum = (rootIndex * M_PI - phase) / angularFrequency;
    maximumDistance = std::max(
        maximumDistance,
        outwardDistanceAtTime(spring, displacement, velocity, firstExtremum, outwardDirection));
    maximumDistance = std::max(
        maximumDistance,
        outwardDistanceAtTime(
            spring,
            displacement,
            velocity,
            firstExtremum + M_PI / angularFrequency,
            outwardDirection));
    return std::max<CGFloat>(0, maximumDistance);
  }

  if (spring.dampingType == rnsidedrawer::DampingType::Overdamped) {
    const CGFloat slowRate =
        -spring.naturalFrequencySquared / (spring.dampingRate + spring.responseRate);
    const CGFloat fastRate = -(spring.dampingRate + spring.responseRate);
    const CGFloat slowCoefficient = (velocity - fastRate * displacement) / (slowRate - fastRate);
    const CGFloat fastCoefficient = displacement - slowCoefficient;
    const CGFloat denominator = slowRate * slowCoefficient;
    if (denominator != 0 && std::isfinite(denominator)) {
      const CGFloat ratio = -(fastRate * fastCoefficient) / denominator;
      if (ratio > 0 && std::isfinite(ratio)) {
        maximumDistance = std::max(
            maximumDistance,
            outwardDistanceAtTime(
                spring,
                displacement,
                velocity,
                std::log(ratio) / (slowRate - fastRate),
                outwardDirection));
      }
    }
    return std::max<CGFloat>(0, maximumDistance);
  }

  const CGFloat coefficient = velocity + spring.dampingRate * displacement;
  const CGFloat denominator = spring.dampingRate * coefficient;
  if (denominator != 0 && std::isfinite(denominator)) {
    maximumDistance = std::max(
        maximumDistance,
        outwardDistanceAtTime(
            spring, displacement, velocity, velocity / denominator, outwardDirection));
  }
  return std::max<CGFloat>(0, maximumDistance);
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
  CGFloat projectedPosition = boundedPosition;
  const CGFloat scaledVelocity = velocity * velocitySensitivity;
  if (std::isnan(scaledVelocity)) {
    projectedPosition = boundedPosition;
  } else if (std::isinf(scaledVelocity)) {
    projectedPosition = scaledVelocity;
  } else {
    projectedPosition += scaledVelocity / kMillisecondsPerSecond * rate / (1 - rate);
  }
  return clamp(projectedPosition, 0, openPosition) >= openPosition * openThreshold;
}

CGFloat limitReleaseVelocity(
    CGFloat position,
    CGFloat velocity,
    CGFloat target,
    const Spring &spring,
    CGFloat maximumOverdrag) noexcept
{
  const CGFloat outwardDirection = target > 0 ? 1 : -1;
  const CGFloat currentDistance = std::max<CGFloat>(0, outwardDirection * (position - target));
  const CGFloat naturalDistance = maximumOutwardDistance(position, 0, target, spring);
  const CGFloat allowedDistance = std::max(maximumOverdrag, std::max(currentDistance, naturalDistance));
  if (velocity == 0) return 0;
  if (std::isfinite(velocity) && maximumOutwardDistance(position, velocity, target, spring) <= allowedDistance) {
    return velocity;
  }

  const CGFloat direction = velocity < 0 ? -1 : 1;
  const CGFloat requestedMagnitude = std::abs(velocity);
  const CGFloat estimate = spring.dampingRate * std::max<CGFloat>(allowedDistance, 1);
  CGFloat upperMagnitude =
      std::isfinite(estimate) ? std::max<CGFloat>(1, std::min(requestedMagnitude, estimate)) : 1;
  CGFloat lowerMagnitude = 0;
  while (true) {
    const CGFloat distance = maximumOutwardDistance(position, direction * upperMagnitude, target, spring);
    if (!std::isfinite(distance) || distance > allowedDistance) break;
    if (upperMagnitude >= requestedMagnitude) return velocity;
    lowerMagnitude = upperMagnitude;
    upperMagnitude = std::min(requestedMagnitude, upperMagnitude * 2);
  }

  for (int iteration = 0; iteration < 40; iteration += 1) {
    const CGFloat candidateMagnitude = lowerMagnitude + (upperMagnitude - lowerMagnitude) * 0.5;
    const CGFloat distance = maximumOutwardDistance(position, direction * candidateMagnitude, target, spring);
    if (!std::isfinite(distance) || distance > allowedDistance) {
      upperMagnitude = candidateMagnitude;
    } else {
      lowerMagnitude = candidateMagnitude;
    }
  }
  return direction * lowerMagnitude;
}

} // namespace rnsidedrawer
