package com.rninteractionprimitives

import android.widget.FrameLayout
import com.facebook.react.uimanager.ThemedReactContext

internal class RNSideDrawerPanelView(reactContext: ThemedReactContext) : FrameLayout(reactContext) {
    init {
        clipChildren = true
        clipToPadding = true
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        // UIManager measures and lays out the React-managed panel content.
        setMeasuredDimension(
            MeasureSpec.getSize(widthMeasureSpec),
            MeasureSpec.getSize(heightMeasureSpec),
        )
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) = Unit
}
