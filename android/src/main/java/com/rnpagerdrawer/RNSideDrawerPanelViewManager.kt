package com.rnpagerdrawer

import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.ViewGroupManager
import com.facebook.react.uimanager.ViewManagerDelegate
import com.facebook.react.viewmanagers.RNSideDrawerPanelViewManagerDelegate
import com.facebook.react.viewmanagers.RNSideDrawerPanelViewManagerInterface

@ReactModule(name = RNSideDrawerPanelViewManager.REACT_CLASS)
internal class RNSideDrawerPanelViewManager :
    ViewGroupManager<RNSideDrawerPanelView>(),
    RNSideDrawerPanelViewManagerInterface<RNSideDrawerPanelView> {
    private val delegate: ViewManagerDelegate<RNSideDrawerPanelView> =
        RNSideDrawerPanelViewManagerDelegate<RNSideDrawerPanelView, RNSideDrawerPanelViewManager>(this)

    override fun getName(): String = REACT_CLASS

    override fun createViewInstance(reactContext: ThemedReactContext): RNSideDrawerPanelView =
        RNSideDrawerPanelView(reactContext)

    override fun getDelegate(): ViewManagerDelegate<RNSideDrawerPanelView> = delegate

    companion object {
        const val REACT_CLASS = "RNSideDrawerPanelView"
    }
}
