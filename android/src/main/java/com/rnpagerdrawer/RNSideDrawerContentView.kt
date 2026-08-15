package com.rnpagerdrawer

import android.graphics.Color
import android.view.View
import android.widget.FrameLayout
import com.facebook.react.uimanager.ThemedReactContext

internal class RNSideDrawerContentView(reactContext: ThemedReactContext) : FrameLayout(reactContext) {
    private val scrim = View(reactContext).apply {
        isClickable = false
        setBackgroundColor(Color.TRANSPARENT)
        setOnClickListener { onScrimPress?.invoke() }
    }

    var onScrimPress: (() -> Unit)? = null

    init {
        clipChildren = true
        clipToPadding = true
        super.addView(scrim, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
    }

    fun addReactChild(child: View, index: Int) {
        super.addView(child, index.coerceIn(0, childCount - 1))
        scrim.bringToFront()
    }

    fun getReactChildAt(index: Int): View? = if (index in 0 until childCount - 1) getChildAt(index) else null

    fun reactChildCount(): Int = childCount - 1

    fun removeReactChildAt(index: Int) {
        super.removeViewAt(index)
    }

    fun setDrawerProgress(progress: Float) {
        scrim.isClickable = progress > 0.001f
    }
}
