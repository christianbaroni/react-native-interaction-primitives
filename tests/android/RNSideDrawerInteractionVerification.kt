package com.rninteractionprimitives

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.pow

private const val RELATIVE_TOLERANCE = 2e-11
private const val ABSOLUTE_TOLERANCE = 2e-11

private fun requireNear(
    actual: Double,
    expected: Double,
    relative: Double = RELATIVE_TOLERANCE,
    absolute: Double = ABSOLUTE_TOLERANCE,
) {
    val scale = max(1.0, max(abs(actual), abs(expected)))
    check(actual.isFinite() && expected.isFinite() && abs(actual - expected) <= max(absolute, relative * scale)) {
        "Expected $expected, got $actual"
    }
}

private fun evaluate(
    spring: SideDrawerSpring,
    displacement: Double,
    velocity: Double,
    elapsed: Double,
): SideDrawerSpringState = SideDrawerSpringState().also {
    evaluateSideDrawerSpring(spring, displacement, velocity, elapsed, it)
}

private fun verifyGoldenStates() {
    data class Case(
        val spring: SideDrawerSpring,
        val displacement: Double,
        val velocity: Double,
        val elapsed: Double,
        val expectedDisplacement: Double,
        val expectedVelocity: Double,
    )

    val cases = listOf(
        Case(resolveSideDrawerSpring(0.8, 680.0, 46.0), -320.0, 0.0, 0.1, -65.87757877044565, 1475.2753861570177),
        Case(resolveSideDrawerSpring(0.8, 680.0, 46.0), -320.0, 0.0, 0.2, -5.560439749842255, 147.32983655837184),
        Case(resolveSideDrawerSpring(1.0, 100.0, 5.0), 10.0, -20.0, 0.37, -3.6734629900593335, 23.775980595041943),
        Case(resolveSideDrawerSpring(1.0, 100.0, 20.0), 10.0, -20.0, 0.37, 0.9790516482254399, -7.812634364627248),
        Case(resolveSideDrawerSpring(1.0, 100.0, 30.0), 10.0, -20.0, 0.37, 2.631430194700746, -10.05003890074222),
    )

    cases.forEach { testCase ->
        val state = evaluate(testCase.spring, testCase.displacement, testCase.velocity, testCase.elapsed)
        requireNear(state.displacement, testCase.expectedDisplacement)
        requireNear(state.velocity, testCase.expectedVelocity)
    }
}

private fun verifyInitialConditionsAndSemigroup() {
    val springs = listOf(
        resolveSideDrawerSpring(1.0, 100.0, 5.0),
        resolveSideDrawerSpring(1.0, 100.0, 20.0),
        resolveSideDrawerSpring(1.0, 100.0, 30.0),
    )

    springs.forEach { spring ->
        val initial = evaluate(spring, 17.5, -43.25, 0.0)
        requireNear(initial.displacement, 17.5)
        requireNear(initial.velocity, -43.25)

        val first = evaluate(spring, 17.5, -43.25, 0.173)
        val restarted = evaluate(spring, first.displacement, first.velocity, 0.281)
        val direct = evaluate(spring, 17.5, -43.25, 0.454)
        requireNear(restarted.displacement, direct.displacement, 8e-11, 8e-11)
        requireNear(restarted.velocity, direct.velocity, 8e-11, 8e-11)
    }
}

private fun verifyNearCriticalContinuity() {
    val critical = resolveSideDrawerSpring(1.0, 100.0, 20.0)
    val below = resolveSideDrawerSpring(1.0, 100.0, 20.0 * (1.0 - 1e-8))
    val above = resolveSideDrawerSpring(1.0, 100.0, 20.0 * (1.0 + 1e-8))

    check(critical.dampingType == SideDrawerDampingType.CriticallyDamped)
    check(below.dampingType == SideDrawerDampingType.Underdamped)
    check(above.dampingType == SideDrawerDampingType.Overdamped)
    check(below.peakDisplacementPerVelocity.isFinite())
    check(above.peakDisplacementPerVelocity.isFinite())
    requireNear(below.peakDisplacementPerVelocity, critical.peakDisplacementPerVelocity, 1e-7, 1e-13)
    requireNear(above.peakDisplacementPerVelocity, critical.peakDisplacementPerVelocity, 1e-7, 1e-13)

    listOf(0.001, 0.1, 0.5).forEach { elapsed ->
        val criticalState = evaluate(critical, 83.0, -127.0, elapsed)
        val belowState = evaluate(below, 83.0, -127.0, elapsed)
        val aboveState = evaluate(above, 83.0, -127.0, elapsed)
        requireNear(belowState.displacement, criticalState.displacement, 3e-7, 3e-9)
        requireNear(aboveState.displacement, criticalState.displacement, 3e-7, 3e-9)
        requireNear(belowState.velocity, criticalState.velocity, 3e-7, 3e-9)
        requireNear(aboveState.velocity, criticalState.velocity, 3e-7, 3e-9)
    }

    val offset = 1e-12
    val veryNearBelow = resolveSideDrawerSpring(1.0, 100.0, 20.0 * (1.0 - offset))
    val veryNearAbove = resolveSideDrawerSpring(1.0, 100.0, 20.0 * (1.0 + offset))
    val belowRatio = veryNearBelow.dampingRate / 10.0
    val aboveRatio = veryNearAbove.dampingRate / 10.0
    requireNear(
        veryNearBelow.responseRate,
        10.0 * kotlin.math.sqrt((1.0 - belowRatio) * (1.0 + belowRatio)),
        2e-12,
        2e-18,
    )
    requireNear(
        veryNearAbove.responseRate,
        10.0 * kotlin.math.sqrt(aboveRatio - 1.0) * kotlin.math.sqrt(aboveRatio + 1.0),
        2e-12,
        2e-18,
    )
}

private fun verifySpringRepresentation() {
    val accepted = resolveSideDrawerSpring(1.0, 4.0, 2.0)
    requireNear(accepted.mass, 1.0)
    requireNear(accepted.stiffness, 4.0)
    requireNear(accepted.damping, 2.0)

    val partiallyDefaulted = resolveSideDrawerSpring(-1.0, 100.0, 20.0)
    requireNear(partiallyDefaulted.mass, DEFAULT_SIDE_DRAWER_SPRING_MASS)
    requireNear(partiallyDefaulted.stiffness, 100.0)
    requireNear(partiallyDefaulted.damping, 20.0)

    val slowTail = resolveSideDrawerSpring(1.0, 100.0, 200.0)
    requireNear(slowTail.mass, 1.0)
    requireNear(slowTail.stiffness, 100.0)
    requireNear(slowTail.damping, 200.0)

    val extremeOverdamping = resolveSideDrawerSpring(1.0, 1.0, 2e9)
    requireNear(extremeOverdamping.mass, 1.0)
    requireNear(extremeOverdamping.stiffness, 1.0)
    requireNear(extremeOverdamping.damping, 2e9)
    requireNear(extremeOverdamping.peakDisplacementPerVelocity, 5e-10, 1e-9, 1e-18)

    val quotientConditioned = resolveSideDrawerSpring(1.0, 1.0, 2e307)
    requireNear(quotientConditioned.damping, 2e307)
    check(quotientConditioned.peakDisplacementPerVelocity.isFinite())
    check(quotientConditioned.peakDisplacementPerVelocity > 0.0)
    val quotientConditionedState = evaluate(quotientConditioned, 320.0, 10_000.0, 1.0 / 120.0)
    check(quotientConditionedState.displacement.isFinite())
    check(quotientConditionedState.velocity.isFinite())

    val overflow = resolveSideDrawerSpring(1e-300, 1e300, 1.0)
    requireNear(overflow.mass, DEFAULT_SIDE_DRAWER_SPRING_MASS)
    requireNear(overflow.stiffness, DEFAULT_SIDE_DRAWER_SPRING_STIFFNESS)
    requireNear(overflow.damping, DEFAULT_SIDE_DRAWER_SPRING_DAMPING)
}

private fun verifyExtremeSpringTransfer() {
    data class Case(
        val damping: Double,
        val restoringDisplacement: Double,
        val restoringVelocity: Double,
        val velocityOnlyDisplacement: Double,
        val velocityOnlyVelocity: Double,
    )
    // Modal solutions evaluated at 800-digit precision from the admitted double inputs.
    val cases = listOf(
        Case(1e307, -294.41421268138345, 2944.1421268138342, 9.200444146293232e-288, -9.200444146293233e-287),
        Case(1.7e307, -304.691987092261, 1792.305806425065, 5.600955645078327e-288, -3.2946797912225456e-287),
    )
    cases.forEach { testCase ->
        val spring = resolveSideDrawerSpring(1.0, 1e308, testCase.damping)
        requireNear(spring.stiffness, 1e308)
        requireNear(spring.damping, testCase.damping)
        val restoring = evaluate(spring, -320.0, 0.0, 1.0 / 120.0)
        requireNear(restoring.displacement, testCase.restoringDisplacement)
        requireNear(restoring.velocity, testCase.restoringVelocity)
        val velocityOnly = evaluate(spring, 0.0, 1e20, 1.0 / 120.0)
        requireNear(velocityOnly.displacement / testCase.velocityOnlyDisplacement, 1.0)
        requireNear(velocityOnly.velocity / testCase.velocityOnlyVelocity, 1.0)

        listOf(-320.0 to 0.0, 0.0 to 1e20, 320.0 to -1e20).forEach { (displacement, velocity) ->
            val direct = evaluate(spring, displacement, velocity, 1.0 / 120.0)
            val opposite = evaluate(spring, -displacement, -velocity, 1.0 / 120.0)
            requireNear(opposite.displacement / -direct.displacement, 1.0)
            requireNear(opposite.velocity / -direct.velocity, 1.0)
            val first = evaluate(spring, displacement, velocity, 1.0 / 360.0)
            val resumed = evaluate(spring, first.displacement, first.velocity, 1.0 / 180.0)
            requireNear(resumed.displacement / direct.displacement, 1.0)
            requireNear(resumed.velocity / direct.velocity, 1.0)
        }
    }
    val settled = evaluate(resolveSideDrawerSpring(1.0, 1e308, 2e154), -320.0, 0.0, 1.0 / 120.0)
    check(settled.displacement == 0.0 && settled.velocity == 0.0)
}

private fun verifySpringScaleEquivalence() {
    listOf(1e-308, 1e-150, 1.0, 1e150, 1e308).forEach { stiffness ->
        val frequency = kotlin.math.sqrt(stiffness)
        listOf(0.1, 1.0, 10.0).forEach { dampingRatio ->
            val spring = resolveSideDrawerSpring(1.0, stiffness, 2.0 * dampingRatio * frequency)
            val normalizedSpring = resolveSideDrawerSpring(1.0, 1.0, 2.0 * dampingRatio)
            listOf(0.01, 0.1, 1.0, 10.0, 100.0).forEach { normalizedTime ->
                val actual = evaluate(spring, -320.0, 23.0 * frequency, normalizedTime / frequency)
                val expected = evaluate(normalizedSpring, -320.0, 23.0, normalizedTime)
                requireNear(actual.displacement, expected.displacement)
                requireNear(actual.velocity / frequency, expected.velocity)
            }
        }
    }
}

private fun verifyConfiguredInteraction() {
    val interaction = defaultSideDrawerInteraction(7f).copy(
        springMass = 1.0,
        springStiffness = 100.0,
        springDamping = 20.0,
        releaseOpenThreshold = 0.4,
        releaseVelocitySensitivity = 1.5,
        releaseVelocityTransfer = 0.75,
    )
    requireNear(interaction.spring.mass, 1.0)
    requireNear(interaction.spring.stiffness, 100.0)
    requireNear(interaction.spring.damping, 20.0)
    requireNear(interaction.overdragPx.toDouble(), 7.0)
    requireNear(interaction.releaseOpenThreshold, 0.4)
    requireNear(interaction.releaseVelocitySensitivity, 1.5)
    requireNear(interaction.releaseVelocityTransfer, 0.75)

    val updatedInteraction = interaction.copy(springMass = 2.0)
    requireNear(interaction.spring.mass, 1.0)
    requireNear(updatedInteraction.spring.mass, 2.0)
    check(updatedInteraction !== interaction)

    val temporarilyUnrepresentable = interaction.copy(
        springMass = 1e-300,
        springStiffness = 1e300,
        springDamping = 1.0,
    )
    requireNear(temporarilyUnrepresentable.spring.mass, DEFAULT_SIDE_DRAWER_SPRING_MASS)
    val recovered = temporarilyUnrepresentable.copy(springMass = 1.0)
    requireNear(recovered.spring.mass, 1.0)
    requireNear(recovered.spring.stiffness, 1e300)
    requireNear(recovered.spring.damping, 1.0)
}

private fun verifyReleaseVelocityLimit() {
    val limitDistance = 32.0
    val springs = listOf(
        resolveSideDrawerSpring(1.0, 180.0, 7.0),
        resolveSideDrawerSpring(0.8, 680.0, 46.0),
        resolveSideDrawerSpring(1.0, 225.0, 42.0),
    )

    springs.forEach { spring ->
        var previousMagnitude = 0.0
        listOf(1.0, 500.0, 2500.0, 10000.0, 1e8).forEach { velocity ->
            val limited = limitSideDrawerReleaseVelocity(spring, velocity, limitDistance)
            val limitedNegative = limitSideDrawerReleaseVelocity(spring, -velocity, limitDistance)
            requireNear(limitedNegative, -limited, 2e-12, 2e-12)
            check(abs(limited) >= previousMagnitude)
            check(abs(limited) <= velocity)
            previousMagnitude = abs(limited)

            val inputDistance = abs(spring.peakDisplacementPerVelocity * velocity) / limitDistance
            val limitedDistance = abs(spring.peakDisplacementPerVelocity * limited) / limitDistance
            requireNear(
                inputDistance * inputDistance,
                limitedDistance * limitedDistance + limitedDistance.pow(6),
                3e-10,
                3e-12,
            )
        }

        val velocityAtLimitDistance = limitDistance / spring.peakDisplacementPerVelocity
        val ordinaryVelocity = 0.01 * velocityAtLimitDistance
        check(limitSideDrawerReleaseVelocity(spring, ordinaryVelocity, limitDistance) / ordinaryVelocity > 0.99999999)
        val extremeVelocity = 1000.0 * velocityAtLimitDistance
        val doubledExtremeRatio =
            limitSideDrawerReleaseVelocity(spring, 2.0 * extremeVelocity, limitDistance) /
                limitSideDrawerReleaseVelocity(spring, extremeVelocity, limitDistance)
        check(doubledExtremeRatio > 1.25 && doubledExtremeRatio < 1.27)
    }

    val slowSpring = resolveSideDrawerSpring(1.0, 0.01, 0.2)
    val limitedHalfMaximum = limitSideDrawerReleaseVelocity(slowSpring, Double.MAX_VALUE / 2.0, limitDistance)
    val limitedMaximum = limitSideDrawerReleaseVelocity(slowSpring, Double.MAX_VALUE, limitDistance)
    check(limitedMaximum.isFinite())
    check(limitedMaximum > limitedHalfMaximum)
    check(limitedMaximum < Double.MAX_VALUE)
}

private fun verifyWidthStateRemapping() {
    val inside = remapSideDrawerState(80f, 160.0, 320f, 640f)
    requireNear(inside.position.toDouble(), 160.0)
    requireNear(inside.velocity, 320.0)

    val lowerOvershoot = remapSideDrawerState(-12f, -75.0, 320f, 640f)
    requireNear(lowerOvershoot.position.toDouble(), -12.0)
    requireNear(lowerOvershoot.velocity, -75.0)

    val upperOvershoot = remapSideDrawerState(332f, 75.0, 320f, 640f)
    requireNear(upperOvershoot.position.toDouble(), 652.0)
    requireNear(upperOvershoot.velocity, 75.0)

    requireNear(remapSideDrawerState(0f, -10.0, 320f, 640f).velocity, -10.0)
    requireNear(remapSideDrawerState(0f, 10.0, 320f, 640f).velocity, 20.0)
    requireNear(remapSideDrawerState(320f, 10.0, 320f, 640f).velocity, 10.0)
    requireNear(remapSideDrawerState(320f, -10.0, 320f, 640f).velocity, -20.0)

    val spring = resolveSideDrawerSpring(0.8, 680.0, 46.0)
    val oldState = evaluate(spring, -320.0, 0.0, 0.1)
    val oldReveal = 320.0 + oldState.displacement
    val remapped = remapSideDrawerState(oldReveal.toFloat(), oldState.velocity, 320f, 640f)
    val oldFuture = evaluate(spring, oldReveal - 320.0, oldState.velocity, 1.0 / 60.0)
    val newFuture = evaluate(spring, remapped.position - 640.0, remapped.velocity, 1.0 / 60.0)
    requireNear(
        (320.0 + oldFuture.displacement) / 320.0,
        (640.0 + newFuture.displacement) / 640.0,
        2e-7,
        2e-7,
    )
}

private fun verifyOverdragDerivative() {
    val lowerBound = 0f
    val upperBound = 320f
    val resistanceDistance = 4f
    val velocity = 137f
    val step = 0.25f

    listOf(-80f, -4f, -0.1f, 0f, 150f, 320f, 320.1f, 324f, 400f).forEach { position ->
        val derivative = (
            resistedSideDrawerPosition(position + step, lowerBound, upperBound, resistanceDistance) -
                resistedSideDrawerPosition(position - step, lowerBound, upperBound, resistanceDistance)
            ) / (2f * step)
        val transformedVelocity = resistedSideDrawerVelocity(
            position,
            lowerBound,
            upperBound,
            resistanceDistance,
            velocity,
        )
        requireNear(transformedVelocity.toDouble(), (derivative * velocity).toDouble(), 1e-3, 1e-3)
    }
}

private fun verifyRemainingDisplacementBound() {
    val springs = listOf(
        resolveSideDrawerSpring(1.0, 100.0, 5.0),
        resolveSideDrawerSpring(1.0, 100.0, 20.0),
        resolveSideDrawerSpring(1.0, 100.0, 30.0),
    )

    springs.forEach { spring ->
        val displacement = 13.0
        val velocity = -87.0
        val bound = sideDrawerSpringDisplacementBound(spring, displacement, velocity)
        check(bound.isFinite())
        repeat(501) { sample ->
            val state = evaluate(spring, displacement, velocity, sample * 0.01)
            check(abs(state.displacement) <= bound + 2e-10)
        }
    }

    val spring = resolveSideDrawerSpring(0.8, 680.0, 46.0)
    check(sideDrawerSpringDisplacementBound(spring, Double.NaN, 0.0).isInfinite())
}

private fun verifyDensityIndependentCompletionFrame() {
    val spring = resolveSideDrawerSpring(0.8, 680.0, 46.0)

    fun completionFrame(density: Double): Int {
        val displacement = -320.0 * density
        for (frame in 0..1000) {
            val state = evaluate(spring, displacement, 0.0, frame / 60.0)
            val residual = sideDrawerSpringDisplacementBound(spring, state.displacement, state.velocity)
            if (residual <= 0.5 * density) return frame
        }
        error("Spring did not complete")
    }

    check(completionFrame(1.0) == completionFrame(4.0))
}

fun main() {
    verifyGoldenStates()
    verifyInitialConditionsAndSemigroup()
    verifyNearCriticalContinuity()
    verifySpringRepresentation()
    verifyExtremeSpringTransfer()
    verifySpringScaleEquivalence()
    verifyConfiguredInteraction()
    verifyReleaseVelocityLimit()
    verifyWidthStateRemapping()
    verifyOverdragDerivative()
    verifyRemainingDisplacementBound()
    verifyDensityIndependentCompletionFrame()
    println("Android spring verification passed")
}
