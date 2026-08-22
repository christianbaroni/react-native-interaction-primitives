package com.rninteractionprimitives

import com.facebook.react.bridge.ReadableArray

internal enum class SideDrawerMotionChannel(val scalesWithDensity: Boolean = false) {
    DrawerOpacity,
    DrawerScale,
    DrawerTranslationX(scalesWithDensity = true),
    DrawerTranslationY(scalesWithDensity = true),
    ContentOpacity,
    ContentScale,
    ContentTranslationX(scalesWithDensity = true),
    ContentTranslationY(scalesWithDensity = true),
    OverlayOpacity,
    ContentBorderOpacity,
    ContentShadowOpacity,
}

internal class SideDrawerMotion private constructor(
    private val interpolations: Array<Interpolation?>,
) {
    fun evaluate(channel: SideDrawerMotionChannel, progress: Float, fallback: Float): Float {
        return interpolations[channel.ordinal]?.evaluate(progress) ?: fallback
    }

    private class Segment(
        val upperInput: Float,
        val slope: Float,
        val intercept: Float,
    )

    private class Interpolation(
        val firstInput: Float,
        val firstOutput: Float,
        val lastInput: Float,
        val lastOutput: Float,
        val segments: Array<Segment>,
    ) {
        fun evaluate(progress: Float): Float {
            if (progress <= firstInput) return firstOutput
            if (progress >= lastInput) return lastOutput

            var lower = 0
            var upper = segments.lastIndex
            while (lower < upper) {
                val middle = (lower + upper) ushr 1
                if (progress <= segments[middle].upperInput) {
                    upper = middle
                } else {
                    lower = middle + 1
                }
            }
            val segment = segments[lower]
            return segment.slope * progress + segment.intercept
        }
    }

    companion object {
        val EMPTY = SideDrawerMotion(arrayOfNulls(SideDrawerMotionChannel.entries.size))

        fun compile(configuration: ReadableArray?, density: Float): SideDrawerMotion {
            val channelCount = SideDrawerMotionChannel.entries.size
            if (configuration == null || configuration.size() < channelCount) return EMPTY

            val interpolations = arrayOfNulls<Interpolation>(channelCount)
            var cursor = channelCount
            for (channel in SideDrawerMotionChannel.entries) {
                val rawPointCount = configuration.getDouble(channel.ordinal)
                if (!rawPointCount.isFinite() || rawPointCount < 0.0 || rawPointCount > configuration.size()) {
                    return EMPTY
                }

                val pointCount = rawPointCount.toInt()
                if (rawPointCount != pointCount.toDouble() || pointCount == 1 ||
                    pointCount > (configuration.size() - cursor) / 2
                ) {
                    return EMPTY
                }
                if (pointCount == 0) continue

                val outputScale = if (channel.scalesWithDensity) density else 1f
                val firstInput = configuration.getDouble(cursor).toFloat()
                val firstOutput = configuration.getDouble(cursor + 1).toFloat() * outputScale
                if (!firstInput.isFinite() || !firstOutput.isFinite() || firstInput !in 0f..1f) return EMPTY

                var previousInput = firstInput
                var previousOutput = firstOutput
                var lastInput = firstInput
                var lastOutput = firstOutput
                cursor += 2
                val segments = ArrayList<Segment>(pointCount - 1)
                repeat(pointCount - 1) {
                    val input = configuration.getDouble(cursor).toFloat()
                    val output = configuration.getDouble(cursor + 1).toFloat() * outputScale
                    if (!input.isFinite() || !output.isFinite() || input <= previousInput || input > 1f) return EMPTY

                    val slope = (output - previousOutput) / (input - previousInput)
                    segments.add(Segment(input, slope, previousOutput - slope * previousInput))
                    previousInput = input
                    previousOutput = output
                    lastInput = input
                    lastOutput = output
                    cursor += 2
                }
                interpolations[channel.ordinal] = Interpolation(
                    firstInput,
                    firstOutput,
                    lastInput,
                    lastOutput,
                    segments.toTypedArray(),
                )
            }
            return if (cursor == configuration.size()) SideDrawerMotion(interpolations) else EMPTY
        }
    }
}
