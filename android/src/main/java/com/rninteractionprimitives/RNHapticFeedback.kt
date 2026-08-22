package com.rninteractionprimitives

import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View

internal enum class RNHapticFeedback {
    Selection,
    Light,
    Medium,
    Heavy,
    Soft,
    Rigid,
    Success,
    Warning,
    Error;

    fun perform(view: View) {
        val feedback = when (this) {
            Selection -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                HapticFeedbackConstants.SEGMENT_TICK
            } else {
                HapticFeedbackConstants.CLOCK_TICK
            }
            Light -> HapticFeedbackConstants.KEYBOARD_TAP
            Medium -> HapticFeedbackConstants.VIRTUAL_KEY
            Heavy -> HapticFeedbackConstants.LONG_PRESS
            Soft -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                HapticFeedbackConstants.SEGMENT_FREQUENT_TICK
            } else {
                HapticFeedbackConstants.CLOCK_TICK
            }
            Rigid -> HapticFeedbackConstants.CONTEXT_CLICK
            Success -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                HapticFeedbackConstants.CONFIRM
            } else {
                HapticFeedbackConstants.VIRTUAL_KEY
            }
            Warning -> HapticFeedbackConstants.CONTEXT_CLICK
            Error -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                HapticFeedbackConstants.REJECT
            } else {
                HapticFeedbackConstants.LONG_PRESS
            }
        }
        view.performHapticFeedback(feedback)
    }

    companion object {
        fun fromName(name: String?): RNHapticFeedback? = when (name) {
            "selection" -> Selection
            "light" -> Light
            "medium" -> Medium
            "heavy" -> Heavy
            "soft" -> Soft
            "rigid" -> Rigid
            "success" -> Success
            "warning" -> Warning
            "error" -> Error
            else -> null
        }
    }
}
