package com.rnpagerdrawer

import android.graphics.Color
import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.widget.OverScroller
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.bridge.WritableMap
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.UIManagerHelper
import kotlin.math.abs
import kotlin.math.max
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

    private class MotionSegment(
        val upperInput: Float,
        val slope: Float,
        val intercept: Float,
    )

    private class MotionInterpolation(
        val firstInput: Float,
        val firstOutput: Float,
        val lastInput: Float,
        val lastOutput: Float,
        val segments: Array<MotionSegment>,
    ) {
        fun evaluate(progress: Float): Float {
            if (progress <= firstInput) return firstOutput
            if (progress >= lastInput) return lastOutput
            for (segment in segments) {
                if (progress <= segment.upperInput) return segment.slope * progress + segment.intercept
            }
            return lastOutput
        }
    }

    private val slots = ArrayList<View>(2)
    private val targetResolverScroller = OverScroller(reactContext)
    private val viewConfiguration = ViewConfiguration.get(reactContext)
    private val touchSlop = viewConfiguration.scaledTouchSlop
    private val maximumFlingVelocity = viewConfiguration.scaledMaximumFlingVelocity

    private var panelView: RNSideDrawerPanelView? = null
    private var contentView: RNSideDrawerContentView? = null
    private var phase = Phase.Closed
    private var settlingSource = SettlingSource.None
    private var targetOpen = false
    private var open = false
    private var lastEmittedOpen = false
    private var rawRevealPx = 0f
    private var laidOutDrawerWidthPx = 0f
    private var hasLaidOut = false
    private var activePointerId = INVALID_POINTER_ID
    private var gestureEligible = false
    private var isDragging = false
    private var hasDragged = false
    private var downX = 0f
    private var downY = 0f
    private var dragStartX = 0f
    private var dragStartRawRevealPx = 0f
    private var settleStartTimeNanos = 0L
    private var settleStartRawRevealPx = 0f
    private var settleInitialVelocityPxPerSecond = 0f
    private var settleVelocityPxPerSecond = 0f
    private var settleRunning = false
    private var velocityTracker: VelocityTracker? = null
    private var motion = arrayOfNulls<MotionInterpolation>(MOTION_CHANNEL_COUNT)
    private var overlayColor = Color.TRANSPARENT

    var drawerWidthPx: Float = 0f
        set(value) {
            val next = max(0f, value)
            if (field == next) return
            field = next
            requestLayout()
        }

    var contentCornerRadiusPx: Float = -1f
        set(value) {
            if (field == value) return
            field = value
            contentView?.contentCornerRadiusPx = value
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

    var gestureReleaseHaptic: RNHapticFeedback? = null

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
        val contentWidthSpec = MeasureSpec.makeMeasureSpec(measuredWidth, MeasureSpec.EXACTLY)
        panelView?.measure(contentWidthSpec, heightSpec)
        contentView?.measure(contentWidthSpec, heightSpec)
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        val firstLayout = !hasLaidOut
        val settlingBeforeLayout = phase == Phase.Settling
        if (settlingBeforeLayout) synchronizeSettleFrame()
        val resumeSettling = phase == Phase.Settling
        val resumeVelocity = if (resumeSettling) settleVelocityPxPerSecond else 0f
        val preservedRawFraction = if (firstLayout) {
            if (initialOpen) 1f else 0f
        } else if (laidOutDrawerWidthPx > 0f) {
            rawRevealPx / laidOutDrawerWidthPx
        } else {
            0f
        }
        settleRunning = false

        laidOutDrawerWidthPx = drawerWidthPx
        val hostWidth = right - left
        val hostHeight = bottom - top
        panelView?.layout(0, 0, hostWidth, hostHeight)
        contentView?.layout(0, 0, hostWidth, hostHeight)
        hasLaidOut = true
        rawRevealPx = preservedRawFraction * laidOutDrawerWidthPx
        applyProgress()

        if (resumeSettling) {
            startSettle(resumeVelocity)
        } else if (firstLayout) {
            open = preservedRawFraction >= 1f
            targetOpen = open
            lastEmittedOpen = open
            phase = if (open) Phase.Open else Phase.Closed
        }
    }

    override fun onInterceptTouchEvent(event: MotionEvent): Boolean {
        if (!gestureEnabled || laidOutDrawerWidthPx <= 0f) return false
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                gestureEligible = true
                initializeTouch(event)
                if (phase == Phase.Settling) {
                    beginDragging(event.x)
                    parent?.requestDisallowInterceptTouchEvent(true)
                    return true
                }
            }
            MotionEvent.ACTION_MOVE -> {
                if (!gestureEligible) return false
                val pointerIndex = event.findPointerIndex(activePointerId)
                if (pointerIndex < 0) return false
                val deltaX = event.getX(pointerIndex) - downX
                val deltaY = event.getY(pointerIndex) - downY
                val revealDelta = deltaX * revealDirection()
                val canMove = (rawRevealPx > 0f || revealDelta > 0f) &&
                    (rawRevealPx < laidOutDrawerWidthPx || revealDelta < 0f)
                if (canMove && abs(deltaX) > touchSlop && abs(deltaX) > abs(deltaY)) {
                    beginDragging(event.getX(pointerIndex))
                    hasDragged = true
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
                    val deltaX = x - dragStartX
                    val deltaY = event.getY(pointerIndex) - downY
                    if (abs(deltaX) > touchSlop && abs(deltaX) > abs(deltaY)) hasDragged = true
                    setDragRawRevealPx(dragStartRawRevealPx + (x - dragStartX) * revealDirection())
                    publishProgress()
                }
                return true
            }
            MotionEvent.ACTION_UP -> {
                if (isDragging) {
                    val tracker = ensureVelocityTracker()
                    tracker.computeCurrentVelocity(1000, maximumFlingVelocity.toFloat())
                    val revealVelocity = tracker.getXVelocity(activePointerId) * revealDirection()
                    settleFromRelease(revealVelocity, hasDragged)
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
        if (phase != Phase.Settling || !settleRunning) return
        if (updateSettleFrame(System.nanoTime())) postInvalidateOnAnimation()
    }

    override fun onDetachedFromWindow() {
        if (phase == Phase.Settling) synchronizeSettleFrame()
        settleRunning = false
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
                child.contentCornerRadiusPx = contentCornerRadiusPx
                child.setDrawerOverlayColor(overlayColor)
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

    fun setMotionConfig(config: ReadableArray?) {
        motion = compileMotion(config) ?: arrayOfNulls(MOTION_CHANNEL_COUNT)
        if (hasLaidOut) applyProgress()
    }

    fun setOverlayColor(color: Int?) {
        overlayColor = color ?: Color.TRANSPARENT
        contentView?.setDrawerOverlayColor(overlayColor)
    }

    fun close(animated: Boolean) {
        setOpen(false, animated)
    }

    fun toggle(animated: Boolean) {
        val nextOpen = if (phase == Phase.Settling) !targetOpen else progress() < 0.5f
        setOpen(nextOpen, animated)
    }

    fun prepareForRemoval() {
        settleRunning = false
        finishTouch()
        contentView?.onScrimPress = null
        slots.clear()
        removeAllViews()
        panelView = null
        contentView = null
        hasLaidOut = false
        rawRevealPx = 0f
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
        if (phase == Phase.Settling) synchronizeSettleFrame()
        val initialVelocity = if (phase == Phase.Settling) settleVelocityPxPerSecond else 0f
        settleRunning = false
        if (isDragging) finishTouch()
        settleToOpen(nextOpen, SettlingSource.Programmatic, animated, initialVelocity)
    }

    private fun settleFromRelease(velocityPxPerSecond: Float, performHaptic: Boolean) {
        val naturalReveal = naturalTargetReveal(presentedRevealPx(), velocityPxPerSecond)
        val nextOpen = naturalReveal >= laidOutDrawerWidthPx * 0.5f
        if (performHaptic) gestureReleaseHaptic?.perform(this)
        settleToOpen(nextOpen, SettlingSource.Release, true, velocityPxPerSecond)
    }

    private fun settleToOpen(
        nextOpen: Boolean,
        source: SettlingSource,
        animated: Boolean,
        initialVelocityPxPerSecond: Float = 0f,
    ) {
        targetOpen = nextOpen
        settlingSource = source
        phase = Phase.Settling
        publishProgress()
        settleRunning = false
        val atRest = abs(rawRevealPx - targetReveal(nextOpen)) <= SETTLE_POSITION_EPSILON_PX &&
            abs(initialVelocityPxPerSecond) <= SETTLE_VELOCITY_EPSILON_PX_PER_SECOND
        if (!animated || atRest) {
            finishAtOpen(nextOpen)
            return
        }
        startSettle(initialVelocityPxPerSecond)
    }

    private fun startSettle(velocityPxPerSecond: Float) {
        settleStartRawRevealPx = rawRevealPx
        settleInitialVelocityPxPerSecond = velocityPxPerSecond
        settleVelocityPxPerSecond = velocityPxPerSecond
        settleStartTimeNanos = System.nanoTime()
        settleRunning = true
        postInvalidateOnAnimation()
    }

    private fun updateSettleFrame(frameTimeNanos: Long): Boolean {
        if (!settleRunning) return false
        val target = targetReveal(targetOpen)
        val elapsed = (frameTimeNanos - settleStartTimeNanos).coerceAtLeast(0L) / NANOS_PER_SECOND
        val initialDisplacement = (settleStartRawRevealPx - target).toDouble()
        val initialVelocity = settleInitialVelocityPxPerSecond.toDouble()
        val coefficient = initialVelocity + SETTLE_ANGULAR_FREQUENCY * initialDisplacement
        val decay = kotlin.math.exp(-SETTLE_ANGULAR_FREQUENCY * elapsed)
        val displacement = (initialDisplacement + coefficient * elapsed) * decay
        val velocity = (initialVelocity - SETTLE_ANGULAR_FREQUENCY * coefficient * elapsed) * decay

        val rawReveal = target + displacement.toFloat()
        rawRevealPx = rawReveal
        settleVelocityPxPerSecond = velocity.toFloat()
        applyProgress()
        publishProgress()
        if (abs(displacement) <= SETTLE_POSITION_EPSILON_PX && abs(velocity) <= SETTLE_VELOCITY_EPSILON_PX_PER_SECOND) {
            finishAtOpen(targetOpen)
            return false
        }
        return true
    }

    private fun naturalTargetReveal(currentReveal: Float, velocityPxPerSecond: Float): Float {
        val maximum = laidOutDrawerWidthPx.roundToInt()
        val boundedReveal = currentReveal.coerceIn(0f, laidOutDrawerWidthPx)
        targetResolverScroller.forceFinished(true)
        targetResolverScroller.fling(
            boundedReveal.roundToInt(),
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
        settleRunning = false
        settleVelocityPxPerSecond = 0f
        rawRevealPx = targetReveal(nextOpen)
        open = nextOpen
        targetOpen = nextOpen
        phase = if (nextOpen) Phase.Open else Phase.Closed
        settlingSource = SettlingSource.None
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
        isDragging = false
        hasDragged = false
    }

    private fun beginDragging(currentX: Float) {
        if (isDragging) return
        val wasSettling = phase == Phase.Settling
        val interruptedTarget = if (wasSettling) targetOpen else open
        if (wasSettling) synchronizeSettleFrame()
        settleRunning = false
        isDragging = true
        dragStartX = if (wasSettling) currentX else downX
        dragStartRawRevealPx = rawRevealPx
        targetOpen = interruptedTarget
        settlingSource = SettlingSource.None
        phase = Phase.Dragging
        publishProgress()
    }

    private fun finishTouch() {
        activePointerId = INVALID_POINTER_ID
        gestureEligible = false
        isDragging = false
        hasDragged = false
        velocityTracker?.recycle()
        velocityTracker = null
    }

    private fun handlePointerUp(event: MotionEvent) {
        val actionIndex = event.actionIndex
        if (event.getPointerId(actionIndex) != activePointerId) return
        val nextIndex = if (actionIndex == 0) 1 else 0
        activePointerId = event.getPointerId(nextIndex)
        dragStartX = event.getX(nextIndex)
        dragStartRawRevealPx = rawRevealPx
        downX = dragStartX
        downY = event.getY(nextIndex)
        velocityTracker?.clear()
    }

    private fun synchronizeSettleFrame() {
        if (settleRunning) updateSettleFrame(System.nanoTime())
    }

    private fun revealDirection(): Int {
        val isRtl = layoutDirection == LAYOUT_DIRECTION_RTL
        val revealsLeft = (side == Side.Start) != isRtl
        return if (revealsLeft) 1 else -1
    }

    private fun setDragRawRevealPx(value: Float) {
        rawRevealPx = value
        applyProgress()
    }

    private fun presentedRevealPx(): Float {
        val maximum = laidOutDrawerWidthPx
        return when {
            rawRevealPx < 0f -> -rubberBandDistance(-rawRevealPx)
            rawRevealPx > maximum -> maximum + rubberBandDistance(rawRevealPx - maximum)
            else -> rawRevealPx
        }
    }

    private fun rubberBandDistance(distance: Float): Float {
        val dimension = width.toFloat().coerceAtLeast(1f)
        return distance * dimension * RUBBER_BAND_COEFFICIENT /
            (dimension + RUBBER_BAND_COEFFICIENT * distance)
    }

    private fun compileMotion(config: ReadableArray?): Array<MotionInterpolation?>? {
        if (config == null || config.size() < MOTION_CHANNEL_COUNT) return null
        val compiled = arrayOfNulls<MotionInterpolation>(MOTION_CHANNEL_COUNT)
        var cursor = MOTION_CHANNEL_COUNT
        for (channel in 0 until MOTION_CHANNEL_COUNT) {
            val rawPointCount = config.getDouble(channel)
            val pointCount = rawPointCount.toInt()
            if (!rawPointCount.isFinite() || rawPointCount != pointCount.toDouble() || pointCount < 0 || pointCount == 1) {
                return null
            }
            if (cursor + pointCount * 2 > config.size()) return null
            if (pointCount == 0) continue

            val outputScale = if (
                channel == DRAWER_TRANSLATE_X || channel == DRAWER_TRANSLATE_Y ||
                channel == CONTENT_TRANSLATE_X || channel == CONTENT_TRANSLATE_Y
            ) {
                resources.displayMetrics.density
            } else {
                1f
            }
            val firstInput = config.getDouble(cursor).toFloat()
            val firstOutput = config.getDouble(cursor + 1).toFloat() * outputScale
            if (!firstInput.isFinite() || !firstOutput.isFinite() || firstInput !in 0f..1f) return null
            var previousInput = firstInput
            var previousOutput = firstOutput
            var lastInput = firstInput
            var lastOutput = firstOutput
            cursor += 2
            val segments = ArrayList<MotionSegment>(pointCount - 1)
            repeat(pointCount - 1) {
                val input = config.getDouble(cursor).toFloat()
                val output = config.getDouble(cursor + 1).toFloat() * outputScale
                if (!input.isFinite() || !output.isFinite() || input <= previousInput || input > 1f) return null
                val slope = (output - previousOutput) / (input - previousInput)
                segments.add(MotionSegment(input, slope, previousOutput - slope * previousInput))
                previousInput = input
                previousOutput = output
                lastInput = input
                lastOutput = output
                cursor += 2
            }
            compiled[channel] = MotionInterpolation(
                firstInput,
                firstOutput,
                lastInput,
                lastOutput,
                segments.toTypedArray(),
            )
        }
        return if (cursor == config.size()) compiled else null
    }

    private fun motionValue(channel: Int, progress: Float, fallback: Float): Float {
        return motion[channel]?.evaluate(progress) ?: fallback
    }

    private fun applyProgress() {
        val presentedReveal = presentedRevealPx()
        val currentProgress = if (laidOutDrawerWidthPx > 0f) {
            (presentedReveal / laidOutDrawerWidthPx).coerceIn(0f, 1f)
        } else {
            0f
        }
        val panel = panelView
        val drawerOpacity = motionValue(DRAWER_OPACITY, currentProgress, 1f).coerceIn(0f, 1f)
        val drawerScale = motionValue(DRAWER_SCALE, currentProgress, 1f)
        val drawerTranslationX = motionValue(DRAWER_TRANSLATE_X, currentProgress, 0f)
        val drawerTranslationY = motionValue(DRAWER_TRANSLATE_Y, currentProgress, 0f)
        if (panel != null) {
            if (panel.alpha != drawerOpacity) panel.alpha = drawerOpacity
            if (panel.scaleX != drawerScale) panel.scaleX = drawerScale
            if (panel.scaleY != drawerScale) panel.scaleY = drawerScale
            if (panel.translationX != drawerTranslationX) panel.translationX = drawerTranslationX
            if (panel.translationY != drawerTranslationY) panel.translationY = drawerTranslationY
        }

        val content = contentView
        val contentOpacity = motionValue(CONTENT_OPACITY, currentProgress, 1f).coerceIn(0f, 1f)
        val contentScale = motionValue(CONTENT_SCALE, currentProgress, 1f)
        val contentTranslationX =
            revealDirection() * presentedReveal + motionValue(CONTENT_TRANSLATE_X, currentProgress, 0f)
        val contentTranslationY = motionValue(CONTENT_TRANSLATE_Y, currentProgress, 0f)
        if (content != null) {
            if (content.alpha != contentOpacity) content.alpha = contentOpacity
            if (content.scaleX != contentScale) content.scaleX = contentScale
            if (content.scaleY != contentScale) content.scaleY = contentScale
            if (content.translationX != contentTranslationX) content.translationX = contentTranslationX
            if (content.translationY != contentTranslationY) content.translationY = contentTranslationY
            content.setDrawerOverlayOpacity(motionValue(OVERLAY_OPACITY, currentProgress, 0f))
            content.setDrawerProgress(currentProgress)
        }
        val panelEnabled = currentProgress > 0.001f
        if (panelView?.isEnabled != panelEnabled) panelView?.isEnabled = panelEnabled
        when {
            currentProgress <= 0.001f -> {
                setAccessibilityState(IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS, IMPORTANT_FOR_ACCESSIBILITY_AUTO)
            }
            currentProgress >= 0.999f -> {
                setAccessibilityState(IMPORTANT_FOR_ACCESSIBILITY_AUTO, IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS)
            }
            else -> {
                setAccessibilityState(IMPORTANT_FOR_ACCESSIBILITY_AUTO, IMPORTANT_FOR_ACCESSIBILITY_AUTO)
            }
        }
    }

    private fun setAccessibilityState(panelState: Int, contentState: Int) {
        if (panelView?.importantForAccessibility != panelState) panelView?.importantForAccessibility = panelState
        if (contentView?.importantForAccessibility != contentState) contentView?.importantForAccessibility = contentState
    }

    private fun progress(): Float {
        return if (laidOutDrawerWidthPx > 0f) {
            (presentedRevealPx() / laidOutDrawerWidthPx).coerceIn(0f, 1f)
        } else {
            0f
        }
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
        const val DRAWER_OPACITY = 0
        const val DRAWER_SCALE = 1
        const val DRAWER_TRANSLATE_X = 2
        const val DRAWER_TRANSLATE_Y = 3
        const val CONTENT_OPACITY = 4
        const val CONTENT_SCALE = 5
        const val CONTENT_TRANSLATE_X = 6
        const val CONTENT_TRANSLATE_Y = 7
        const val OVERLAY_OPACITY = 8
        const val MOTION_CHANNEL_COUNT = 9
        const val INVALID_POINTER_ID = -1
        // UIKit's rubber-band relation uses this coefficient for immediate, continuous endpoint resistance.
        const val RUBBER_BAND_COEFFICIENT = 0.55f
        const val NANOS_PER_SECOND = 1_000_000_000.0
        const val SETTLE_ANGULAR_FREQUENCY = 12.566370614359172
        const val SETTLE_POSITION_EPSILON_PX = 0.5
        const val SETTLE_VELOCITY_EPSILON_PX_PER_SECOND = 5.0
    }
}
