package com.rninteractionprimitives

import android.view.View
import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.uimanager.PixelUtil
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.ViewGroupManager
import com.facebook.react.uimanager.ViewManagerDelegate
import com.facebook.react.uimanager.annotations.ReactProp
import com.facebook.react.viewmanagers.RNPagerViewManagerDelegate
import com.facebook.react.viewmanagers.RNPagerViewManagerInterface

@ReactModule(name = RNPagerViewManager.REACT_CLASS)
internal class RNPagerViewManager :
    ViewGroupManager<RNPagerView>(),
    RNPagerViewManagerInterface<RNPagerView> {
    private val delegate: ViewManagerDelegate<RNPagerView> =
        RNPagerViewManagerDelegate<RNPagerView, RNPagerViewManager>(this)

    override fun getName(): String = REACT_CLASS

    override fun createViewInstance(reactContext: ThemedReactContext): RNPagerView = RNPagerView(reactContext)

    override fun getDelegate(): ViewManagerDelegate<RNPagerView> = delegate

    override fun needsCustomLayoutForChildren(): Boolean = true

    override fun addView(parent: RNPagerView, child: View, index: Int) {
        if (child is RNPagerPageView) parent.addPagerPage(child, index)
    }

    override fun getChildCount(parent: RNPagerView): Int = parent.pagerPageCount()

    override fun getChildAt(parent: RNPagerView, index: Int): View {
        return parent.getPagerPageAt(index)
            ?: throw IndexOutOfBoundsException("RNPagerView has no page at index $index.")
    }

    override fun removeViewAt(parent: RNPagerView, index: Int) {
        parent.removePagerPageAt(index)
    }

    override fun onDropViewInstance(view: RNPagerView) {
        view.prepareForRemoval()
        super.onDropViewInstance(view)
    }

    override fun getExportedCustomDirectEventTypeConstants(): MutableMap<String, Any> {
        val constants = super.getExportedCustomDirectEventTypeConstants() ?: HashMap()
        constants["topPageChange"] = mutableMapOf("registrationName" to "onPageChange")
        constants["topPageScroll"] = mutableMapOf("registrationName" to "onPageScroll")
        constants["topStateChange"] = mutableMapOf("registrationName" to "onStateChange")
        return constants
    }

    @ReactProp(name = "initialPage", defaultInt = 0)
    override fun setInitialPage(view: RNPagerView, value: Int) {
        view.initialPage = value
    }

    @ReactProp(name = "orientation")
    override fun setOrientation(view: RNPagerView, value: String?) {
        view.orientation = if (value == "vertical") RNPagerView.Orientation.Vertical else RNPagerView.Orientation.Horizontal
    }

    @ReactProp(name = "pageInset", defaultFloat = 0f)
    override fun setPageInset(view: RNPagerView, value: Float) {
        view.pageInsetPx = PixelUtil.toPixelFromDIP(value)
    }

    @ReactProp(name = "pageChangeEventsEnabled", defaultBoolean = false)
    override fun setPageChangeEventsEnabled(view: RNPagerView, value: Boolean) {
        view.pageChangeEventsEnabled = value
    }

    @ReactProp(name = "pageScrollEventsEnabled", defaultBoolean = false)
    override fun setPageScrollEventsEnabled(view: RNPagerView, value: Boolean) {
        view.pageScrollEventsEnabled = value
    }

    @ReactProp(name = "pageSpacing", defaultFloat = 0f)
    override fun setPageSpacing(view: RNPagerView, value: Float) {
        view.pageSpacingPx = PixelUtil.toPixelFromDIP(value)
    }

    @ReactProp(name = "scrollEnabled", defaultBoolean = true)
    override fun setScrollEnabled(view: RNPagerView, value: Boolean) {
        view.pagerScrollEnabled = value
    }

    @ReactProp(name = "stateEventsEnabled", defaultBoolean = false)
    override fun setStateEventsEnabled(view: RNPagerView, value: Boolean) {
        view.stateEventsEnabled = value
    }

    override fun requestPageScrollSnapshot(view: RNPagerView) {
        view.requestPageScrollSnapshot()
    }

    override fun setPage(view: RNPagerView, page: Int, animated: Boolean) {
        view.setPage(page, animated)
    }

    companion object {
        const val REACT_CLASS = "RNPagerView"
    }
}
