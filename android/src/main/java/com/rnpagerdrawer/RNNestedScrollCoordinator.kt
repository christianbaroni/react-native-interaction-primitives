package com.rnpagerdrawer

import android.view.View
import android.view.ViewGroup
import com.facebook.react.uimanager.TouchTargetHelper

internal class RNNestedScrollCoordinator(private val container: ViewGroup) {
    private val nativeTouchTarget = IntArray(1)

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
        while (view != null && view !== container) {
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
