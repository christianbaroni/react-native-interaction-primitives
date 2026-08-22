package com.rninteractionprimitives

import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tanh

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
    val dampingType: SideDrawerDampingType,
)

internal data class SideDrawerInteraction(
    val spring: SideDrawerSpring,
    val overdragPx: Float,
    val releaseOpenThreshold: Double,
    val releaseVelocitySensitivity: Double,
    val releaseVelocityTransfer: Double,
)

internal class SideDrawerSpringState {
    var displacement = 0.0
    var velocity = 0.0
}

internal const val DEFAULT_SIDE_DRAWER_OVERDRAG_DP = 4f
internal const val DEFAULT_SIDE_DRAWER_RELEASE_OPEN_THRESHOLD = 0.5
internal const val DEFAULT_SIDE_DRAWER_RELEASE_VELOCITY_SENSITIVITY = 1.0
internal const val DEFAULT_SIDE_DRAWER_RELEASE_VELOCITY_TRANSFER = 1.0
private const val DEFAULT_SIDE_DRAWER_SPRING_MASS = 1.0
private val DEFAULT_SIDE_DRAWER_SPRING_STIFFNESS = 49.0 * Math.PI * Math.PI
private val DEFAULT_SIDE_DRAWER_SPRING_DAMPING = 14.0 * Math.PI

private val DEFAULT_SIDE_DRAWER_SPRING = SideDrawerSpring(
    DEFAULT_SIDE_DRAWER_SPRING_MASS,
    DEFAULT_SIDE_DRAWER_SPRING_STIFFNESS,
    DEFAULT_SIDE_DRAWER_SPRING_DAMPING,
    DEFAULT_SIDE_DRAWER_SPRING_STIFFNESS / DEFAULT_SIDE_DRAWER_SPRING_MASS,
    (DEFAULT_SIDE_DRAWER_SPRING_DAMPING / 2.0) / DEFAULT_SIDE_DRAWER_SPRING_MASS,
    0.0,
    SideDrawerDampingType.CriticallyDamped,
)

internal fun defaultSideDrawerInteraction(overdragPx: Float) = SideDrawerInteraction(
    DEFAULT_SIDE_DRAWER_SPRING,
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
    if (!naturalFrequencySquared.isFinite() || naturalFrequencySquared <= 0.0 ||
        !dampingRate.isFinite() || dampingRate <= 0.0
    ) {
        return DEFAULT_SIDE_DRAWER_SPRING
    }

    val naturalFrequency = sqrt(naturalFrequencySquared)
    val tolerance = 32.0 * Math.ulp(1.0) * max(dampingRate, naturalFrequency)
    val dampingType: SideDrawerDampingType
    val responseRate: Double
    when {
        abs(dampingRate - naturalFrequency) <= tolerance -> {
            dampingType = SideDrawerDampingType.CriticallyDamped
            responseRate = 0.0
        }
        dampingRate < naturalFrequency -> {
            val ratio = dampingRate / naturalFrequency
            dampingType = SideDrawerDampingType.Underdamped
            responseRate = naturalFrequency * sqrt(max(0.0, 1.0 - ratio * ratio))
        }
        else -> {
            val ratio = naturalFrequency / dampingRate
            dampingType = SideDrawerDampingType.Overdamped
            responseRate = dampingRate * sqrt(max(0.0, 1.0 - ratio * ratio))
        }
    }
    return SideDrawerSpring(
        resolvedMass,
        resolvedStiffness,
        resolvedDamping,
        naturalFrequencySquared,
        dampingRate,
        responseRate,
        dampingType,
    )
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

    if (spring.dampingType == SideDrawerDampingType.Underdamped) {
        val angularFrequency = spring.responseRate
        val sineCoefficient = (initialVelocity + spring.dampingRate * initialDisplacement) / angularFrequency
        val angle = angularFrequency * elapsed
        val decay = exp(-spring.dampingRate * elapsed)
        val oscillation = initialDisplacement * cos(angle) + sineCoefficient * sin(angle)
        val oscillationVelocity =
            -initialDisplacement * angularFrequency * sin(angle) +
                sineCoefficient * angularFrequency * cos(angle)
        result.displacement = decay * oscillation
        result.velocity = decay * (oscillationVelocity - spring.dampingRate * oscillation)
        return
    }

    if (spring.dampingType == SideDrawerDampingType.Overdamped) {
        val slowRate = -spring.naturalFrequencySquared / (spring.dampingRate + spring.responseRate)
        val fastRate = -(spring.dampingRate + spring.responseRate)
        val slowCoefficient = (initialVelocity - fastRate * initialDisplacement) / (slowRate - fastRate)
        val fastCoefficient = initialDisplacement - slowCoefficient
        val slowDecay = exp(slowRate * elapsed)
        val fastDecay = exp(fastRate * elapsed)
        result.displacement = slowCoefficient * slowDecay + fastCoefficient * fastDecay
        result.velocity = slowRate * slowCoefficient * slowDecay + fastRate * fastCoefficient * fastDecay
        return
    }

    val coefficient = initialVelocity + spring.dampingRate * initialDisplacement
    val decay = exp(-spring.dampingRate * elapsed)
    result.displacement = (initialDisplacement + coefficient * elapsed) * decay
    result.velocity = (initialVelocity - spring.dampingRate * coefficient * elapsed) * decay
}

internal fun remapSideDrawerPosition(position: Float, oldWidth: Float, newWidth: Float): Float = when {
    position < 0f -> position
    position > oldWidth -> newWidth + position - oldWidth
    oldWidth > 0f -> position / oldWidth * newWidth
    else -> position
}

internal fun resistedSideDrawerPosition(
    unconstrainedPosition: Float,
    lowerBound: Float,
    upperBound: Float,
    maximumOverdrag: Float,
): Float {
    if (maximumOverdrag <= 0f) return unconstrainedPosition.coerceIn(lowerBound, upperBound)
    if (unconstrainedPosition < lowerBound) {
        return lowerBound + maximumOverdrag * tanh((unconstrainedPosition - lowerBound) / maximumOverdrag)
    }
    if (unconstrainedPosition <= upperBound) return unconstrainedPosition
    return upperBound + maximumOverdrag * tanh((unconstrainedPosition - upperBound) / maximumOverdrag)
}

internal fun resistedSideDrawerVelocity(
    unconstrainedPosition: Float,
    lowerBound: Float,
    upperBound: Float,
    maximumOverdrag: Float,
    velocity: Float,
): Float {
    if (!velocity.isFinite()) return 0f
    if (maximumOverdrag <= 0f) {
        if ((unconstrainedPosition <= lowerBound && velocity < 0f) ||
            (unconstrainedPosition >= upperBound && velocity > 0f)
        ) {
            return 0f
        }
        return velocity
    }
    if (unconstrainedPosition in lowerBound..upperBound) return velocity

    val boundary = if (unconstrainedPosition < lowerBound) lowerBound else upperBound
    val normalizedDistance = tanh((unconstrainedPosition - boundary) / maximumOverdrag)
    return velocity * (1f - normalizedDistance * normalizedDistance)
}

internal fun limitSideDrawerReleaseVelocity(
    position: Float,
    velocity: Double,
    target: Float,
    spring: SideDrawerSpring,
    maximumOverdrag: Float,
    workState: SideDrawerSpringState,
): Double {
    val outwardDirection = if (target > 0f) 1 else -1
    val currentDistance = max(0f, outwardDirection * (position - target))
    val naturalDistance = maximumOutwardDistance(position, 0.0, target, spring, workState)
    val allowedDistance = max(maximumOverdrag, max(currentDistance, naturalDistance))
    if (velocity == 0.0) return 0.0
    if (velocity.isFinite() &&
        maximumOutwardDistance(position, velocity, target, spring, workState) <= allowedDistance
    ) {
        return velocity
    }

    val direction = if (velocity < 0.0) -1.0 else 1.0
    val requestedMagnitude = abs(velocity)
    val estimate = spring.dampingRate * max(allowedDistance.toDouble(), 1.0)
    var upperMagnitude = if (estimate.isFinite()) max(1.0, min(requestedMagnitude, estimate)) else 1.0
    var lowerMagnitude = 0.0
    while (true) {
        val distance = maximumOutwardDistance(position, direction * upperMagnitude, target, spring, workState)
        if (!distance.isFinite() || distance > allowedDistance) break
        if (upperMagnitude >= requestedMagnitude) return velocity
        lowerMagnitude = upperMagnitude
        upperMagnitude = min(requestedMagnitude, upperMagnitude * 2.0)
    }

    repeat(40) {
        val candidateMagnitude = lowerMagnitude + (upperMagnitude - lowerMagnitude) * 0.5
        val distance = maximumOutwardDistance(position, direction * candidateMagnitude, target, spring, workState)
        if (!distance.isFinite() || distance > allowedDistance) {
            upperMagnitude = candidateMagnitude
        } else {
            lowerMagnitude = candidateMagnitude
        }
    }
    return direction * lowerMagnitude
}

private fun maximumOutwardDistance(
    position: Float,
    velocity: Double,
    target: Float,
    spring: SideDrawerSpring,
    workState: SideDrawerSpringState,
): Float {
    val outwardDirection = if (target > 0f) 1 else -1
    val displacement = (position - target).toDouble()
    var maximumDistance = max(0.0, outwardDirection * displacement)

    if (spring.dampingType == SideDrawerDampingType.Underdamped) {
        val angularFrequency = spring.responseRate
        val sineCoefficient =
            -(spring.dampingRate * velocity + spring.naturalFrequencySquared * displacement) / angularFrequency
        val phase = atan2(velocity, sineCoefficient)
        val rootIndex = floor(phase / Math.PI) + 1.0
        val firstExtremum = (rootIndex * Math.PI - phase) / angularFrequency
        maximumDistance = max(
            maximumDistance,
            outwardDistanceAtTime(
                spring,
                displacement,
                velocity,
                firstExtremum,
                outwardDirection,
                workState,
            ),
        )
        maximumDistance = max(
            maximumDistance,
            outwardDistanceAtTime(
                spring,
                displacement,
                velocity,
                firstExtremum + Math.PI / angularFrequency,
                outwardDirection,
                workState,
            ),
        )
        return max(0.0, maximumDistance).toFloat()
    }

    if (spring.dampingType == SideDrawerDampingType.Overdamped) {
        val slowRate = -spring.naturalFrequencySquared / (spring.dampingRate + spring.responseRate)
        val fastRate = -(spring.dampingRate + spring.responseRate)
        val slowCoefficient = (velocity - fastRate * displacement) / (slowRate - fastRate)
        val fastCoefficient = displacement - slowCoefficient
        val denominator = slowRate * slowCoefficient
        if (denominator != 0.0 && denominator.isFinite()) {
            val ratio = -(fastRate * fastCoefficient) / denominator
            if (ratio > 0.0 && ratio.isFinite()) {
                maximumDistance = max(
                    maximumDistance,
                    outwardDistanceAtTime(
                        spring,
                        displacement,
                        velocity,
                        ln(ratio) / (slowRate - fastRate),
                        outwardDirection,
                        workState,
                    ),
                )
            }
        }
        return max(0.0, maximumDistance).toFloat()
    }

    val coefficient = velocity + spring.dampingRate * displacement
    val denominator = spring.dampingRate * coefficient
    if (denominator != 0.0 && denominator.isFinite()) {
        maximumDistance = max(
            maximumDistance,
            outwardDistanceAtTime(
                spring,
                displacement,
                velocity,
                velocity / denominator,
                outwardDirection,
                workState,
            ),
        )
    }
    return max(0.0, maximumDistance).toFloat()
}

private fun outwardDistanceAtTime(
    spring: SideDrawerSpring,
    displacement: Double,
    velocity: Double,
    time: Double,
    outwardDirection: Int,
    workState: SideDrawerSpringState,
): Double {
    if (time <= 0.0 || !time.isFinite()) return 0.0
    evaluateSideDrawerSpring(spring, displacement, velocity, time, workState)
    return outwardDirection * workState.displacement
}
