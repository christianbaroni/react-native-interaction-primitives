package com.rninteractionprimitives

import android.view.View
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.uimanager.PixelUtil
import com.facebook.react.uimanager.PointerEvents
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.ViewGroupManager
import com.facebook.react.uimanager.ViewManagerDelegate
import com.facebook.react.uimanager.ViewProps
import com.facebook.react.uimanager.annotations.ReactProp
import com.facebook.react.viewmanagers.RNSideDrawerViewManagerDelegate
import com.facebook.react.viewmanagers.RNSideDrawerViewManagerInterface

@ReactModule(name = RNSideDrawerViewManager.REACT_CLASS)
internal class RNSideDrawerViewManager :
    ViewGroupManager<RNSideDrawerView>(),
    RNSideDrawerViewManagerInterface<RNSideDrawerView> {
    private val delegate: ViewManagerDelegate<RNSideDrawerView> =
        object : ViewManagerDelegate<RNSideDrawerView> {
            private val generated =
                RNSideDrawerViewManagerDelegate<RNSideDrawerView, RNSideDrawerViewManager>(this@RNSideDrawerViewManager)

            override fun setProperty(view: RNSideDrawerView, propName: String, value: Any?) {
                // The generated delegate does not dispatch this inherited view prop.
                if (propName == ViewProps.POINTER_EVENTS) {
                    setPointerEvents(view, value as String?)
                } else {
                    generated.setProperty(view, propName, value)
                }
            }

            override fun receiveCommand(view: RNSideDrawerView, commandName: String, args: ReadableArray) {
                generated.receiveCommand(view, commandName, args)
            }
        }

    override fun getName(): String = REACT_CLASS

    override fun createViewInstance(reactContext: ThemedReactContext): RNSideDrawerView = RNSideDrawerView(reactContext)

    override fun getDelegate(): ViewManagerDelegate<RNSideDrawerView> = delegate

    override fun needsCustomLayoutForChildren(): Boolean = true

    override fun onAfterUpdateTransaction(view: RNSideDrawerView) {
        super.onAfterUpdateTransaction(view)
        view.flushPendingProgressSnapshot()
    }

    override fun addView(parent: RNSideDrawerView, child: View, index: Int) {
        parent.addDrawerSlot(child, index)
    }

    override fun getChildCount(parent: RNSideDrawerView): Int = parent.drawerSlotCount()

    override fun getChildAt(parent: RNSideDrawerView, index: Int): View {
        return parent.getDrawerSlotAt(index)
            ?: throw IndexOutOfBoundsException("RNSideDrawerView has no slot at index $index.")
    }

    override fun removeViewAt(parent: RNSideDrawerView, index: Int) {
        parent.removeDrawerSlotAt(index)
    }

    override fun onDropViewInstance(view: RNSideDrawerView) {
        view.prepareForRemoval()
        super.onDropViewInstance(view)
    }

    override fun getExportedCustomDirectEventTypeConstants(): MutableMap<String, Any> {
        val constants = super.getExportedCustomDirectEventTypeConstants() ?: HashMap()
        constants["topProgress"] = mutableMapOf("registrationName" to "onProgress")
        constants["topTransitionEnd"] = mutableMapOf("registrationName" to "onTransitionEnd")
        constants["topTransitionStart"] = mutableMapOf("registrationName" to "onTransitionStart")
        return constants
    }

    @ReactProp(name = ViewProps.POINTER_EVENTS)
    fun setPointerEvents(view: RNSideDrawerView, value: String?) {
        view.pointerEvents = PointerEvents.parsePointerEvents(value)
    }

    @ReactProp(name = "drawerWidth")
    override fun setDrawerWidth(view: RNSideDrawerView, value: Float) {
        view.drawerWidthPx = PixelUtil.toPixelFromDIP(value)
    }

    @ReactProp(name = "contentBorderColor", customType = "Color")
    override fun setContentBorderColor(view: RNSideDrawerView, value: Int?) {
        view.contentBorderColor = value ?: 0
    }

    @ReactProp(name = "contentBorderWidth", defaultFloat = 0f)
    override fun setContentBorderWidth(view: RNSideDrawerView, value: Float) {
        view.contentBorderWidthPx = PixelUtil.toPixelFromDIP(value)
    }

    @ReactProp(name = "contentCornerRadius", defaultFloat = -1f)
    override fun setContentCornerRadius(view: RNSideDrawerView, value: Float) {
        view.contentCornerRadiusPx = if (value < 0f) value else PixelUtil.toPixelFromDIP(value)
    }

    @ReactProp(name = "contentShadowColor", customType = "Color")
    override fun setContentShadowColor(view: RNSideDrawerView, value: Int?) {
        view.contentShadowColor = value ?: 0
    }

    @ReactProp(name = "contentShadowElevation", defaultFloat = 0f)
    override fun setContentShadowElevation(view: RNSideDrawerView, value: Float) {
        view.contentShadowElevationPx = PixelUtil.toPixelFromDIP(value)
    }

    @ReactProp(name = "contentShadowOffsetX", defaultFloat = 0f)
    override fun setContentShadowOffsetX(view: RNSideDrawerView, value: Float) = Unit

    @ReactProp(name = "contentShadowOffsetY", defaultFloat = 0f)
    override fun setContentShadowOffsetY(view: RNSideDrawerView, value: Float) = Unit

    @ReactProp(name = "contentShadowRadius", defaultFloat = 0f)
    override fun setContentShadowRadius(view: RNSideDrawerView, value: Float) = Unit

    @ReactProp(name = "gestureEnabled", defaultBoolean = true)
    override fun setGestureEnabled(view: RNSideDrawerView, value: Boolean) {
        view.gestureEnabled = value
    }

    @ReactProp(name = "gestureReleaseHaptic")
    override fun setGestureReleaseHaptic(view: RNSideDrawerView, value: String?) {
        view.gestureReleaseHaptic = RNHapticFeedback.fromName(view.context, value)
    }

    @ReactProp(name = "initialOpen", defaultBoolean = false)
    override fun setInitialOpen(view: RNSideDrawerView, value: Boolean) {
        view.initialOpen = value
    }

    @ReactProp(name = "motionConfig")
    override fun setMotionConfig(view: RNSideDrawerView, value: ReadableArray?) {
        view.setMotionConfig(value)
    }

    @ReactProp(name = "overdrag", defaultDouble = 4.0)
    override fun setOverdrag(view: RNSideDrawerView, value: Double) {
        view.overdragPx = PixelUtil.toPixelFromDIP(value)
    }

    @ReactProp(name = "overlayColor", customType = "Color")
    override fun setOverlayColor(view: RNSideDrawerView, value: Int?) {
        view.setOverlayColor(value)
    }

    @ReactProp(name = "progressEventsEnabled", defaultBoolean = false)
    override fun setProgressEventsEnabled(view: RNSideDrawerView, value: Boolean) {
        view.progressEventsEnabled = value
    }

    @ReactProp(name = "releaseOpenThreshold", defaultDouble = 0.5)
    override fun setReleaseOpenThreshold(view: RNSideDrawerView, value: Double) {
        view.releaseOpenThreshold = value
    }

    @ReactProp(name = "releaseVelocitySensitivity", defaultDouble = 1.0)
    override fun setReleaseVelocitySensitivity(view: RNSideDrawerView, value: Double) {
        view.releaseVelocitySensitivity = value
    }

    @ReactProp(name = "releaseVelocityTransfer", defaultDouble = 1.0)
    override fun setReleaseVelocityTransfer(view: RNSideDrawerView, value: Double) {
        view.releaseVelocityTransfer = value
    }

    @ReactProp(name = "side")
    override fun setSide(view: RNSideDrawerView, value: String?) {
        view.side = if (value == "end") RNSideDrawerView.Side.End else RNSideDrawerView.Side.Start
    }

    @ReactProp(name = "springDamping", defaultDouble = DEFAULT_SIDE_DRAWER_SPRING_DAMPING)
    override fun setSpringDamping(view: RNSideDrawerView, value: Double) {
        view.springDamping = value
    }

    @ReactProp(name = "springMass", defaultDouble = DEFAULT_SIDE_DRAWER_SPRING_MASS)
    override fun setSpringMass(view: RNSideDrawerView, value: Double) {
        view.springMass = value
    }

    @ReactProp(name = "springStiffness", defaultDouble = DEFAULT_SIDE_DRAWER_SPRING_STIFFNESS)
    override fun setSpringStiffness(view: RNSideDrawerView, value: Double) {
        view.springStiffness = value
    }

    @ReactProp(name = "transitionEndEventsEnabled", defaultBoolean = false)
    override fun setTransitionEndEventsEnabled(view: RNSideDrawerView, value: Boolean) {
        view.transitionEndEventsEnabled = value
    }

    @ReactProp(name = "transitionStartEventsEnabled", defaultBoolean = false)
    override fun setTransitionStartEventsEnabled(view: RNSideDrawerView, value: Boolean) {
        view.transitionStartEventsEnabled = value
    }

    override fun close(view: RNSideDrawerView, animated: Boolean) {
        view.close(animated)
    }

    override fun open(view: RNSideDrawerView, animated: Boolean) {
        view.open(animated)
    }

    override fun toggle(view: RNSideDrawerView, animated: Boolean) {
        view.toggle(animated)
    }

    companion object {
        const val REACT_CLASS = "RNSideDrawerView"
    }
}
