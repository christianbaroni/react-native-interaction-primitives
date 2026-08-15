package com.rnpagerdrawer

import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.widget.OverScroller
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.WritableMap
import com.facebook.react.uimanager.PixelUtil
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.UIManagerHelper
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

internal class RNSideDrawerView(private val reactContext: ThemedReactContext) : ViewGroup(reactContext) {
    enum class Side {
        Start,
        End,
    }

    private enum class Phase {
        Closed,
        Open,
        Dragging,
        Settling,
    }

    private enum class SettlingSource {
        None,
        Programmatic,
        Release,
    }

    private val slots = ArrayList<View>(2)
    private val scroller = OverScroller(reactContext)
    private val targetResolverScroller = OverScroller(reactContext)
    private val touchSlop = ViewConfiguration.get(reactContext).scaledTouchSlop
    private val maximumFlingVelocity = ViewConfiguration.get(reactContext).scaledMaximumFlingVelocity

    private var panelView: RNSideDrawerPanelView? = null
    private var contentView: RNSideDrawerContentView? = null
    private var phase = Phase.Closed
    private var settlingSource = SettlingSource.None
    private var targetOpen = false
    private var open = false
    private var lastEmittedOpen = false
    private var revealPx = 0f
    private var laidOutDrawerWidthPx = 0f
    private var hasLaidOut = false
    private var activePointerId = INVALID_POINTER_ID
    private var gestureEligible = false
    private var isDragging = false
    private var downX = 0f
    private var downY = 0f
    private var lastX = 0f
    private var interruptedRevealVelocityPxPerSecond = 0f
    private var velocityTracker: VelocityTracker? = null

    var drawerWidthPx: Float = 0f
        set(value) {
            val next = max(0f, value)
            if (field == next) return
            field = next
            requestLayout()
        }

    var edgeWidthPx: Float = PixelUtil.toPixelFromDIP(24f)
        set(value) {
            field = max(0f, value)
        }

    var gestureEnabled: Boolean = true
        set(value) {
            if (field == value) return
            field = value
            if (!value) {
                if (isDragging) settleToOpen(progress() >= 0.5f, SettlingSource.Release, true)
                finishTouch()
            }
        }

    var initialOpen: Boolean = false
        set(value) {
            field = value
            if (hasLaidOut) return
            open = value
            targetOpen = value
            phase = if (value) Phase.Open else Phase.Closed
        }

    var openChangeEventsEnabled: Boolean = false
    var progressEventsEnabled: Boolean = false

    var side: Side = Side.Start
        set(value) {
            if (field == value) return
            field = value
            requestLayout()
        }

    init {
        clipChildren = true
        clipToPadding = true
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val measuredWidth = MeasureSpec.getSize(widthMeasureSpec)
        val measuredHeight = MeasureSpec.getSize(heightMeasureSpec)
        setMeasuredDimension(measuredWidth, measuredHeight)

        val heightSpec = MeasureSpec.makeMeasureSpec(measuredHeight, MeasureSpec.EXACTLY)
        val panelWidthSpec = MeasureSpec.makeMeasureSpec(drawerWidthPx.roundToInt(), MeasureSpec.EXACTLY)
        val contentWidthSpec = MeasureSpec.makeMeasureSpec(measuredWidth, MeasureSpec.EXACTLY)
        panelView?.measure(panelWidthSpec, heightSpec)
        contentView?.measure(contentWidthSpec, heightSpec)
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        val firstLayout = !hasLaidOut
        val resumeSettling = phase == Phase.Settling
        if (resumeSettling) synchronizeScrollerFrame()
        val preservedProgress = if (firstLayout) {
            if (initialOpen) 1f else 0f
        } else if (laidOutDrawerWidthPx > 0f) {
            revealPx / laidOutDrawerWidthPx
        } else {
            0f
        }
        val settlingTarget = targetOpen
        if (resumeSettling) scroller.abortAnimation()

        laidOutDrawerWidthPx = drawerWidthPx
        val hostWidth = right - left
        val hostHeight = bottom - top
        if (revealDirection() > 0) {
            panelView?.layout(0, 0, laidOutDrawerWidthPx.roundToInt(), hostHeight)
        } else {
            val panelLeft = hostWidth - laidOutDrawerWidthPx.roundToInt()
            panelView?.layout(panelLeft, 0, hostWidth, hostHeight)
        }
        contentView?.layout(0, 0, hostWidth, hostHeight)
        hasLaidOut = true
        setRevealPx(preservedProgress * laidOutDrawerWidthPx)

        if (resumeSettling) {
            startSettle(settlingTarget, 0f)
        } else if (firstLayout) {
            open = preservedProgress >= 1f
            targetOpen = open
            lastEmittedOpen = open
            phase = if (open) Phase.Open else Phase.Closed
        }
    }

    override fun onInterceptTouchEvent(event: MotionEvent): Boolean {
        if (!gestureEnabled || laidOutDrawerWidthPx <= 0f) return false
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                val x = event.x
                gestureEligible = gestureCanStartAt(x)
                if (gestureEligible) initializeTouch(event)
            }
            MotionEvent.ACTION_MOVE -> {
                if (!gestureEligible) return false
                val pointerIndex = event.findPointerIndex(activePointerId)
                if (pointerIndex < 0) return false
                val deltaX = event.getX(pointerIndex) - downX
                val deltaY = event.getY(pointerIndex) - downY
                val revealDelta = deltaX * revealDirection()
                val canMove = (revealPx > 0f || revealDelta > 0f) &&
                    (revealPx < laidOutDrawerWidthPx || revealDelta < 0f)
                if (canMove && abs(deltaX) > touchSlop && abs(deltaX) > abs(deltaY)) {
                    beginDragging()
                    lastX = event.getX(pointerIndex)
                    parent?.requestDisallowInterceptTouchEvent(true)
                    return true
                }
            }
            MotionEvent.ACTION_CANCEL, MotionEvent.ACTION_UP -> finishTouch()
        }
        return false
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!gestureEnabled || !gestureEligible) return false
        ensureVelocityTracker().addMovement(event)
        when (event.actionMasked) {
            MotionEvent.ACTION_POINTER_UP -> handlePointerUp(event)
            MotionEvent.ACTION_MOVE -> {
                val pointerIndex = event.findPointerIndex(activePointerId)
                if (pointerIndex < 0) return false
                val x = event.getX(pointerIndex)
                if (isDragging) {
                    setRevealPx(revealPx + (x - lastX) * revealDirection())
                    lastX = x
                    publishProgress()
                }
                return true
            }
            MotionEvent.ACTION_UP -> {
                if (isDragging) {
                    val tracker = ensureVelocityTracker()
                    tracker.computeCurrentVelocity(1000, maximumFlingVelocity.toFloat())
                    val revealVelocity = tracker.getXVelocity(activePointerId) * revealDirection()
                    settleFromRelease(revealVelocity)
                }
                finishTouch()
                return true
            }
            MotionEvent.ACTION_CANCEL -> {
                if (isDragging) settleToOpen(progress() >= 0.5f, SettlingSource.Release, true)
                finishTouch()
                return true
            }
        }
        return true
    }

    override fun computeScroll() {
        if (phase != Phase.Settling) return
        if (scroller.computeScrollOffset()) {
            setRevealPx(scroller.currX.toFloat())
            publishProgress()
            postInvalidateOnAnimation()
            return
        }
        finishAtOpen(targetOpen)
    }

    override fun onDetachedFromWindow() {
        if (phase == Phase.Settling) synchronizeScrollerFrame()
        scroller.abortAnimation()
        when (phase) {
            Phase.Dragging -> finishAtOpen(progress() >= 0.5f)
            Phase.Settling -> finishAtOpen(targetOpen)
            Phase.Closed, Phase.Open -> Unit
        }
        finishTouch()
        super.onDetachedFromWindow()
    }

    fun addDrawerSlot(child: View, index: Int) {
        if (child !is RNSideDrawerPanelView && child !is RNSideDrawerContentView) return
        val boundedIndex = index.coerceIn(0, slots.size)
        slots.add(boundedIndex, child)
        super.addView(child, boundedIndex, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        when (child) {
            is RNSideDrawerPanelView -> panelView = child
            is RNSideDrawerContentView -> {
                contentView = child
                child.onScrimPress = { close(true) }
                child.bringToFront()
            }
        }
        requestLayout()
    }

    fun drawerSlotCount(): Int = slots.size

    fun getDrawerSlotAt(index: Int): View? = slots.getOrNull(index)

    fun removeDrawerSlotAt(index: Int) {
        val child = slots.removeAt(index)
        if (child === panelView) panelView = null
        if (child === contentView) {
            contentView?.onScrimPress = null
            contentView = null
        }
        super.removeView(child)
    }

    fun open(animated: Boolean) {
        setOpen(true, animated)
    }

    fun close(animated: Boolean) {
        setOpen(false, animated)
    }

    fun toggle(animated: Boolean) {
        val nextOpen = if (phase == Phase.Settling) !targetOpen else progress() < 0.5f
        setOpen(nextOpen, animated)
    }

    fun prepareForRemoval() {
        scroller.abortAnimation()
        finishTouch()
        contentView?.onScrimPress = null
        slots.clear()
        removeAllViews()
        panelView = null
        contentView = null
        hasLaidOut = false
        revealPx = 0f
        open = false
        targetOpen = false
        phase = Phase.Closed
        settlingSource = SettlingSource.None
    }

    private fun setOpen(nextOpen: Boolean, animated: Boolean) {
        if (!hasLaidOut) {
            initialOpen = nextOpen
            open = nextOpen
            targetOpen = nextOpen
            phase = if (nextOpen) Phase.Open else Phase.Closed
            requestLayout()
            emitOpenChangeIfNeeded()
            return
        }
        if (phase == Phase.Settling) synchronizeScrollerFrame()
        if (isDragging) finishTouch()
        settleToOpen(nextOpen, SettlingSource.Programmatic, animated)
    }

    private fun settleFromRelease(velocityPxPerSecond: Float) {
        val resolvedVelocity = velocityPxPerSecond + interruptedRevealVelocityPxPerSecond
        interruptedRevealVelocityPxPerSecond = 0f
        val naturalReveal = naturalTargetReveal(revealPx, resolvedVelocity)
        settleToOpen(naturalReveal >= laidOutDrawerWidthPx * 0.5f, SettlingSource.Release, true, resolvedVelocity)
    }

    private fun settleToOpen(
        nextOpen: Boolean,
        source: SettlingSource,
        animated: Boolean,
        releaseVelocityPxPerSecond: Float = 0f,
    ) {
        targetOpen = nextOpen
        settlingSource = source
        phase = Phase.Settling
        publishProgress()
        scroller.abortAnimation()
        if (!animated || abs(revealPx - targetReveal(nextOpen)) <= 0.5f) {
            finishAtOpen(nextOpen)
            return
        }
        startSettle(nextOpen, if (source == SettlingSource.Release) releaseVelocityPxPerSecond else 0f)
    }

    private fun startSettle(nextOpen: Boolean, velocityPxPerSecond: Float) {
        val start = revealPx.roundToInt()
        val end = targetReveal(nextOpen).roundToInt()
        scroller.abortAnimation()
        if (!startReleaseFling(start, end, velocityPxPerSecond)) {
            scroller.startScroll(start, 0, end - start, 0)
        }
        postInvalidateOnAnimation()
    }

    private fun startReleaseFling(start: Int, end: Int, velocityPxPerSecond: Float): Boolean {
        val distance = end - start
        if (distance == 0 || velocityPxPerSecond * distance <= 0f) return false
        scroller.fling(
            start,
            0,
            velocityPxPerSecond.roundToInt(),
            0,
            min(start, end),
            max(start, end),
            0,
            0,
        )
        if (scroller.finalX == end) return true
        scroller.abortAnimation()
        return false
    }

    private fun naturalTargetReveal(currentReveal: Float, velocityPxPerSecond: Float): Float {
        val maximum = laidOutDrawerWidthPx.roundToInt()
        targetResolverScroller.forceFinished(true)
        targetResolverScroller.fling(
            currentReveal.roundToInt(),
            0,
            velocityPxPerSecond.roundToInt(),
            0,
            0,
            maximum,
            0,
            0,
        )
        return targetResolverScroller.finalX.toFloat()
    }

    private fun finishAtOpen(nextOpen: Boolean) {
        scroller.abortAnimation()
        revealPx = targetReveal(nextOpen)
        open = nextOpen
        targetOpen = nextOpen
        phase = if (nextOpen) Phase.Open else Phase.Closed
        settlingSource = SettlingSource.None
        interruptedRevealVelocityPxPerSecond = 0f
        applyProgress()
        publishProgress()
        emitOpenChangeIfNeeded()
    }

    private fun initializeTouch(event: MotionEvent) {
        velocityTracker?.recycle()
        velocityTracker = VelocityTracker.obtain().also { it.addMovement(event) }
        activePointerId = event.getPointerId(0)
        downX = event.x
        downY = event.y
        lastX = downX
        isDragging = false
    }

    private fun beginDragging() {
        if (isDragging) return
        val interruptedTarget = if (phase == Phase.Settling) targetOpen else open
        if (phase == Phase.Settling) synchronizeScrollerFrame()
        val interruptedVelocity = if (phase == Phase.Settling && !scroller.isFinished) {
            currentScrollerVelocityPxPerSecond()
        } else {
            0f
        }
        scroller.abortAnimation()
        isDragging = true
        targetOpen = interruptedTarget
        interruptedRevealVelocityPxPerSecond = interruptedVelocity
        settlingSource = SettlingSource.None
        phase = Phase.Dragging
        publishProgress()
    }

    private fun finishTouch() {
        activePointerId = INVALID_POINTER_ID
        gestureEligible = false
        isDragging = false
        velocityTracker?.recycle()
        velocityTracker = null
    }

    private fun handlePointerUp(event: MotionEvent) {
        val actionIndex = event.actionIndex
        if (event.getPointerId(actionIndex) != activePointerId) return
        val nextIndex = if (actionIndex == 0) 1 else 0
        activePointerId = event.getPointerId(nextIndex)
        lastX = event.getX(nextIndex)
        downX = lastX
        downY = event.getY(nextIndex)
        velocityTracker?.clear()
    }

    private fun synchronizeScrollerFrame() {
        if (!scroller.computeScrollOffset()) return
        setRevealPx(scroller.currX.toFloat())
        publishProgress()
    }

    private fun currentScrollerVelocityPxPerSecond(): Float {
        val remaining = targetReveal(targetOpen) - revealPx
        if (remaining == 0f) return 0f
        return scroller.currVelocity * if (remaining > 0f) 1f else -1f
    }

    private fun gestureCanStartAt(x: Float): Boolean {
        val currentProgress = progress()
        if (currentProgress <= 0.001f) {
            return if (revealDirection() > 0) x <= edgeWidthPx else x >= width - edgeWidthPx
        }
        return pointIsOnContent(x, currentProgress)
    }

    private fun pointIsOnContent(x: Float, currentProgress: Float): Boolean {
        val revealed = currentProgress * laidOutDrawerWidthPx
        return if (revealDirection() > 0) x >= revealed else x <= width - revealed
    }

    private fun revealDirection(): Int {
        val isRtl = layoutDirection == LAYOUT_DIRECTION_RTL
        val revealsLeft = (side == Side.Start) != isRtl
        return if (revealsLeft) 1 else -1
    }

    private fun setRevealPx(value: Float) {
        revealPx = value.coerceIn(0f, laidOutDrawerWidthPx)
        applyProgress()
    }

    private fun applyProgress() {
        val currentProgress = progress()
        contentView?.translationX = revealDirection() * revealPx
        contentView?.setDrawerProgress(currentProgress)
        panelView?.isEnabled = currentProgress > 0.001f
        when {
            currentProgress <= 0.001f -> {
                panelView?.importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
                contentView?.importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_AUTO
            }
            currentProgress >= 0.999f -> {
                panelView?.importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_AUTO
                contentView?.importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            }
            else -> {
                panelView?.importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_AUTO
                contentView?.importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_AUTO
            }
        }
    }

    private fun progress(): Float {
        return if (laidOutDrawerWidthPx > 0f) (revealPx / laidOutDrawerWidthPx).coerceIn(0f, 1f) else 0f
    }

    private fun targetReveal(nextOpen: Boolean): Float = if (nextOpen) laidOutDrawerWidthPx else 0f

    private fun phaseName(): String = when (phase) {
        Phase.Closed -> "closed"
        Phase.Open -> "open"
        Phase.Dragging -> "dragging"
        Phase.Settling -> "settling"
    }

    private fun settlingSourceName(): String {
        if (phase != Phase.Settling) return "none"
        return when (settlingSource) {
            SettlingSource.None -> "none"
            SettlingSource.Programmatic -> "programmatic"
            SettlingSource.Release -> "release"
        }
    }

    private fun progressPayload(): WritableMap {
        return Arguments.createMap().apply {
            putString("phase", phaseName())
            putDouble("progress", progress().toDouble())
            putString("settlingSource", settlingSourceName())
            putBoolean("targetOpen", targetOpen)
        }
    }

    private fun publishProgress() {
        if (!progressEventsEnabled) return
        dispatchEvent("topProgress", progressPayload(), coalesces = true)
    }

    private fun emitOpenChangeIfNeeded() {
        if (lastEmittedOpen == open) return
        lastEmittedOpen = open
        if (!openChangeEventsEnabled) return
        val payload = Arguments.createMap()
        payload.putBoolean("open", open)
        dispatchEvent("topOpenChange", payload, coalesces = false)
    }

    private fun dispatchEvent(eventName: String, payload: WritableMap, coalesces: Boolean) {
        val tag = id
        if (tag == View.NO_ID) return
        UIManagerHelper.getEventDispatcherForReactTag(reactContext, tag)
            ?.dispatchEvent(RNDirectEvent(UIManagerHelper.getSurfaceId(this), tag, eventName, payload, coalesces))
    }

    private fun ensureVelocityTracker(): VelocityTracker {
        return velocityTracker ?: VelocityTracker.obtain().also { velocityTracker = it }
    }

    private companion object {
        const val INVALID_POINTER_ID = -1
    }
}
