package com.rninteractionprimitives

import android.content.Context
import android.os.Build
import android.os.CombinedVibration
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.VibrationEffect.Composition.PRIMITIVE_CLICK
import android.os.VibrationEffect.Composition.PRIMITIVE_LOW_TICK
import android.os.VibrationEffect.Composition.PRIMITIVE_TICK
import android.os.VibratorManager
import android.provider.Settings
import android.view.HapticFeedbackConstants
import android.view.View

internal class RNHapticFeedback private constructor(
    context: Context,
    private val feedback: Int,
    vararg pulses: Pulse,
) {
    private class Pulse(val primitive: Int, val scale: Float, val onsetMs: Int = 0)

    private val manager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && pulses.isNotEmpty()) {
        context.applicationContext.getSystemService(VibratorManager::class.java)
    } else {
        null
    }
    private val vibration = compose(pulses)
    private val attributes = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && vibration != null) {
        VibrationAttributes.Builder().setUsage(VibrationAttributes.USAGE_TOUCH).build()
    } else {
        null
    }

    fun perform(view: View) {
        if (!view.isAttachedToWindow || !view.isHapticFeedbackEnabled) {
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && vibration != null) {
            // Android 13+ enforces this setting for USAGE_TOUCH in the vibration service.
            @Suppress("DEPRECATION")
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU &&
                Settings.System.getInt(
                    view.context.contentResolver,
                    Settings.System.HAPTIC_FEEDBACK_ENABLED,
                    0,
                ) == 0
            ) {
                return
            }

            manager?.vibrate(vibration, attributes)
        } else {
            view.performHapticFeedback(feedback)
        }
    }

    private fun compose(pulses: Array<out Pulse>): CombinedVibration? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return null
        }

        val vibrator = manager?.defaultVibrator ?: return null
        val durations = vibrator.getPrimitiveDurations(*IntArray(pulses.size) { pulses[it].primitive })
        val composition = VibrationEffect.startComposition()
        var previousEndMs = 0

        for ((index, pulse) in pulses.withIndex()) {
            val pauseMs = pulse.onsetMs - previousEndMs
            if (durations[index] <= 0 || pauseMs < 0) {
                return null
            }

            composition.addPrimitive(pulse.primitive, pulse.scale, pauseMs)
            previousEndMs = pulse.onsetMs + durations[index]
        }

        return CombinedVibration.createParallel(composition.compose())
    }

    companion object {
        fun fromName(context: Context, name: String?): RNHapticFeedback? = when (name) {
            "selection" -> RNHapticFeedback(
                context,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    HapticFeedbackConstants.SEGMENT_FREQUENT_TICK
                } else {
                    HapticFeedbackConstants.CLOCK_TICK
                },
                Pulse(PRIMITIVE_TICK, 0.7f),
            )
            "light" -> RNHapticFeedback(
                context,
                HapticFeedbackConstants.KEYBOARD_TAP,
                Pulse(PRIMITIVE_CLICK, 0.5f),
            )
            "medium" -> RNHapticFeedback(
                context,
                HapticFeedbackConstants.VIRTUAL_KEY,
                Pulse(PRIMITIVE_CLICK, 0.7f),
            )
            "heavy" -> RNHapticFeedback(
                context,
                HapticFeedbackConstants.LONG_PRESS,
                Pulse(PRIMITIVE_CLICK, 1f),
            )
            "soft" -> RNHapticFeedback(
                context,
                HapticFeedbackConstants.LONG_PRESS,
                Pulse(PRIMITIVE_LOW_TICK, 1f),
            )
            "rigid" -> RNHapticFeedback(context, HapticFeedbackConstants.CONTEXT_CLICK)
            "success" -> RNHapticFeedback(
                context,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    HapticFeedbackConstants.CONFIRM
                } else {
                    HapticFeedbackConstants.VIRTUAL_KEY
                },
                Pulse(PRIMITIVE_CLICK, 1f),
                Pulse(PRIMITIVE_TICK, 1f, 185),
            )
            "warning" -> RNHapticFeedback(
                context,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    HapticFeedbackConstants.REJECT
                } else {
                    HapticFeedbackConstants.LONG_PRESS
                },
                Pulse(PRIMITIVE_CLICK, 1f),
                Pulse(PRIMITIVE_CLICK, 1f, 215),
            )
            "error" -> RNHapticFeedback(
                context,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    HapticFeedbackConstants.REJECT
                } else {
                    HapticFeedbackConstants.LONG_PRESS
                },
                Pulse(PRIMITIVE_TICK, 1f),
                Pulse(PRIMITIVE_TICK, 0.85f, 100),
                Pulse(PRIMITIVE_CLICK, 0.8f, 200),
                Pulse(PRIMITIVE_LOW_TICK, 1f, 300),
            )
            else -> null
        }
    }
}
