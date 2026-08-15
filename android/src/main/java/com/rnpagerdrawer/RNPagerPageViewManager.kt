package com.rnpagerdrawer

import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.ViewGroupManager
import com.facebook.react.uimanager.ViewManagerDelegate
import com.facebook.react.viewmanagers.RNPagerPageViewManagerDelegate
import com.facebook.react.viewmanagers.RNPagerPageViewManagerInterface

@ReactModule(name = RNPagerPageViewManager.REACT_CLASS)
internal class RNPagerPageViewManager :
    ViewGroupManager<RNPagerPageView>(),
    RNPagerPageViewManagerInterface<RNPagerPageView> {
    private val delegate: ViewManagerDelegate<RNPagerPageView> =
        RNPagerPageViewManagerDelegate<RNPagerPageView, RNPagerPageViewManager>(this)

    override fun getName(): String = REACT_CLASS

    override fun createViewInstance(reactContext: ThemedReactContext): RNPagerPageView = RNPagerPageView(reactContext)

    override fun getDelegate(): ViewManagerDelegate<RNPagerPageView> = delegate

    companion object {
        const val REACT_CLASS = "RNPagerPageView"
    }
}
