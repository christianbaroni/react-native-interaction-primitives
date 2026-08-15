package com.rnpagerdrawer

import android.view.View
import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.ViewGroupManager
import com.facebook.react.uimanager.ViewManagerDelegate
import com.facebook.react.viewmanagers.RNSideDrawerContentViewManagerDelegate
import com.facebook.react.viewmanagers.RNSideDrawerContentViewManagerInterface

@ReactModule(name = RNSideDrawerContentViewManager.REACT_CLASS)
internal class RNSideDrawerContentViewManager :
    ViewGroupManager<RNSideDrawerContentView>(),
    RNSideDrawerContentViewManagerInterface<RNSideDrawerContentView> {
    private val delegate: ViewManagerDelegate<RNSideDrawerContentView> =
        RNSideDrawerContentViewManagerDelegate<RNSideDrawerContentView, RNSideDrawerContentViewManager>(this)

    override fun getName(): String = REACT_CLASS

    override fun createViewInstance(reactContext: ThemedReactContext): RNSideDrawerContentView =
        RNSideDrawerContentView(reactContext)

    override fun getDelegate(): ViewManagerDelegate<RNSideDrawerContentView> = delegate

    override fun addView(parent: RNSideDrawerContentView, child: View, index: Int) {
        parent.addReactChild(child, index)
    }

    override fun getChildCount(parent: RNSideDrawerContentView): Int = parent.reactChildCount()

    override fun getChildAt(parent: RNSideDrawerContentView, index: Int): View {
        return parent.getReactChildAt(index)
            ?: throw IndexOutOfBoundsException("RNSideDrawerContentView has no React child at index $index.")
    }

    override fun removeViewAt(parent: RNSideDrawerContentView, index: Int) {
        parent.removeReactChildAt(index)
    }

    companion object {
        const val REACT_CLASS = "RNSideDrawerContentView"
    }
}
