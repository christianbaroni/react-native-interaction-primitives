package com.rninteractionprimitives

import kotlin.math.abs
import kotlin.math.acosh
import kotlin.math.asinh
import kotlin.math.atan2
import kotlin.math.cbrt
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.expm1
import kotlin.math.hypot
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.sin
import kotlin.math.sqrt

internal enum class SideDrawerDampingType {
    Underdamped,
    CriticallyDamped,
    Overdamped,
}

internal data class SideDrawerSpring(
    val mass: Double,
    val stiffness: Double,
    val damping: Double,
    val naturalFrequencySquared: Double,
    val dampingRate: Double,
    val responseRate: Double,
    val peakDisplacementPerVelocity: Double,
    val dampingType: SideDrawerDampingType,
)

internal data class SideDrawerInteraction(
    val springMass: Double,
    val springStiffness: Double,
    val springDamping: Double,
    val overdragPx: Float,
    val releaseOpenThreshold: Double,
    val releaseVelocitySensitivity: Double,
    val releaseVelocityTransfer: Double,
) {
    val spring = resolveSideDrawerSpring(springMass, springStiffness, springDamping)
}

internal class SideDrawerSpringState {
    var displacement = 0.0
    var velocity = 0.0
}

internal data class SideDrawerWidthChangeState(
    val position: Float,
    val velocity: Double,
)

internal const val DEFAULT_SIDE_DRAWER_OVERDRAG_DP = 4f
internal const val DEFAULT_SIDE_DRAWER_RELEASE_OPEN_THRESHOLD = 0.5
internal const val DEFAULT_SIDE_DRAWER_RELEASE_VELOCITY_SENSITIVITY = 1.0
internal const val DEFAULT_SIDE_DRAWER_RELEASE_VELOCITY_TRANSFER = 1.0
internal const val DEFAULT_SIDE_DRAWER_SPRING_MASS = 0.8
internal const val DEFAULT_SIDE_DRAWER_SPRING_STIFFNESS = 680.0
internal const val DEFAULT_SIDE_DRAWER_SPRING_DAMPING = 46.0

private fun sideDrawerPeakDisplacementPerVelocity(naturalFrequency: Double, peakDecay: Double): Double {
    if (!naturalFrequency.isFinite() || naturalFrequency <= 0.0 ||
        !peakDecay.isFinite() || peakDecay < 0.0
    ) {
        return 0.0
    }
    return exp(-peakDecay - ln(naturalFrequency))
}

private fun createSideDrawerSpring(mass: Double, stiffness: Double, damping: Double): SideDrawerSpring {
    val naturalFrequencySquared = stiffness / mass
    val dampingRate = (damping / 2.0) / mass
    val naturalFrequency = sqrt(naturalFrequencySquared)
    val tolerance = 32.0 * Math.ulp(1.0) * max(dampingRate, naturalFrequency)
    val dampingType: SideDrawerDampingType
    val responseRate: Double
    val peakDecay: Double
    when {
        abs(dampingRate - naturalFrequency) <= tolerance -> {
            dampingType = SideDrawerDampingType.CriticallyDamped
            responseRate = 0.0
            peakDecay = 1.0
        }
        dampingRate < naturalFrequency -> {
            val dampingRatio = dampingRate / naturalFrequency
            val normalizedResponse = sqrt(max(0.0, (1.0 - dampingRatio) * (1.0 + dampingRatio)))
            dampingType = SideDrawerDampingType.Underdamped
            responseRate = naturalFrequency * normalizedResponse
            peakDecay = dampingRatio * atan2(normalizedResponse, dampingRatio) / normalizedResponse
        }
        else -> {
            val dampingRatio = dampingRate / naturalFrequency
            val normalizedResponse = sqrt(max(0.0, dampingRatio - 1.0)) *
                sqrt(max(0.0, dampingRatio + 1.0))
            dampingType = SideDrawerDampingType.Overdamped
            responseRate = naturalFrequency * normalizedResponse
            peakDecay = (dampingRatio / normalizedResponse) * acosh(dampingRatio)
        }
    }
    return SideDrawerSpring(
        mass,
        stiffness,
        damping,
        naturalFrequencySquared,
        dampingRate,
        responseRate,
        sideDrawerPeakDisplacementPerVelocity(naturalFrequency, peakDecay),
        dampingType,
    )
}

private fun sideDrawerSpringIsRepresentable(spring: SideDrawerSpring): Boolean {
    if (!spring.mass.isFinite() || spring.mass <= 0.0 ||
        !spring.stiffness.isFinite() || spring.stiffness <= 0.0 ||
        !spring.damping.isFinite() || spring.damping <= 0.0 ||
        !spring.naturalFrequencySquared.isFinite() || spring.naturalFrequencySquared <= 0.0 ||
        !spring.dampingRate.isFinite() || spring.dampingRate <= 0.0 ||
        !spring.peakDisplacementPerVelocity.isFinite() || spring.peakDisplacementPerVelocity <= 0.0
    ) {
        return false
    }
    if (spring.dampingType == SideDrawerDampingType.CriticallyDamped) {
        return spring.responseRate == 0.0
    }
    if (!spring.responseRate.isFinite() || spring.responseRate <= 0.0) return false
    return spring.dampingType != SideDrawerDampingType.Overdamped ||
        (spring.dampingRate + spring.responseRate).isFinite()
}

private val DEFAULT_SIDE_DRAWER_SPRING = createSideDrawerSpring(
    DEFAULT_SIDE_DRAWER_SPRING_MASS,
    DEFAULT_SIDE_DRAWER_SPRING_STIFFNESS,
    DEFAULT_SIDE_DRAWER_SPRING_DAMPING,
)

internal fun defaultSideDrawerInteraction(overdragPx: Float) =
    SideDrawerInteraction(
        DEFAULT_SIDE_DRAWER_SPRING_MASS,
        DEFAULT_SIDE_DRAWER_SPRING_STIFFNESS,
        DEFAULT_SIDE_DRAWER_SPRING_DAMPING,
        overdragPx,
        DEFAULT_SIDE_DRAWER_RELEASE_OPEN_THRESHOLD,
        DEFAULT_SIDE_DRAWER_RELEASE_VELOCITY_SENSITIVITY,
        DEFAULT_SIDE_DRAWER_RELEASE_VELOCITY_TRANSFER,
    )

internal fun resolveSideDrawerSpring(mass: Double, stiffness: Double, damping: Double): SideDrawerSpring {
    val resolvedMass = if (mass.isFinite() && mass > 0.0) mass else DEFAULT_SIDE_DRAWER_SPRING_MASS
    val resolvedStiffness = if (stiffness.isFinite() && stiffness > 0.0) {
        stiffness
    } else {
        DEFAULT_SIDE_DRAWER_SPRING_STIFFNESS
    }
    val resolvedDamping = if (damping.isFinite() && damping > 0.0) {
        damping
    } else {
        DEFAULT_SIDE_DRAWER_SPRING_DAMPING
    }
    val naturalFrequencySquared = resolvedStiffness / resolvedMass
    val dampingRate = (resolvedDamping / 2.0) / resolvedMass
    val naturalFrequency = sqrt(naturalFrequencySquared)
    val dampingRatio = dampingRate / naturalFrequency
    if (!naturalFrequencySquared.isFinite() || naturalFrequencySquared <= 0.0 ||
        !dampingRate.isFinite() || dampingRate <= 0.0 ||
        !naturalFrequency.isFinite() || naturalFrequency <= 0.0 ||
        !dampingRatio.isFinite() || dampingRatio <= 0.0
    ) {
        return DEFAULT_SIDE_DRAWER_SPRING
    }

    val spring = createSideDrawerSpring(resolvedMass, resolvedStiffness, resolvedDamping)
    return if (sideDrawerSpringIsRepresentable(spring)) spring else DEFAULT_SIDE_DRAWER_SPRING
}

internal fun evaluateSideDrawerSpring(
    spring: SideDrawerSpring,
    initialDisplacement: Double,
    initialVelocity: Double,
    elapsed: Double,
    result: SideDrawerSpringState,
) {
    if (elapsed <= 0.0) {
        result.displacement = initialDisplacement
        result.velocity = initialVelocity
        return
    }

    // Exact basis functions for x'' + 2αx' + ω₀²x = 0. Expressing the
    // solution through its unit-velocity response avoids the large opposing
    // modal coefficients that become ill-conditioned near critical damping
    // and can overflow for otherwise representable overdamped springs.
    val displacementResponse: Double
    val velocityResponse: Double
    val unitVelocityResponse: Double
    when (spring.dampingType) {
        SideDrawerDampingType.Underdamped -> {
            val angle = spring.responseRate * elapsed
            val decay = exp(-spring.dampingRate * elapsed)
            val sinc = if (angle == 0.0) 1.0 else sin(angle) / angle
            val phaseResponse = decay * cos(angle)
            unitVelocityResponse = decay * elapsed * sinc
            val dampingResponse = spring.dampingRate * unitVelocityResponse
            displacementResponse = phaseResponse + dampingResponse
            velocityResponse = phaseResponse - dampingResponse
        }
        SideDrawerDampingType.Overdamped -> {
            val slowRate = -spring.naturalFrequencySquared / (spring.dampingRate + spring.responseRate)
            val slowDecay = exp(slowRate * elapsed)
            val angle = spring.responseRate * elapsed
            val relativeFastDecay = exp(-2.0 * angle)
            unitVelocityResponse = if (angle == 0.0) {
                slowDecay * elapsed
            } else {
                slowDecay * -expm1(-2.0 * angle) / (2.0 * spring.responseRate)
            }
            // Keep the slow tail out of a subtraction of nearly equal terms.
            val slowResponse = slowRate * unitVelocityResponse
            displacementResponse = slowDecay - slowResponse
            velocityResponse = slowDecay * relativeFastDecay + slowResponse
        }
        SideDrawerDampingType.CriticallyDamped -> {
            val decay = exp(-spring.dampingRate * elapsed)
            unitVelocityResponse = decay * elapsed
            val dampingResponse = spring.dampingRate * unitVelocityResponse
            displacementResponse = decay + dampingResponse
            velocityResponse = decay - dampingResponse
        }
    }

    // Form the restoring response before scaling by displacement to avoid overflow.
    result.displacement =
        initialDisplacement * displacementResponse + initialVelocity * unitVelocityResponse
    result.velocity =
        initialVelocity * velocityResponse -
        initialDisplacement * (spring.naturalFrequencySquared * unitVelocityResponse)
}

internal fun limitSideDrawerReleaseVelocity(
    spring: SideDrawerSpring,
    velocity: Double,
    limitDistance: Double,
): Double {
    if (!velocity.isFinite()) return 0.0
    if (velocity == 0.0 || !limitDistance.isFinite() || limitDistance <= 0.0 ||
        !spring.peakDisplacementPerVelocity.isFinite() || spring.peakDisplacementPerVelocity <= 0.0
    ) {
        return velocity
    }

    val velocityAtLimitDistance = limitDistance / spring.peakDisplacementPerVelocity
    if (!velocityAtLimitDistance.isFinite()) return velocity
    if (velocityAtLimitDistance == 0.0) return 0.0

    val normalizedVelocity = abs(velocity) / velocityAtLimitDistance
    if (normalizedVelocity == 0.0) return velocity

    // Exact positive root of u² = s² + s⁶. Its cubic asymptote avoids
    // squaring overflow without introducing a threshold in the curve.
    val squaredVelocity = normalizedVelocity * normalizedVelocity
    if (squaredVelocity == 0.0) return velocity
    val scaledSquare = CUBIC_INPUT_SCALE * squaredVelocity
    val limitedMagnitude = if (scaledSquare.isFinite()) {
        val normalizedLimit = sqrt(
            CUBIC_OUTPUT_SCALE * kotlin.math.sinh(asinh(scaledSquare) / 3.0),
        )
        velocityAtLimitDistance * normalizedLimit
    } else if (normalizedVelocity.isFinite()) {
        velocityAtLimitDistance * cbrt(normalizedVelocity)
    } else {
        val cubeRootScale = cbrt(velocityAtLimitDistance)
        cbrt(abs(velocity)) * cubeRootScale * cubeRootScale
    }
    return Math.copySign(minOf(limitedMagnitude, abs(velocity)), velocity)
}

internal fun sideDrawerSpringDisplacementBound(
    spring: SideDrawerSpring,
    displacement: Double,
    velocity: Double,
): Double {
    if (!displacement.isFinite() || !velocity.isFinite()) return Double.POSITIVE_INFINITY
    val naturalFrequency = sqrt(spring.naturalFrequencySquared)
    if (!naturalFrequency.isFinite() || naturalFrequency <= 0.0) return Double.POSITIVE_INFINITY
    return hypot(displacement, velocity / naturalFrequency)
}

internal fun remapSideDrawerState(
    position: Float,
    velocity: Double,
    oldWidth: Float,
    newWidth: Float,
): SideDrawerWidthChangeState {
    val remappedPosition = when {
        position < 0f -> position
        position > oldWidth -> newWidth + position - oldWidth
        oldWidth > 0f -> position / oldWidth * newWidth
        else -> position
    }
    val velocityScale = when {
        oldWidth <= 0f || position < 0f || position > oldWidth -> 1.0
        position == 0f && velocity < 0.0 -> 1.0
        position == oldWidth && velocity > 0.0 -> 1.0
        else -> newWidth.toDouble() / oldWidth
    }
    val remappedVelocity = velocity * velocityScale
    return SideDrawerWidthChangeState(
        remappedPosition,
        if (remappedVelocity.isFinite()) remappedVelocity else 0.0,
    )
}

internal fun remapSideDrawerPosition(position: Float, oldWidth: Float, newWidth: Float): Float =
    remapSideDrawerState(position, 0.0, oldWidth, newWidth).position

internal fun resistedSideDrawerPosition(
    unconstrainedPosition: Float,
    lowerBound: Float,
    upperBound: Float,
    resistanceDistance: Float,
): Float {
    if (resistanceDistance <= 0f) return unconstrainedPosition.coerceIn(lowerBound, upperBound)
    if (unconstrainedPosition < lowerBound) {
        return lowerBound + resistanceDistance * asinh((unconstrainedPosition - lowerBound) / resistanceDistance)
    }
    if (unconstrainedPosition <= upperBound) return unconstrainedPosition
    return upperBound + resistanceDistance * asinh((unconstrainedPosition - upperBound) / resistanceDistance)
}

internal fun resistedSideDrawerVelocity(
    unconstrainedPosition: Float,
    lowerBound: Float,
    upperBound: Float,
    resistanceDistance: Float,
    velocity: Float,
): Float {
    if (!velocity.isFinite()) return 0f
    if (resistanceDistance <= 0f) {
        if ((unconstrainedPosition <= lowerBound && velocity < 0f) ||
            (unconstrainedPosition >= upperBound && velocity > 0f)
        ) {
            return 0f
        }
        return velocity
    }
    if (unconstrainedPosition in lowerBound..upperBound) return velocity

    val boundary = if (unconstrainedPosition < lowerBound) lowerBound else upperBound
    val normalizedDistance = (unconstrainedPosition - boundary) / resistanceDistance
    return velocity / hypot(1f, normalizedDistance)
}

private const val CUBIC_INPUT_SCALE = 2.598076211353316
private const val CUBIC_OUTPUT_SCALE = 1.154700538379252
