package com.rninteractionprimitives

import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import com.facebook.react.uimanager.TouchTargetHelper
import com.facebook.react.uimanager.events.NativeGestureUtil

internal class RNNestedScrollCoordinator(private val container: ViewGroup) {
    private val nativeTouchTarget = IntArray(1)
    private var nativeGestureActive = false

    fun beginNativeGesture(event: MotionEvent) {
        if (nativeGestureActive) return
        nativeGestureActive = true
        NativeGestureUtil.notifyNativeGestureStarted(container, event)
    }

    fun endNativeGesture(event: MotionEvent) {
        if (!nativeGestureActive) return
        nativeGestureActive = false
        NativeGestureUtil.notifyNativeGestureEnded(container, event)
    }

    fun cancelNativeGesture() {
        if (!nativeGestureActive) return
        nativeGestureActive = false
        val now = SystemClock.uptimeMillis()
        val cancelEvent = MotionEvent.obtain(now, now, MotionEvent.ACTION_CANCEL, 0f, 0f, 0)
        try {
            NativeGestureUtil.notifyNativeGestureEnded(container, cancelEvent)
        } finally {
            cancelEvent.recycle()
        }
    }

    fun touchedDescendantCanScrollHorizontally(x: Float, y: Float, fingerDelta: Float): Boolean =
        touchedDescendantCanScroll(x, y, if (fingerDelta > 0f) -1 else 1, horizontal = true)

    fun touchedDescendantCanScrollVertically(x: Float, y: Float, fingerDelta: Float): Boolean =
        touchedDescendantCanScroll(x, y, if (fingerDelta > 0f) -1 else 1, horizontal = false)

    private fun touchedDescendantCanScroll(
        x: Float,
        y: Float,
        direction: Int,
        horizontal: Boolean,
    ): Boolean {
        nativeTouchTarget[0] = View.NO_ID
        TouchTargetHelper.findTargetTagForTouch(x, y, container, nativeTouchTarget)
        var view = if (nativeTouchTarget[0] == View.NO_ID) null else container.findViewById<View>(nativeTouchTarget[0])
        while (view != null && view !== container && view.id != View.NO_ID) {
            val canScroll = if (horizontal) {
                view.canScrollHorizontally(direction)
            } else {
                view.canScrollVertically(direction)
            }
            if (canScroll) return true
            view = view.parent as? View
        }
        return false
    }
}
