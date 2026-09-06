package com.rninteractionprimitives

import android.app.Activity
import android.content.Context
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
import android.view.ViewGroup
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.annotation.LooperMode
import org.robolectric.shadow.api.Shadow
import org.robolectric.shadows.ShadowVibrator
import org.robolectric.shadows.ShadowViewGroup
import org.robolectric.util.ReflectionHelpers.callInstanceMethod

@RunWith(RobolectricTestRunner::class)
@Config(
    sdk = [31, 34],
    manifest = Config.NONE,
    shadows = [RNHapticFeedbackTest.RecordingView::class, RNHapticFeedbackTest.RecordingVibratorManager::class],
)
@LooperMode(LooperMode.Mode.PAUSED)
class RNHapticFeedbackTest {
    private lateinit var context: Context
    private lateinit var view: View

    @Before
    @Suppress("DEPRECATION")
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        view = Robolectric.buildActivity(Activity::class.java).setup().get().window.decorView
        if (RuntimeEnvironment.getApiLevel() in 31..32) {
            Settings.System.putInt(context.contentResolver, Settings.System.HAPTIC_FEEDBACK_ENABLED, 1)
        }
    }

    @Test
    @Config(sdk = [24, 29, 30, 31, 34])
    fun fallsBackToPlatformFeedbackWithoutSupportedPrimitives() {
        val notificationFallback = if (RuntimeEnvironment.getApiLevel() >= 30) {
            HapticFeedbackConstants.REJECT
        } else {
            HapticFeedbackConstants.LONG_PRESS
        }
        val expected = linkedMapOf(
            "selection" to selectionFallback(),
            "soft" to HapticFeedbackConstants.LONG_PRESS,
            "light" to HapticFeedbackConstants.KEYBOARD_TAP,
            "medium" to HapticFeedbackConstants.VIRTUAL_KEY,
            "heavy" to HapticFeedbackConstants.LONG_PRESS,
            "rigid" to HapticFeedbackConstants.CONTEXT_CLICK,
            "success" to if (RuntimeEnvironment.getApiLevel() >= 30) {
                HapticFeedbackConstants.CONFIRM
            } else {
                HapticFeedbackConstants.VIRTUAL_KEY
            },
            "warning" to notificationFallback,
            "error" to notificationFallback,
        )

        for ((name, constant) in expected) {
            perform(name)
            assertEquals(name, constant, feedback().last())
        }

        assertEquals(expected.values.toList(), feedback())
        assertEquals(0, vibrationCount())
    }

    @Test
    fun playsTheAcceptedCompositionsWithTouchUsage() {
        usePrimitiveDurations()
        val expected = linkedMapOf(
            "selection" to VibrationEffect.startComposition()
                .addPrimitive(PRIMITIVE_TICK, 0.7f).compose(),
            "soft" to VibrationEffect.startComposition()
                .addPrimitive(PRIMITIVE_LOW_TICK, 1f).compose(),
            "light" to VibrationEffect.startComposition()
                .addPrimitive(PRIMITIVE_CLICK, 0.5f).compose(),
            "medium" to VibrationEffect.startComposition()
                .addPrimitive(PRIMITIVE_CLICK, 0.7f).compose(),
            "heavy" to VibrationEffect.startComposition()
                .addPrimitive(PRIMITIVE_CLICK, 1f).compose(),
            "success" to VibrationEffect.startComposition()
                .addPrimitive(PRIMITIVE_CLICK, 1f)
                .addPrimitive(PRIMITIVE_TICK, 1f, 174).compose(),
            "warning" to VibrationEffect.startComposition()
                .addPrimitive(PRIMITIVE_CLICK, 1f)
                .addPrimitive(PRIMITIVE_CLICK, 1f, 204).compose(),
            "error" to VibrationEffect.startComposition()
                .addPrimitive(PRIMITIVE_TICK, 1f)
                .addPrimitive(PRIMITIVE_TICK, 0.85f, 95)
                .addPrimitive(PRIMITIVE_CLICK, 0.8f, 95)
                .addPrimitive(PRIMITIVE_LOW_TICK, 1f, 89).compose(),
        )

        for ((name, effect) in expected) {
            perform(name)
            val recorded = recordingManager().vibrations.last()
            assertEquals(name, CombinedVibration.createParallel(effect), recorded.effect)
            assertEquals(VibrationAttributes.USAGE_TOUCH, recorded.attributes.usage)
            assertEquals(0, recorded.attributes.flags)
        }

        assertEquals(expected.size, vibrationCount())
        assertTrue(feedback().isEmpty())
        perform("rigid")
        assertEquals(listOf(HapticFeedbackConstants.CONTEXT_CLICK), feedback())
    }

    @Test
    fun missingLowTickOnlyDisablesSoftAndErrorCompositions() {
        usePrimitiveDurations(lowTick = 0)
        assertFallbacks(
            mapOf("soft" to HapticFeedbackConstants.LONG_PRESS, "error" to HapticFeedbackConstants.REJECT),
        )
    }

    @Test
    fun missingTickOnlyDisablesSelectionSuccessAndErrorCompositions() {
        usePrimitiveDurations(tick = 0)
        assertFallbacks(
            mapOf(
                "selection" to selectionFallback(),
                "success" to HapticFeedbackConstants.CONFIRM,
                "error" to HapticFeedbackConstants.REJECT,
            ),
        )
    }

    @Test
    fun missingClickPreservesSelectionAndSoftCompositions() {
        usePrimitiveDurations(click = 0)
        assertFallbacks(
            mapOf(
                "light" to HapticFeedbackConstants.KEYBOARD_TAP,
                "medium" to HapticFeedbackConstants.VIRTUAL_KEY,
                "heavy" to HapticFeedbackConstants.LONG_PRESS,
                "success" to HapticFeedbackConstants.CONFIRM,
                "warning" to HapticFeedbackConstants.REJECT,
                "error" to HapticFeedbackConstants.REJECT,
            ),
        )
    }

    @Test
    fun notificationCadenceIsIndependentOfPrimitiveDuration() {
        usePrimitiveDurations(click = 25, tick = 8, lowTick = 15)
        val expected = mapOf(
            "success" to listOf(0, 185),
            "warning" to listOf(0, 215),
            "error" to listOf(0, 100, 200, 300),
        )

        for ((name, onsets) in expected) {
            perform(name)
            assertEquals(name, onsets, onsetTimes(recordingManager().vibrations.last().effect))
        }

        assertEquals(expected.size, vibrationCount())
        assertTrue(feedback().isEmpty())
    }

    @Test
    fun acceptsAnExactFitAndFallsBackWhenPrimitivesOverlap() {
        usePrimitiveDurations(click = 215)
        perform("warning")
        assertEquals(listOf(0, 215), onsetTimes(recordingManager().vibrations.single().effect))

        usePrimitiveDurations(click = 216)
        perform("warning")
        perform("success")
        perform("error")
        perform("heavy")

        assertEquals(2, vibrationCount())
        assertEquals(
            listOf(
                HapticFeedbackConstants.REJECT,
                HapticFeedbackConstants.CONFIRM,
                HapticFeedbackConstants.REJECT,
            ),
            feedback(),
        )
    }

    @Test
    fun reusesThePreparedEffectAcrossPlayback() {
        usePrimitiveDurations()
        val haptic = requireNotNull(RNHapticFeedback.fromName(context, "success"))
        haptic.perform(view)
        val first = recordingManager().vibrations.single().effect

        usePrimitiveDurations(click = 0, tick = 0, lowTick = 0)
        haptic.perform(view)

        assertEquals(2, vibrationCount())
        assertSame(first, recordingManager().vibrations.last().effect)
        assertTrue(feedback().isEmpty())
    }

    @Test
    @Config(sdk = [31, 32])
    @Suppress("DEPRECATION")
    fun readsTheLegacyTouchFeedbackSettingAtPlayback() {
        usePrimitiveDurations()
        val haptic = requireNotNull(RNHapticFeedback.fromName(context, "selection"))

        Settings.System.putString(context.contentResolver, Settings.System.HAPTIC_FEEDBACK_ENABLED, null)
        haptic.perform(view)
        assertEquals(0, vibrationCount())

        for (setting in listOf(0, 1, 0)) {
            Settings.System.putInt(context.contentResolver, Settings.System.HAPTIC_FEEDBACK_ENABLED, setting)
            val previousCount = vibrationCount()
            haptic.perform(view)
            assertEquals(previousCount + setting, vibrationCount())
        }

        assertTrue(feedback().isEmpty())
    }

    @Test
    @Config(sdk = [24, 30, 31, 34])
    fun rejectsNullAndUnknownNames() {
        for (name in listOf(null, "", "unsupported", "Selection", "selection\u0000", "sélection")) {
            assertNull(name, RNHapticFeedback.fromName(context, name))
        }
    }

    @Test
    @Config(sdk = [24, 30, 31, 34])
    fun disabledAndDetachedViewsAreInert() {
        if (RuntimeEnvironment.getApiLevel() >= 31) {
            usePrimitiveDurations()
        }
        val detached = Robolectric.buildActivity(Activity::class.java).create().get().window.decorView
        assertFalse(detached.isAttachedToWindow)
        view.isHapticFeedbackEnabled = false

        for (name in listOf("selection", "rigid")) {
            val haptic = requireNotNull(RNHapticFeedback.fromName(context, name))
            haptic.perform(view)
            haptic.perform(detached)
        }

        assertTrue(feedback().isEmpty())
        assertTrue(Shadow.extract<RecordingView>(detached).feedback.isEmpty())
        assertEquals(0, vibrationCount())
    }

    private fun perform(name: String) = requireNotNull(RNHapticFeedback.fromName(context, name)).perform(view)

    private fun assertFallbacks(expected: Map<String, Int>) {
        val names = listOf("selection", "soft", "light", "medium", "heavy", "success", "warning", "error")

        for (name in names) {
            val previousCount = vibrationCount()
            perform(name)
            val constant = expected[name]
            assertEquals(name, previousCount + if (constant == null) 1 else 0, vibrationCount())
            if (constant != null) {
                assertEquals(name, constant, feedback().last())
            }
        }

        assertEquals(names.mapNotNull(expected::get), feedback())
    }

    private fun usePrimitiveDurations(click: Int = 11, tick: Int = 5, lowTick: Int = 12) {
        val manager = context.getSystemService(VibratorManager::class.java)
        val vibrator = Shadow.extract<ShadowVibrator>(manager.defaultVibrator)
        vibrator.setPrimitiveDurations(PRIMITIVE_CLICK, click)
        vibrator.setPrimitiveDurations(PRIMITIVE_TICK, tick)
        vibrator.setPrimitiveDurations(PRIMITIVE_LOW_TICK, lowTick)
    }

    private fun onsetTimes(vibration: CombinedVibration): List<Int> {
        val effect = callInstanceMethod<VibrationEffect>(vibration, "getEffect")
        val segments = callInstanceMethod<List<Any>>(effect, "getSegments")
        val vibrator = context.getSystemService(VibratorManager::class.java).defaultVibrator
        var elapsedMs = 0

        return segments.map { segment ->
            val primitive = callInstanceMethod<Int>(segment, "getPrimitiveId")
            val onsetMs = elapsedMs + callInstanceMethod<Int>(segment, "getDelay")
            elapsedMs = onsetMs + vibrator.getPrimitiveDurations(primitive).single()
            onsetMs
        }
    }

    private fun selectionFallback(): Int = if (RuntimeEnvironment.getApiLevel() >= 34) {
        HapticFeedbackConstants.SEGMENT_FREQUENT_TICK
    } else {
        HapticFeedbackConstants.CLOCK_TICK
    }

    private fun feedback(): List<Int> = Shadow.extract<RecordingView>(view).feedback

    private fun recordingManager(): RecordingVibratorManager =
        Shadow.extract(context.getSystemService(VibratorManager::class.java))

    private fun vibrationCount(): Int =
        if (RuntimeEnvironment.getApiLevel() >= 31) recordingManager().vibrations.size else 0

    @Implements(ViewGroup::class)
    class RecordingView : ShadowViewGroup() {
        val feedback = mutableListOf<Int>()

        @Implementation
        override fun performHapticFeedback(constant: Int): Boolean {
            feedback.add(constant)
            return true
        }
    }

    @Implements(VibratorManager::class, minSdk = 31)
    class RecordingVibratorManager {
        data class Vibration(val effect: CombinedVibration, val attributes: VibrationAttributes)

        val vibrations = mutableListOf<Vibration>()

        @Implementation
        fun vibrate(effect: CombinedVibration, attributes: VibrationAttributes) {
            vibrations.add(Vibration(effect, attributes))
        }
    }
}
