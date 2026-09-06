#include "RNSideDrawerInteraction.h"

#include <algorithm>
#include <array>
#include <cassert>
#include <cmath>
#include <iomanip>
#include <iostream>
#include <limits>

namespace {

using rnsidedrawer::DampingType;
using rnsidedrawer::InteractionConfiguration;
using rnsidedrawer::Spring;
using rnsidedrawer::SpringState;

constexpr double kRelativeTolerance = 2e-11;
constexpr double kAbsoluteTolerance = 2e-11;

bool nearlyEqual(double actual, double expected, double relative = kRelativeTolerance, double absolute = kAbsoluteTolerance)
{
  if (!std::isfinite(actual) || !std::isfinite(expected)) return false;
  const double scale = std::max({1.0, std::abs(actual), std::abs(expected)});
  return std::abs(actual - expected) <= std::max(absolute, relative * scale);
}

void requireNear(double actual, double expected, double relative = kRelativeTolerance, double absolute = kAbsoluteTolerance)
{
  if (!nearlyEqual(actual, expected, relative, absolute)) {
    std::cerr << std::setprecision(17) << "Expected " << expected << ", got " << actual << std::endl;
    std::abort();
  }
}

Spring resolveSpring(double mass, double stiffness, double damping)
{
  InteractionConfiguration configuration = rnsidedrawer::defaultInteractionConfiguration();
  configuration.springMass = mass;
  configuration.springStiffness = stiffness;
  configuration.springDamping = damping;
  return rnsidedrawer::resolveInteraction(configuration).spring;
}

void verifyGoldenStates()
{
  struct Case {
    Spring spring;
    double displacement;
    double velocity;
    double elapsed;
    double expectedDisplacement;
    double expectedVelocity;
  };

  const std::array<Case, 5> cases = {{
      {resolveSpring(0.8, 680, 46), -320, 0, 0.1, -65.87757877044565, 1475.2753861570177},
      {resolveSpring(0.8, 680, 46), -320, 0, 0.2, -5.560439749842255, 147.32983655837184},
      {resolveSpring(1, 100, 5), 10, -20, 0.37, -3.6734629900593335, 23.775980595041943},
      {resolveSpring(1, 100, 20), 10, -20, 0.37, 0.9790516482254399, -7.812634364627248},
      {resolveSpring(1, 100, 30), 10, -20, 0.37, 2.631430194700746, -10.05003890074222},
  }};

  for (const Case &testCase : cases) {
    const SpringState state = rnsidedrawer::evaluateSpring(
        testCase.spring,
        testCase.displacement,
        testCase.velocity,
        testCase.elapsed);
    requireNear(state.displacement, testCase.expectedDisplacement);
    requireNear(state.velocity, testCase.expectedVelocity);
  }
}

void verifyInitialConditionsAndSemigroup()
{
  const std::array<Spring, 3> springs = {
      resolveSpring(1, 100, 5),
      resolveSpring(1, 100, 20),
      resolveSpring(1, 100, 30),
  };

  for (const Spring &spring : springs) {
    const SpringState initial = rnsidedrawer::evaluateSpring(spring, 17.5, -43.25, 0);
    requireNear(initial.displacement, 17.5);
    requireNear(initial.velocity, -43.25);

    const SpringState first = rnsidedrawer::evaluateSpring(spring, 17.5, -43.25, 0.173);
    const SpringState restarted = rnsidedrawer::evaluateSpring(spring, first.displacement, first.velocity, 0.281);
    const SpringState direct = rnsidedrawer::evaluateSpring(spring, 17.5, -43.25, 0.454);
    requireNear(restarted.displacement, direct.displacement, 8e-11, 8e-11);
    requireNear(restarted.velocity, direct.velocity, 8e-11, 8e-11);
  }
}

void verifyNearCriticalContinuity()
{
  const Spring critical = resolveSpring(1, 100, 20);
  const Spring below = resolveSpring(1, 100, 20 * (1 - 1e-8));
  const Spring above = resolveSpring(1, 100, 20 * (1 + 1e-8));

  assert(critical.dampingType == DampingType::CriticallyDamped);
  assert(below.dampingType == DampingType::Underdamped);
  assert(above.dampingType == DampingType::Overdamped);
  assert(std::isfinite(below.peakDisplacementPerVelocity));
  assert(std::isfinite(above.peakDisplacementPerVelocity));
  requireNear(below.peakDisplacementPerVelocity, critical.peakDisplacementPerVelocity, 1e-7, 1e-13);
  requireNear(above.peakDisplacementPerVelocity, critical.peakDisplacementPerVelocity, 1e-7, 1e-13);

  for (double elapsed : {0.001, 0.1, 0.5}) {
    const SpringState criticalState = rnsidedrawer::evaluateSpring(critical, 83, -127, elapsed);
    const SpringState belowState = rnsidedrawer::evaluateSpring(below, 83, -127, elapsed);
    const SpringState aboveState = rnsidedrawer::evaluateSpring(above, 83, -127, elapsed);
    requireNear(belowState.displacement, criticalState.displacement, 3e-7, 3e-9);
    requireNear(aboveState.displacement, criticalState.displacement, 3e-7, 3e-9);
    requireNear(belowState.velocity, criticalState.velocity, 3e-7, 3e-9);
    requireNear(aboveState.velocity, criticalState.velocity, 3e-7, 3e-9);
  }

  constexpr double offset = 1e-12;
  const Spring veryNearBelow = resolveSpring(1, 100, 20 * (1 - offset));
  const Spring veryNearAbove = resolveSpring(1, 100, 20 * (1 + offset));
  const double belowRatio = veryNearBelow.dampingRate / 10;
  const double aboveRatio = veryNearAbove.dampingRate / 10;
  requireNear(
      veryNearBelow.responseRate,
      10 * std::sqrt((1 - belowRatio) * (1 + belowRatio)),
      2e-12,
      2e-18);
  requireNear(
      veryNearAbove.responseRate,
      10 * std::sqrt(aboveRatio - 1) * std::sqrt(aboveRatio + 1),
      2e-12,
      2e-18);
}

void verifySpringRepresentation()
{
  const Spring accepted = resolveSpring(1, 4, 2);
  requireNear(accepted.mass, 1);
  requireNear(accepted.stiffness, 4);
  requireNear(accepted.damping, 2);

  const Spring partiallyDefaulted = resolveSpring(-1, 100, 20);
  requireNear(partiallyDefaulted.mass, 0.8);
  requireNear(partiallyDefaulted.stiffness, 100);
  requireNear(partiallyDefaulted.damping, 20);

  const Spring slowTail = resolveSpring(1, 100, 200);
  requireNear(slowTail.mass, 1);
  requireNear(slowTail.stiffness, 100);
  requireNear(slowTail.damping, 200);

  const Spring extremeOverdamping = resolveSpring(1, 1, 2e9);
  requireNear(extremeOverdamping.mass, 1);
  requireNear(extremeOverdamping.stiffness, 1);
  requireNear(extremeOverdamping.damping, 2e9);
  requireNear(extremeOverdamping.peakDisplacementPerVelocity, 5e-10, 1e-9, 1e-18);

  const Spring quotientConditioned = resolveSpring(1, 1, 2e307);
  requireNear(quotientConditioned.damping, 2e307);
  assert(std::isfinite(quotientConditioned.peakDisplacementPerVelocity));
  assert(quotientConditioned.peakDisplacementPerVelocity > 0);
  const SpringState quotientConditionedState =
      rnsidedrawer::evaluateSpring(quotientConditioned, 320, 10'000, 1.0 / 120);
  assert(std::isfinite(quotientConditionedState.displacement));
  assert(std::isfinite(quotientConditionedState.velocity));

  const Spring overflow = resolveSpring(1e-300, 1e300, 1);
  requireNear(overflow.mass, 0.8);
  requireNear(overflow.stiffness, 680);
  requireNear(overflow.damping, 46);
}

void verifyExtremeSpringTransfer()
{
  struct Case {
    double damping;
    SpringState restoring;
    SpringState velocityOnly;
  };
  // Modal solutions evaluated at 800-digit precision from the admitted double inputs.
  const std::array<Case, 2> cases = {{
      {1e307, {-294.41421268138345, 2944.1421268138342}, {9.200444146293232e-288, -9.200444146293233e-287}},
      {1.7e307, {-304.691987092261, 1792.305806425065}, {5.600955645078327e-288, -3.2946797912225456e-287}},
  }};
  for (const Case &testCase : cases) {
    const Spring spring = resolveSpring(1, 1e308, testCase.damping);
    requireNear(spring.stiffness, 1e308);
    requireNear(spring.damping, testCase.damping);
    const SpringState restoring = rnsidedrawer::evaluateSpring(spring, -320, 0, 1.0 / 120);
    requireNear(restoring.displacement, testCase.restoring.displacement);
    requireNear(restoring.velocity, testCase.restoring.velocity);
    const SpringState velocityOnly = rnsidedrawer::evaluateSpring(spring, 0, 1e20, 1.0 / 120);
    requireNear(velocityOnly.displacement / testCase.velocityOnly.displacement, 1);
    requireNear(velocityOnly.velocity / testCase.velocityOnly.velocity, 1);

    for (SpringState initial : {SpringState{-320, 0}, SpringState{0, 1e20}, SpringState{320, -1e20}}) {
      const SpringState direct = rnsidedrawer::evaluateSpring(spring, initial.displacement, initial.velocity, 1.0 / 120);
      const SpringState opposite = rnsidedrawer::evaluateSpring(spring, -initial.displacement, -initial.velocity, 1.0 / 120);
      requireNear(opposite.displacement / -direct.displacement, 1);
      requireNear(opposite.velocity / -direct.velocity, 1);
      const SpringState first = rnsidedrawer::evaluateSpring(spring, initial.displacement, initial.velocity, 1.0 / 360);
      const SpringState resumed = rnsidedrawer::evaluateSpring(spring, first.displacement, first.velocity, 1.0 / 180);
      requireNear(resumed.displacement / direct.displacement, 1);
      requireNear(resumed.velocity / direct.velocity, 1);
    }
  }
  const SpringState settled = rnsidedrawer::evaluateSpring(resolveSpring(1, 1e308, 2e154), -320, 0, 1.0 / 120);
  assert(settled.displacement == 0 && settled.velocity == 0);
}

void verifySpringScaleEquivalence()
{
  for (double stiffness : {1e-308, 1e-150, 1.0, 1e150, 1e308}) {
    const double frequency = std::sqrt(stiffness);
    for (double dampingRatio : {0.1, 1.0, 10.0}) {
      const Spring spring = resolveSpring(1, stiffness, 2 * dampingRatio * frequency);
      const Spring normalizedSpring = resolveSpring(1, 1, 2 * dampingRatio);
      for (double normalizedTime : {0.01, 0.1, 1.0, 10.0, 100.0}) {
        const SpringState actual = rnsidedrawer::evaluateSpring(spring, -320, 23 * frequency, normalizedTime / frequency);
        const SpringState expected = rnsidedrawer::evaluateSpring(normalizedSpring, -320, 23, normalizedTime);
        requireNear(actual.displacement, expected.displacement);
        requireNear(actual.velocity / frequency, expected.velocity);
      }
    }
  }
}

void verifyReleaseVelocityLimit()
{
  constexpr double limitDistance = 32;
  const std::array<Spring, 3> springs = {
      resolveSpring(1, 180, 7),
      resolveSpring(0.8, 680, 46),
      resolveSpring(1, 225, 42),
  };
  const std::array<double, 5> velocities = {1, 500, 2500, 10000, 1e8};

  for (const Spring &spring : springs) {
    double previousMagnitude = 0;
    for (double velocity : velocities) {
      const double limited = rnsidedrawer::limitReleaseVelocity(spring, velocity, limitDistance);
      const double limitedNegative = rnsidedrawer::limitReleaseVelocity(spring, -velocity, limitDistance);
      requireNear(limitedNegative, -limited, 2e-12, 2e-12);
      assert(std::abs(limited) >= previousMagnitude);
      assert(std::abs(limited) <= velocity);
      previousMagnitude = std::abs(limited);

      const double inputDistance =
          std::abs(spring.peakDisplacementPerVelocity * velocity) / limitDistance;
      const double limitedDistance =
          std::abs(spring.peakDisplacementPerVelocity * limited) / limitDistance;
      requireNear(
          inputDistance * inputDistance,
          limitedDistance * limitedDistance + std::pow(limitedDistance, 6),
          3e-10,
          3e-12);
    }

    const double velocityAtLimitDistance =
        limitDistance / spring.peakDisplacementPerVelocity;
    const double ordinaryVelocity = 0.01 * velocityAtLimitDistance;
    assert(rnsidedrawer::limitReleaseVelocity(spring, ordinaryVelocity, limitDistance) /
        ordinaryVelocity > 0.99999999);
    const double extremeVelocity = 1000 * velocityAtLimitDistance;
    const double doubledExtremeRatio =
        rnsidedrawer::limitReleaseVelocity(spring, 2 * extremeVelocity, limitDistance) /
        rnsidedrawer::limitReleaseVelocity(spring, extremeVelocity, limitDistance);
    assert(doubledExtremeRatio > 1.25 && doubledExtremeRatio < 1.27);
  }

  const Spring slowSpring = resolveSpring(1, 0.01, 0.2);
  const double maximumVelocity = std::numeric_limits<double>::max();
  const double limitedHalfMaximum =
      rnsidedrawer::limitReleaseVelocity(slowSpring, maximumVelocity / 2, limitDistance);
  const double limitedMaximum =
      rnsidedrawer::limitReleaseVelocity(slowSpring, maximumVelocity, limitDistance);
  assert(std::isfinite(limitedMaximum));
  assert(limitedMaximum > limitedHalfMaximum);
  assert(limitedMaximum < maximumVelocity);
}

void verifyWidthStateRemapping()
{
  const auto inside = rnsidedrawer::remapStateForWidthChange(80, 160, 320, 640);
  requireNear(inside.position, 160);
  requireNear(inside.velocity, 320);

  const auto lowerOvershoot = rnsidedrawer::remapStateForWidthChange(-12, -75, 320, 640);
  requireNear(lowerOvershoot.position, -12);
  requireNear(lowerOvershoot.velocity, -75);

  const auto upperOvershoot = rnsidedrawer::remapStateForWidthChange(332, 75, 320, 640);
  requireNear(upperOvershoot.position, 652);
  requireNear(upperOvershoot.velocity, 75);

  requireNear(rnsidedrawer::remapStateForWidthChange(0, -10, 320, 640).velocity, -10);
  requireNear(rnsidedrawer::remapStateForWidthChange(0, 10, 320, 640).velocity, 20);
  requireNear(rnsidedrawer::remapStateForWidthChange(320, 10, 320, 640).velocity, 10);
  requireNear(rnsidedrawer::remapStateForWidthChange(320, -10, 320, 640).velocity, -20);

  const Spring spring = resolveSpring(0.8, 680, 46);
  const SpringState oldState = rnsidedrawer::evaluateSpring(spring, -320, 0, 0.1);
  const double oldReveal = 320 + oldState.displacement;
  const auto remapped = rnsidedrawer::remapStateForWidthChange(oldReveal, oldState.velocity, 320, 640);
  const SpringState oldFuture = rnsidedrawer::evaluateSpring(spring, oldReveal - 320, oldState.velocity, 1.0 / 60.0);
  const SpringState newFuture = rnsidedrawer::evaluateSpring(spring, remapped.position - 640, remapped.velocity, 1.0 / 60.0);
  requireNear((320 + oldFuture.displacement) / 320, (640 + newFuture.displacement) / 640, 2e-11, 2e-11);
}

void verifyOverdragDerivative()
{
  constexpr double lowerBound = 0;
  constexpr double upperBound = 320;
  constexpr double resistanceDistance = 4;
  constexpr double velocity = 137;
  constexpr double step = 1e-5;

  for (double position : {-80.0, -4.0, -0.1, 0.0, 150.0, 320.0, 320.1, 324.0, 400.0}) {
    const double derivative =
        (rnsidedrawer::resistedPosition(
             position + step, lowerBound, upperBound, resistanceDistance) -
         rnsidedrawer::resistedPosition(
             position - step, lowerBound, upperBound, resistanceDistance)) /
        (2 * step);
    const double transformedVelocity = rnsidedrawer::resistedVelocity(
        position, lowerBound, upperBound, resistanceDistance, velocity);
    requireNear(transformedVelocity, derivative * velocity, 2e-8, 2e-8);
  }
}

} // namespace

int main()
{
  verifyGoldenStates();
  verifyInitialConditionsAndSemigroup();
  verifyNearCriticalContinuity();
  verifySpringRepresentation();
  verifyExtremeSpringTransfer();
  verifySpringScaleEquivalence();
  verifyReleaseVelocityLimit();
  verifyWidthStateRemapping();
  verifyOverdragDerivative();
  std::cout << "iOS spring verification passed" << std::endl;
  return 0;
}
