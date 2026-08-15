package com.rnpagerdrawer

import android.widget.FrameLayout
import com.facebook.react.uimanager.ThemedReactContext

internal class RNPagerPageView(reactContext: ThemedReactContext) : FrameLayout(reactContext) {
    init {
        clipChildren = true
        clipToPadding = true
    }
}
