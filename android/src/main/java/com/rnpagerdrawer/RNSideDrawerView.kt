package com.rnpagerdrawer

import android.graphics.Color
import android.os.Build
import android.view.Choreographer
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
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.tanh

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
            var lower = 0
            var upper = segments.lastIndex
            while (lower < upper) {
                val middle = (lower + upper) ushr 1
                if (progress <= segments[middle].upperInput) {
                    upper = middle
                } else {
                    lower = middle + 1
                }
            }
            val segment = segments[lower]
            return segment.slope * progress + segment.intercept
        }
    }

    private val slots = ArrayList<View>(2)
    private val choreographer = Choreographer.getInstance()
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
    private var revealPx = 0f
    private var laidOutDrawerWidthPx = 0f
    private var hasLaidOut = false
    private var activePointerId = INVALID_POINTER_ID
    private var gestureEligible = false
    private var descendantRequestedDisallowIntercept = false
    private var isDragging = false
    private var hasDragged = false
    private var gestureOriginOpen = false
    private var downX = 0f
    private var downY = 0f
    private var dragStartX = 0f
    private var lastPointerX = 0f
    private var dragStartRawRevealPx = 0f
    private var dragRawRevealPx = 0f
    private var dragLowerBoundPx = 0f
    private var dragHasReachedNonnegative = true
    private var settleStartTimeNanos = 0L
    private var settleStartRevealPx = 0f
    private var settleInitialVelocityPxPerSecond = 0f
    private var settleVelocityPxPerSecond = 0f
    private var settleRunning = false
    private var settlePausedForTouch = false
    private var highFrameRateRequested = false
    private var velocityTracker: VelocityTracker? = null
    private var motion = arrayOfNulls<MotionInterpolation>(MOTION_CHANNEL_COUNT)
    private var overlayColor = Color.TRANSPARENT

    private val settleFrameCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            if (phase != Phase.Settling || !settleRunning) return
            if (updateSettleFrame(frameTimeNanos)) choreographer.postFrameCallback(this)
        }
    }

    var drawerWidthPx: Float = 0f
        set(value) {
            val next = max(0f, value)
            if (field == next) return
            field = next
            requestLayout()
        }

    var contentBorderColor: Int = Color.TRANSPARENT
        set(value) {
            if (field == value) return
            field = value
            contentView?.setDrawerBorderColor(value)
        }

    var contentBorderWidthPx: Float = 0f
        set(value) {
            val next = if (value.isFinite()) max(0f, value) else 0f
            if (field == next) return
            field = next
            contentView?.setDrawerBorderWidth(next)
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
                if (isDragging) {
                    settleToOpen(progress() >= 0.5f, SettlingSource.Release, true, 0f)
                } else {
                    resumePausedSettle()
                }
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

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if (gestureEnabled && laidOutDrawerWidthPx > 0f && event.actionMasked == MotionEvent.ACTION_DOWN &&
            phase == Phase.Settling
        ) {
            pauseSettleForTouch()
        }
        val handled = super.dispatchTouchEvent(event)
        if (event.actionMasked == MotionEvent.ACTION_UP || event.actionMasked == MotionEvent.ACTION_CANCEL) {
            resumePausedSettle()
            finishTouch()
        }
        return handled
    }

    override fun requestDisallowInterceptTouchEvent(disallowIntercept: Boolean) {
        if (!disallowIntercept) {
            descendantRequestedDisallowIntercept = false
            if (isDragging) return
            super.requestDisallowInterceptTouchEvent(false)
            return
        }
        if (gestureEligible && !isDragging) {
            descendantRequestedDisallowIntercept = true
            return
        }
        super.requestDisallowInterceptTouchEvent(true)
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        val firstLayout = !hasLaidOut
        val settlingBeforeLayout = phase == Phase.Settling
        val resumePaused = settlePausedForTouch
        if (settlingBeforeLayout) synchronizeSettleFrame()
        val resumeSettling = phase == Phase.Settling
        val resumeVelocity = if (resumeSettling) settleVelocityPxPerSecond else 0f
        val resumeSource = settlingSource
        val previousDrawerWidth = laidOutDrawerWidthPx
        val previousReveal = revealPx
        val dragLowerBound = if (dragHasReachedNonnegative) 0f else dragLowerBoundPx
        val hiddenLowerTravel = if (phase == Phase.Dragging) {
            minOf(0f, dragRawRevealPx - dragLowerBound)
        } else {
            0f
        }
        stopSettleFrames()

        laidOutDrawerWidthPx = drawerWidthPx
        val hostWidth = right - left
        val hostHeight = bottom - top
        panelView?.layout(0, 0, hostWidth, hostHeight)
        contentView?.layout(0, 0, hostWidth, hostHeight)
        hasLaidOut = true
        revealPx = when {
            firstLayout -> if (initialOpen) laidOutDrawerWidthPx else 0f
            previousReveal < 0f -> previousReveal
            previousReveal > previousDrawerWidth -> laidOutDrawerWidthPx + previousReveal - previousDrawerWidth
            previousDrawerWidth > 0f -> previousReveal / previousDrawerWidth * laidOutDrawerWidthPx
            open -> laidOutDrawerWidthPx
            else -> 0f
        }
        if (phase == Phase.Dragging) {
            reanchorDrag(lastPointerX, directRawReveal(revealPx) + hiddenLowerTravel)
        }
        applyProgress()

        if (resumeSettling) {
            if (resumePaused) {
                settleVelocityPxPerSecond = 0f
                settlePausedForTouch = true
            } else {
                settleToOpen(targetOpen, resumeSource, true, resumeVelocity)
            }
        } else if (firstLayout) {
            open = initialOpen
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
                if (phase == Phase.Settling) pauseSettleForTouch()
            }
            MotionEvent.ACTION_MOVE -> {
                if (!gestureEligible) return false
                val pointerIndex = event.findPointerIndex(activePointerId)
                if (pointerIndex < 0) return false
                val deltaX = event.getX(pointerIndex) - downX
                val deltaY = event.getY(pointerIndex) - downY
                val revealDelta = deltaX * revealDirection()
                val canMove = canMove(revealDelta)
                if (canMove && abs(deltaX) > touchSlop && abs(deltaX) > abs(deltaY)) {
                    beginDragging(event.getX(pointerIndex))
                    hasDragged = true
                    parent?.requestDisallowInterceptTouchEvent(true)
                    return true
                }
                if (max(abs(deltaX), abs(deltaY)) > touchSlop && (!canMove || abs(deltaY) >= abs(deltaX))) {
                    yieldGestureToDescendant()
                }
            }
            MotionEvent.ACTION_CANCEL, MotionEvent.ACTION_UP -> {
                resumePausedSettle()
                finishTouch()
            }
        }
        return false
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!gestureEnabled || !gestureEligible) return false
        if (event.actionMasked == MotionEvent.ACTION_DOWN) return true
        ensureVelocityTracker().addMovement(event)
        when (event.actionMasked) {
            MotionEvent.ACTION_POINTER_UP -> handlePointerUp(event)
            MotionEvent.ACTION_MOVE -> {
                val pointerIndex = event.findPointerIndex(activePointerId)
                if (pointerIndex < 0) return false
                val x = event.getX(pointerIndex)
                lastPointerX = x
                if (!isDragging) {
                    val deltaX = x - downX
                    val deltaY = event.getY(pointerIndex) - downY
                    val horizontalIntent = abs(deltaX) > touchSlop && abs(deltaX) > abs(deltaY)
                    if (canMove(deltaX * revealDirection()) && horizontalIntent) {
                        beginDragging(x)
                        hasDragged = true
                        parent?.requestDisallowInterceptTouchEvent(true)
                    }
                }
                if (isDragging) {
                    val deltaX = x - dragStartX
                    val deltaY = event.getY(pointerIndex) - downY
                    if (abs(deltaX) > touchSlop && abs(deltaX) > abs(deltaY)) hasDragged = true
                    updateDragReveal(x)
                    publishProgress()
                }
                return true
            }
            MotionEvent.ACTION_UP -> {
                if (isDragging) {
                    val pointerIndex = event.findPointerIndex(activePointerId)
                    if (pointerIndex >= 0) {
                        updateDragReveal(event.getX(pointerIndex))
                        publishProgress()
                    }
                    val tracker = ensureVelocityTracker()
                    tracker.computeCurrentVelocity(1000, maximumFlingVelocity.toFloat())
                    val revealVelocity = tracker.getXVelocity(activePointerId) * revealDirection()
                    settleFromRelease(revealVelocity, hasDragged)
                } else {
                    resumePausedSettle()
                }
                finishTouch()
                return true
            }
            MotionEvent.ACTION_CANCEL -> {
                if (isDragging) {
                    settleToOpen(progress() >= 0.5f, SettlingSource.Release, true, 0f)
                } else {
                    resumePausedSettle()
                }
                finishTouch()
                return true
            }
        }
        return true
    }

    override fun onDetachedFromWindow() {
        if (phase == Phase.Settling) synchronizeSettleFrame()
        stopSettleFrames()
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
                child.setDrawerBorderColor(contentBorderColor)
                child.setDrawerBorderWidth(contentBorderWidthPx)
                child.contentCornerRadiusPx = contentCornerRadiusPx
                child.setDrawerOverlayColor(overlayColor)
                child.onScrimPress = { close(true) }
                child.bringToFront()
            }
        }
        if (highFrameRateRequested) applyRequestedFrameRate(child)
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
        stopSettleFrames()
        setHighFrameRateRequested(false)
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
        if ((phase == Phase.Open && nextOpen) || (phase == Phase.Closed && !nextOpen)) return
        if (animated && phase == Phase.Settling && targetOpen == nextOpen) return
        if (phase == Phase.Settling) synchronizeSettleFrame()
        val initialVelocity = if (phase == Phase.Settling) settleVelocityPxPerSecond else 0f
        stopSettleFrames()
        settlePausedForTouch = false
        if (isDragging) finishTouch()
        settleToOpen(nextOpen, SettlingSource.Programmatic, animated, initialVelocity)
    }

    private fun settleFromRelease(velocityPxPerSecond: Float, performHaptic: Boolean) {
        val presentedVelocity = releaseRevealVelocity(velocityPxPerSecond)
        val naturalReveal = naturalTargetReveal(revealPx, presentedVelocity)
        val nextOpen = naturalReveal >= laidOutDrawerWidthPx * 0.5f
        if (performHaptic && nextOpen != gestureOriginOpen) gestureReleaseHaptic?.perform(this)
        settleToOpen(nextOpen, SettlingSource.Release, true, presentedVelocity)
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
        stopSettleFrames()
        settlePausedForTouch = false
        val target = targetReveal(nextOpen)
        val atRest = abs(revealPx - target) <= SETTLE_POSITION_EPSILON_PX
        if (!animated || atRest) {
            finishAtOpen(nextOpen)
            return
        }
        val boundedVelocity = boundedSettleVelocity(revealPx, initialVelocityPxPerSecond, target, overtravelLimitPx())
        startSettle(boundedVelocity)
    }

    private fun startSettle(velocityPxPerSecond: Float) {
        choreographer.removeFrameCallback(settleFrameCallback)
        settleStartRevealPx = revealPx
        settleInitialVelocityPxPerSecond = velocityPxPerSecond
        settleVelocityPxPerSecond = velocityPxPerSecond
        settleStartTimeNanos = System.nanoTime()
        settleRunning = true
        setHighFrameRateRequested(true)
        choreographer.postFrameCallback(settleFrameCallback)
    }

    private fun updateSettleFrame(frameTimeNanos: Long): Boolean {
        if (!settleRunning) return false
        val target = targetReveal(targetOpen)
        val elapsed = (frameTimeNanos - settleStartTimeNanos).coerceAtLeast(0L) / NANOS_PER_SECOND
        val initialDisplacement = (settleStartRevealPx - target).toDouble()
        val initialVelocity = settleInitialVelocityPxPerSecond.toDouble()
        val coefficient = initialVelocity + SETTLE_ANGULAR_FREQUENCY * initialDisplacement
        val decay = exp(-SETTLE_ANGULAR_FREQUENCY * elapsed)
        val displacement = (initialDisplacement + coefficient * elapsed) * decay
        val velocity = (initialVelocity - SETTLE_ANGULAR_FREQUENCY * coefficient * elapsed) * decay

        revealPx = target + displacement.toFloat()
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
        stopSettleFrames()
        settlePausedForTouch = false
        settleVelocityPxPerSecond = 0f
        revealPx = targetReveal(nextOpen)
        open = nextOpen
        targetOpen = nextOpen
        phase = if (nextOpen) Phase.Open else Phase.Closed
        settlingSource = SettlingSource.None
        applyProgress()
        publishProgress()
        emitOpenChangeIfNeeded()
        setHighFrameRateRequested(false)
    }

    private fun initializeTouch(event: MotionEvent) {
        velocityTracker?.recycle()
        velocityTracker = VelocityTracker.obtain().also { it.addMovement(event) }
        activePointerId = event.getPointerId(0)
        downX = event.x
        downY = event.y
        lastPointerX = event.x
        descendantRequestedDisallowIntercept = false
        isDragging = false
        hasDragged = false
    }

    private fun beginDragging(currentX: Float) {
        if (isDragging) return
        val wasSettling = phase == Phase.Settling
        val interruptedTarget = if (wasSettling) targetOpen else open
        if (wasSettling && !settlePausedForTouch) synchronizeSettleFrame()
        stopSettleFrames()
        settlePausedForTouch = false
        isDragging = true
        startDragMapping(if (wasSettling) currentX else downX)
        gestureOriginOpen = interruptedTarget
        targetOpen = interruptedTarget
        settlingSource = SettlingSource.None
        phase = Phase.Dragging
        setHighFrameRateRequested(true)
        publishProgress()
    }

    private fun finishTouch() {
        activePointerId = INVALID_POINTER_ID
        gestureEligible = false
        isDragging = false
        hasDragged = false
        descendantRequestedDisallowIntercept = false
        super.requestDisallowInterceptTouchEvent(false)
        velocityTracker?.recycle()
        velocityTracker = null
    }

    private fun handlePointerUp(event: MotionEvent) {
        val actionIndex = event.actionIndex
        if (event.getPointerId(actionIndex) != activePointerId) return
        val nextIndex = if (actionIndex == 0) 1 else 0
        activePointerId = event.getPointerId(nextIndex)
        lastPointerX = event.getX(nextIndex)
        reanchorDrag(lastPointerX)
        downX = dragStartX
        downY = event.getY(nextIndex)
        velocityTracker?.clear()
    }

    private fun synchronizeSettleFrame() {
        if (settleRunning) updateSettleFrame(System.nanoTime())
    }

    private fun pauseSettleForTouch() {
        if (phase != Phase.Settling || settlePausedForTouch) return
        synchronizeSettleFrame()
        stopSettleFrames()
        settleVelocityPxPerSecond = 0f
        settlePausedForTouch = true
    }

    private fun resumePausedSettle() {
        if (!settlePausedForTouch || phase != Phase.Settling) return
        settlePausedForTouch = false
        settleToOpen(targetOpen, settlingSource, true, 0f)
    }

    private fun stopSettleFrames() {
        settleRunning = false
        choreographer.removeFrameCallback(settleFrameCallback)
    }

    private fun startDragMapping(currentX: Float) {
        dragLowerBoundPx = minOf(revealPx, 0f)
        dragHasReachedNonnegative = revealPx >= 0f
        reanchorDrag(currentX, directRawReveal(revealPx))
    }

    private fun reanchorDrag(currentX: Float, rawReveal: Float = dragRawRevealPx) {
        lastPointerX = currentX
        dragStartX = currentX
        dragStartRawRevealPx = rawReveal
        dragRawRevealPx = rawReveal
    }

    private fun yieldGestureToDescendant() {
        gestureEligible = false
        if (descendantRequestedDisallowIntercept) super.requestDisallowInterceptTouchEvent(true)
    }

    private fun revealDirection(): Int {
        val isRtl = layoutDirection == LAYOUT_DIRECTION_RTL
        val revealsLeft = (side == Side.Start) != isRtl
        return if (revealsLeft) 1 else -1
    }

    private fun canMove(revealDelta: Float): Boolean =
        (revealPx > 0f || revealDelta > 0f) && (revealPx < laidOutDrawerWidthPx || revealDelta < 0f)

    private fun setDragRawRevealPx(value: Float) {
        dragRawRevealPx = value
        var presentedRawReveal = value
        if (!dragHasReachedNonnegative) {
            presentedRawReveal = max(dragLowerBoundPx, presentedRawReveal)
            if (presentedRawReveal >= 0f) dragHasReachedNonnegative = true
        }
        if (dragHasReachedNonnegative) presentedRawReveal = max(0f, presentedRawReveal)
        revealPx = if (presentedRawReveal < 0f) presentedRawReveal else directReveal(presentedRawReveal)
        applyProgress()
    }

    private fun updateDragReveal(currentX: Float) {
        lastPointerX = currentX
        setDragRawRevealPx(dragStartRawRevealPx + (currentX - dragStartX) * revealDirection())
    }

    private fun directReveal(rawReveal: Float): Float {
        if (rawReveal <= laidOutDrawerWidthPx) return max(0f, rawReveal)
        val limit = overtravelLimitPx()
        return laidOutDrawerWidthPx + limit * tanh((rawReveal - laidOutDrawerWidthPx) / limit)
    }

    private fun directRawReveal(presentationReveal: Float): Float {
        if (presentationReveal <= laidOutDrawerWidthPx) return presentationReveal
        val limit = overtravelLimitPx()
        val normalized = ((presentationReveal - laidOutDrawerWidthPx) / limit).coerceIn(0f, 1f - 1e-6f)
        return laidOutDrawerWidthPx + limit * 0.5f * ln((1f + normalized) / (1f - normalized))
    }

    private fun releaseRevealVelocity(velocityPxPerSecond: Float): Float {
        if (!velocityPxPerSecond.isFinite()) return 0f
        val lowerBound = if (dragHasReachedNonnegative) 0f else dragLowerBoundPx
        if (dragRawRevealPx < lowerBound ||
            (dragRawRevealPx <= lowerBound && velocityPxPerSecond < 0f)
        ) {
            return 0f
        }
        if (dragRawRevealPx <= laidOutDrawerWidthPx) return velocityPxPerSecond
        val normalized = tanh((dragRawRevealPx - laidOutDrawerWidthPx) / overtravelLimitPx())
        return velocityPxPerSecond * (1f - normalized * normalized)
    }

    private fun outwardExcursion(
        reveal: Float,
        velocity: Float,
        target: Float,
        angularFrequency: Double,
    ): Float {
        val outwardDirection = if (target > 0f) 1f else -1f
        val displacement = reveal - target
        var maximumExcursion = max(0f, outwardDirection * displacement)
        val coefficient = velocity + angularFrequency * displacement
        if (abs(coefficient) <= Double.MIN_VALUE) return maximumExcursion
        val extremumTime = velocity / (angularFrequency * coefficient)
        if (extremumTime <= 0.0 || !extremumTime.isFinite()) return maximumExcursion
        val extremumDisplacement = (displacement + coefficient * extremumTime) * exp(-angularFrequency * extremumTime)
        maximumExcursion = max(maximumExcursion, (outwardDirection * extremumDisplacement).toFloat())
        return maximumExcursion
    }

    private fun boundedSettleVelocity(
        reveal: Float,
        velocity: Float,
        target: Float,
        allowedExcursion: Float,
    ): Float {
        val outwardDirection = if (target > 0f) 1f else -1f
        val currentExcursion = max(0f, outwardDirection * (reveal - target))
        val resolvedAllowedExcursion = max(allowedExcursion, currentExcursion)
        val baseExcursion = outwardExcursion(reveal, velocity, target, SETTLE_ANGULAR_FREQUENCY)
        if (baseExcursion <= resolvedAllowedExcursion) return velocity

        var lowerScale = 0f
        var upperScale = 1f
        repeat(32) {
            val candidateScale = (lowerScale + upperScale) * 0.5f
            val candidateVelocity = velocity * candidateScale
            val candidateExcursion = outwardExcursion(reveal, candidateVelocity, target, SETTLE_ANGULAR_FREQUENCY)
            if (candidateExcursion > resolvedAllowedExcursion) {
                upperScale = candidateScale
            } else {
                lowerScale = candidateScale
            }
        }
        return velocity * lowerScale
    }

    private fun overtravelLimitPx(): Float = OVERTRAVEL_LIMIT_DP * resources.displayMetrics.density

    private fun setHighFrameRateRequested(requested: Boolean) {
        if (highFrameRateRequested == requested) return
        highFrameRateRequested = requested
        applyRequestedFrameRate(this)
        panelView?.let(::applyRequestedFrameRate)
        contentView?.let(::applyRequestedFrameRate)
    }

    private fun applyRequestedFrameRate(view: View) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) return
        val frameRate = if (highFrameRateRequested) {
            View.REQUESTED_FRAME_RATE_CATEGORY_HIGH
        } else {
            View.REQUESTED_FRAME_RATE_CATEGORY_DEFAULT
        }
        view.setRequestedFrameRate(frameRate)
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
        val currentProgress = if (laidOutDrawerWidthPx > 0f) {
            (revealPx / laidOutDrawerWidthPx).coerceIn(0f, 1f)
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
            revealDirection() * revealPx + motionValue(CONTENT_TRANSLATE_X, currentProgress, 0f)
        val contentTranslationY = motionValue(CONTENT_TRANSLATE_Y, currentProgress, 0f)
        if (content != null) {
            if (content.alpha != contentOpacity) content.alpha = contentOpacity
            if (content.scaleX != contentScale) content.scaleX = contentScale
            if (content.scaleY != contentScale) content.scaleY = contentScale
            if (content.translationX != contentTranslationX) content.translationX = contentTranslationX
            if (content.translationY != contentTranslationY) content.translationY = contentTranslationY
            content.setDrawerOverlayOpacity(motionValue(OVERLAY_OPACITY, currentProgress, 0f))
            content.setDrawerBorderOpacity(motionValue(CONTENT_BORDER_OPACITY, currentProgress, 1f))
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
            (revealPx / laidOutDrawerWidthPx).coerceIn(0f, 1f)
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
        const val CONTENT_BORDER_OPACITY = 9
        const val MOTION_CHANNEL_COUNT = 10
        const val INVALID_POINTER_ID = -1
        const val NANOS_PER_SECOND = 1_000_000_000.0
        const val SETTLE_ANGULAR_FREQUENCY = 21.991148575128552
        const val SETTLE_POSITION_EPSILON_PX = 0.5
        const val SETTLE_VELOCITY_EPSILON_PX_PER_SECOND = 5.0
        const val OVERTRAVEL_LIMIT_DP = 4f
    }
}
