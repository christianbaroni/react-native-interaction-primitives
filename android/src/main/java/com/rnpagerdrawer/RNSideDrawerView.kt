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
import com.facebook.react.uimanager.TouchTargetHelper
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

    private val contentPresentationView = RNSideDrawerContentPresentationView(reactContext)
    private val slots = ArrayList<View>(2)
    private val targetResolverScroller = OverScroller(reactContext)
    private val choreographer = Choreographer.getInstance()
    private val viewConfiguration = ViewConfiguration.get(reactContext)
    private val touchSlop = viewConfiguration.scaledTouchSlop
    private val maximumFlingVelocity = viewConfiguration.scaledMaximumFlingVelocity
    private val nativeTouchTarget = IntArray(1)

    private var panelView: RNSideDrawerPanelView? = null
    private var contentView: RNSideDrawerContentView? = null

    private var phase = Phase.Closed
    private var settlingSource = SettlingSource.None
    private var open = false
    private var targetOpen = false
    private var lastEmittedOpen = false
    private var hasLaidOut = false
    private var progressSnapshotPending = false
    private var laidOutDrawerWidthPx = 0f
    private var revealPx = 0f

    private var configuredInteraction = defaultSideDrawerInteraction(defaultOverdragPx())
    private var activeInteraction = configuredInteraction
    private var motion = SideDrawerMotion.EMPTY
    private var overlayColor = Color.TRANSPARENT

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
    private var dragStartPositionPx = 0f
    private var unconstrainedDragPositionPx = 0f
    private var dragLowerBoundPx = 0f
    private var dragUpperBoundPx = 0f
    private var velocityTracker: VelocityTracker? = null

    private var settleStartTimeNanos = 0L
    private var settleStartPositionPx = 0f
    private var settleInitialVelocityPxPerSecond = 0.0
    private var settleVelocityPxPerSecond = 0.0
    private var settleRunning = false
    private var settlePausedForTouch = false
    private val settleState = SideDrawerSpringState()
    private val excursionState = SideDrawerSpringState()

    private var highFrameRateRequested = false

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

    var overdragPx: Float
        get() = configuredInteraction.overdragPx
        set(value) {
            val resolved = if (value.isFinite()) max(0f, value) else defaultOverdragPx()
            configuredInteraction = configuredInteraction.copy(overdragPx = resolved)
        }

    var releaseOpenThreshold: Double
        get() = configuredInteraction.releaseOpenThreshold
        set(value) {
            val resolved = if (value.isFinite() && value in 0.0..1.0) {
                value
            } else {
                DEFAULT_SIDE_DRAWER_RELEASE_OPEN_THRESHOLD
            }
            configuredInteraction = configuredInteraction.copy(releaseOpenThreshold = resolved)
        }

    var releaseVelocitySensitivity: Double
        get() = configuredInteraction.releaseVelocitySensitivity
        set(value) {
            val resolved = if (value.isFinite() && value >= 0.0) {
                value
            } else {
                DEFAULT_SIDE_DRAWER_RELEASE_VELOCITY_SENSITIVITY
            }
            configuredInteraction = configuredInteraction.copy(releaseVelocitySensitivity = resolved)
        }

    var releaseVelocityTransfer: Double
        get() = configuredInteraction.releaseVelocityTransfer
        set(value) {
            val resolved = if (value.isFinite() && value >= 0.0) {
                value
            } else {
                DEFAULT_SIDE_DRAWER_RELEASE_VELOCITY_TRANSFER
            }
            configuredInteraction = configuredInteraction.copy(releaseVelocityTransfer = resolved)
        }

    var springDamping: Double
        get() = configuredInteraction.spring.damping
        set(value) {
            val spring = configuredInteraction.spring
            configuredInteraction = configuredInteraction.copy(
                spring = resolveSideDrawerSpring(spring.mass, spring.stiffness, value),
            )
        }

    var springMass: Double
        get() = configuredInteraction.spring.mass
        set(value) {
            val spring = configuredInteraction.spring
            configuredInteraction = configuredInteraction.copy(
                spring = resolveSideDrawerSpring(value, spring.stiffness, spring.damping),
            )
        }

    var springStiffness: Double
        get() = configuredInteraction.spring.stiffness
        set(value) {
            val spring = configuredInteraction.spring
            configuredInteraction = configuredInteraction.copy(
                spring = resolveSideDrawerSpring(spring.mass, value, spring.damping),
            )
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
            contentPresentationView.contentCornerRadiusPx = value
        }

    var contentShadowColor: Int = Color.TRANSPARENT
        set(value) {
            if (field == value) return
            field = value
            contentPresentationView.setShadowColor(value)
        }

    var contentShadowElevationPx: Float = 0f
        set(value) {
            val next = if (value.isFinite()) max(0f, value) else 0f
            if (field == next) return
            field = next
            contentPresentationView.setShadowElevation(next)
        }

    var gestureEnabled: Boolean = true
        set(value) {
            if (field == value) return
            field = value
            if (!value) {
                if (isDragging) {
                    settleToOpen(
                        revealProgress() >= activeInteraction.releaseOpenThreshold,
                        SettlingSource.Release,
                        true,
                        0.0,
                        activeInteraction,
                    )
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
        set(value) {
            if (field == value) return
            field = value
            progressSnapshotPending = value
        }

    var side: Side = Side.Start
        set(value) {
            if (field == value) return
            field = value
            requestLayout()
        }

    init {
        clipChildren = true
        clipToPadding = true
        super.addView(contentPresentationView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val measuredWidth = MeasureSpec.getSize(widthMeasureSpec)
        val measuredHeight = MeasureSpec.getSize(heightMeasureSpec)
        setMeasuredDimension(measuredWidth, measuredHeight)

        val heightSpec = MeasureSpec.makeMeasureSpec(measuredHeight, MeasureSpec.EXACTLY)
        val contentWidthSpec = MeasureSpec.makeMeasureSpec(measuredWidth, MeasureSpec.EXACTLY)
        panelView?.measure(contentWidthSpec, heightSpec)
        contentPresentationView.measure(contentWidthSpec, heightSpec)
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
        val resumeVelocity = if (resumeSettling) settleVelocityPxPerSecond else 0.0
        val resumeSource = settlingSource
        val previousDrawerWidth = laidOutDrawerWidthPx
        val previousReveal = revealPx
        val previousDragPosition = unconstrainedDragPositionPx
        val previousDragLowerBound = dragLowerBoundPx
        val previousDragUpperBound = dragUpperBoundPx
        stopSettleFrames()

        laidOutDrawerWidthPx = drawerWidthPx
        val hostWidth = right - left
        val hostHeight = bottom - top
        panelView?.layout(0, 0, hostWidth, hostHeight)
        contentPresentationView.layout(0, 0, hostWidth, hostHeight)
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
            val remappedDragPosition =
                remapSideDrawerPosition(previousDragPosition, previousDrawerWidth, laidOutDrawerWidthPx)
            dragLowerBoundPx =
                remapSideDrawerPosition(previousDragLowerBound, previousDrawerWidth, laidOutDrawerWidthPx)
            dragUpperBoundPx =
                remapSideDrawerPosition(previousDragUpperBound, previousDrawerWidth, laidOutDrawerWidthPx)
            reanchorDrag(lastPointerX, remappedDragPosition)
            revealPx = resistedSideDrawerPosition(
                remappedDragPosition,
                dragLowerBoundPx,
                dragUpperBoundPx,
                activeInteraction.overdragPx,
            )
        }
        applyPresentation()

        if (resumeSettling) {
            if (resumePaused) {
                settleVelocityPxPerSecond = 0.0
                settlePausedForTouch = true
            } else {
                settleToOpen(targetOpen, resumeSource, true, resumeVelocity, activeInteraction)
            }
        } else if (firstLayout) {
            open = initialOpen
            targetOpen = open
            lastEmittedOpen = open
            phase = if (open) Phase.Open else Phase.Closed
        }
        flushPendingProgressSnapshot()
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
                val revealDelta = deltaX * openingDirection()
                val drawerCanMove = canMoveInDirection(revealDelta)
                val horizontalIntent = abs(deltaX) > touchSlop && abs(deltaX) > abs(deltaY)
                if (horizontalIntent && touchedDescendantCanScrollHorizontally(deltaX)) {
                    yieldGestureToDescendant()
                    return false
                }
                if (drawerCanMove && horizontalIntent) {
                    beginDragging(event.getX(pointerIndex))
                    hasDragged = true
                    parent?.requestDisallowInterceptTouchEvent(true)
                    return true
                }
                if (max(abs(deltaX), abs(deltaY)) > touchSlop && (!drawerCanMove || abs(deltaY) >= abs(deltaX))) {
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
                    if (canMoveInDirection(deltaX * openingDirection()) && horizontalIntent) {
                        beginDragging(x)
                        hasDragged = true
                        parent?.requestDisallowInterceptTouchEvent(true)
                    }
                }
                if (isDragging) {
                    val deltaX = x - dragStartX
                    val deltaY = event.getY(pointerIndex) - downY
                    if (abs(deltaX) > touchSlop && abs(deltaX) > abs(deltaY)) hasDragged = true
                    updateDragPosition(x)
                    publishProgress()
                }
                return true
            }
            MotionEvent.ACTION_UP -> {
                if (isDragging) {
                    val pointerIndex = event.findPointerIndex(activePointerId)
                    if (pointerIndex >= 0) {
                        updateDragPosition(event.getX(pointerIndex))
                        publishProgress()
                    }
                    val tracker = ensureVelocityTracker()
                    tracker.computeCurrentVelocity(1000, maximumFlingVelocity.toFloat())
                    val revealVelocity = tracker.getXVelocity(activePointerId) * openingDirection()
                    settleFromRelease(revealVelocity, hasDragged)
                } else {
                    resumePausedSettle()
                }
                finishTouch()
                return true
            }
            MotionEvent.ACTION_CANCEL -> {
                if (isDragging) {
                    settleToOpen(
                        revealProgress() >= activeInteraction.releaseOpenThreshold,
                        SettlingSource.Release,
                        true,
                        0.0,
                        activeInteraction,
                    )
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
            Phase.Dragging -> finishAtOpen(revealProgress() >= 0.5f)
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
        when (child) {
            is RNSideDrawerPanelView -> {
                panelView = child
                super.addView(child, 0, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
            }
            is RNSideDrawerContentView -> {
                contentView = child
                child.setDrawerBorderColor(contentBorderColor)
                child.setDrawerBorderWidth(contentBorderWidthPx)
                child.setDrawerOverlayColor(overlayColor)
                child.onScrimPress = { close(true) }
                contentPresentationView.setContentView(child)
            }
        }
        if (highFrameRateRequested) applyRequestedFrameRate(child)
        requestLayout()
    }

    fun drawerSlotCount(): Int = slots.size

    fun getDrawerSlotAt(index: Int): View? = slots.getOrNull(index)

    fun removeDrawerSlotAt(index: Int) {
        val child = slots.removeAt(index)
        if (child === panelView) {
            panelView = null
            super.removeView(child)
        }
        if (child === contentView) {
            contentView?.onScrimPress = null
            contentView = null
            contentPresentationView.removeContentView(child as RNSideDrawerContentView)
        }
    }

    fun open(animated: Boolean) {
        setOpen(true, animated)
    }

    fun setMotionConfig(config: ReadableArray?) {
        motion = SideDrawerMotion.compile(config, resources.displayMetrics.density)
        if (hasLaidOut) applyPresentation()
    }

    fun setOverlayColor(color: Int?) {
        overlayColor = color ?: Color.TRANSPARENT
        contentView?.setDrawerOverlayColor(overlayColor)
    }

    fun flushPendingProgressSnapshot() {
        if (!progressSnapshotPending || !progressEventsEnabled || !hasLaidOut) return
        progressSnapshotPending = false
        publishProgress()
    }

    fun close(animated: Boolean) {
        setOpen(false, animated)
    }

    fun toggle(animated: Boolean) {
        val nextOpen = if (phase == Phase.Settling) !targetOpen else revealProgress() < 0.5f
        setOpen(nextOpen, animated)
    }

    fun prepareForRemoval() {
        stopSettleFrames()
        setHighFrameRateRequested(false)
        finishTouch()
        contentView?.onScrimPress = null
        panelView?.let { super.removeView(it) }
        contentView?.let { contentPresentationView.removeContentView(it) }
        slots.clear()
        panelView = null
        contentView = null
        hasLaidOut = false
        revealPx = 0f
        open = false
        targetOpen = false
        phase = Phase.Closed
        settlingSource = SettlingSource.None
        motion = SideDrawerMotion.EMPTY
        contentCornerRadiusPx = -1f
        contentShadowColor = Color.TRANSPARENT
        contentShadowElevationPx = 0f
        progressEventsEnabled = false
        progressSnapshotPending = false
        applyPresentation()
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
        val initialVelocity = if (phase == Phase.Settling) settleVelocityPxPerSecond else 0.0
        stopSettleFrames()
        settlePausedForTouch = false
        if (isDragging) finishTouch()
        settleToOpen(nextOpen, SettlingSource.Programmatic, animated, initialVelocity)
    }

    private fun settleFromRelease(velocityPxPerSecond: Float, performHaptic: Boolean) {
        val interaction = activeInteraction
        val presentedVelocity = releaseVelocityForCurrentDrag(velocityPxPerSecond)
        val projectedPosition = projectedReleasePosition(
            revealPx,
            presentedVelocity * interaction.releaseVelocitySensitivity,
        )
        val nextOpen = projectedPosition >= laidOutDrawerWidthPx * interaction.releaseOpenThreshold
        if (performHaptic && nextOpen != gestureOriginOpen) gestureReleaseHaptic?.perform(this)
        val target = targetPosition(nextOpen)
        val transferredVelocity = presentedVelocity * interaction.releaseVelocityTransfer
        val boundedVelocity = limitSideDrawerReleaseVelocity(
            revealPx,
            transferredVelocity,
            target,
            interaction.spring,
            interaction.overdragPx,
            excursionState,
        )
        settleToOpen(nextOpen, SettlingSource.Release, true, boundedVelocity, interaction)
    }

    private fun settleToOpen(
        nextOpen: Boolean,
        source: SettlingSource,
        animated: Boolean,
        initialVelocityPxPerSecond: Double = 0.0,
        interaction: SideDrawerInteraction = configuredInteraction,
    ) {
        activeInteraction = interaction
        targetOpen = nextOpen
        settlingSource = source
        phase = Phase.Settling
        publishProgress()
        stopSettleFrames()
        settlePausedForTouch = false
        val target = targetPosition(nextOpen)
        val atRest = abs(revealPx - target) <= SETTLE_POSITION_EPSILON_PX
        if (!animated || atRest) {
            finishAtOpen(nextOpen)
            return
        }
        startSettle(initialVelocityPxPerSecond)
    }

    private fun startSettle(velocityPxPerSecond: Double) {
        choreographer.removeFrameCallback(settleFrameCallback)
        settleStartPositionPx = revealPx
        settleInitialVelocityPxPerSecond = velocityPxPerSecond
        settleVelocityPxPerSecond = velocityPxPerSecond
        settleStartTimeNanos = System.nanoTime()
        settleRunning = true
        setHighFrameRateRequested(true)
        choreographer.postFrameCallback(settleFrameCallback)
    }

    private fun updateSettleFrame(frameTimeNanos: Long): Boolean {
        if (!settleRunning) return false
        val target = targetPosition(targetOpen)
        val elapsed = (frameTimeNanos - settleStartTimeNanos).coerceAtLeast(0L) / NANOS_PER_SECOND
        val initialDisplacement = (settleStartPositionPx - target).toDouble()
        val initialVelocity = settleInitialVelocityPxPerSecond
        evaluateSideDrawerSpring(activeInteraction.spring, initialDisplacement, initialVelocity, elapsed, settleState)
        val displacement = settleState.displacement
        val velocity = settleState.velocity

        revealPx = target + displacement.toFloat()
        settleVelocityPxPerSecond = velocity
        applyPresentation()
        publishProgress()
        if (abs(displacement) <= SETTLE_POSITION_EPSILON_PX && abs(velocity) <= SETTLE_VELOCITY_EPSILON_PX_PER_SECOND) {
            finishAtOpen(targetOpen)
            return false
        }
        return true
    }

    private fun projectedReleasePosition(currentPosition: Float, velocityPxPerSecond: Double): Float {
        val maximum = laidOutDrawerWidthPx.roundToInt()
        val boundedPosition = currentPosition.coerceIn(0f, laidOutDrawerWidthPx)
        if (velocityPxPerSecond.isNaN()) return boundedPosition
        if (velocityPxPerSecond >= Int.MAX_VALUE) return laidOutDrawerWidthPx
        if (velocityPxPerSecond <= Int.MIN_VALUE) return 0f
        targetResolverScroller.forceFinished(true)
        targetResolverScroller.fling(
            boundedPosition.roundToInt(),
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
        settleVelocityPxPerSecond = 0.0
        revealPx = targetPosition(nextOpen)
        open = nextOpen
        targetOpen = nextOpen
        phase = if (nextOpen) Phase.Open else Phase.Closed
        settlingSource = SettlingSource.None
        applyPresentation()
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
        activeInteraction = configuredInteraction
        beginDragPositionTracking(if (wasSettling) currentX else downX)
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
        if (phase != Phase.Settling) return
        stopSettleFrames()
        settleVelocityPxPerSecond = 0.0
        settlePausedForTouch = true
    }

    private fun resumePausedSettle() {
        if (!settlePausedForTouch || phase != Phase.Settling) return
        settlePausedForTouch = false
        settleToOpen(targetOpen, settlingSource, true, 0.0, activeInteraction)
    }

    private fun stopSettleFrames() {
        settleRunning = false
        choreographer.removeFrameCallback(settleFrameCallback)
    }

    private fun beginDragPositionTracking(currentX: Float) {
        dragLowerBoundPx = min(0f, revealPx)
        dragUpperBoundPx = max(laidOutDrawerWidthPx, revealPx)
        reanchorDrag(currentX, revealPx)
    }

    private fun reanchorDrag(currentX: Float, dragPosition: Float = unconstrainedDragPositionPx) {
        lastPointerX = currentX
        dragStartX = currentX
        dragStartPositionPx = dragPosition
        unconstrainedDragPositionPx = dragPosition
    }

    private fun yieldGestureToDescendant() {
        gestureEligible = false
        if (descendantRequestedDisallowIntercept) super.requestDisallowInterceptTouchEvent(true)
    }

    private fun touchedDescendantCanScrollHorizontally(deltaX: Float): Boolean {
        val scrollDirection = if (deltaX > 0f) -1 else 1
        nativeTouchTarget[0] = View.NO_ID
        TouchTargetHelper.findTargetTagForTouch(downX, downY, this, nativeTouchTarget)
        var view = if (nativeTouchTarget[0] == View.NO_ID) null else findViewById<View>(nativeTouchTarget[0])
        while (view != null && view !== this) {
            if (view.canScrollHorizontally(scrollDirection)) return true
            view = view.parent as? View
        }
        return false
    }

    private fun openingDirection(): Int {
        val isRtl = layoutDirection == LAYOUT_DIRECTION_RTL
        val revealsLeft = (side == Side.Start) != isRtl
        return if (revealsLeft) 1 else -1
    }

    private fun canMoveInDirection(revealDelta: Float): Boolean =
        (revealPx > 0f || revealDelta > 0f) && (revealPx < laidOutDrawerWidthPx || revealDelta < 0f)

    private fun setUnconstrainedDragPosition(value: Float) {
        unconstrainedDragPositionPx = value
        revealPx = resistedSideDrawerPosition(
            value,
            dragLowerBoundPx,
            dragUpperBoundPx,
            activeInteraction.overdragPx,
        )
        applyPresentation()
    }

    private fun updateDragPosition(currentX: Float) {
        lastPointerX = currentX
        var dragPosition = dragStartPositionPx + (currentX - dragStartX) * openingDirection()
        if (activeInteraction.overdragPx <= 0f) {
            val boundedPosition = dragPosition.coerceIn(dragLowerBoundPx, dragUpperBoundPx)
            if (boundedPosition != dragPosition) {
                dragStartPositionPx = boundedPosition
                dragStartX = currentX
                dragPosition = boundedPosition
            }
        }
        setUnconstrainedDragPosition(dragPosition)
    }

    private fun releaseVelocityForCurrentDrag(velocityPxPerSecond: Float): Float {
        return resistedSideDrawerVelocity(
            unconstrainedDragPositionPx,
            dragLowerBoundPx,
            dragUpperBoundPx,
            activeInteraction.overdragPx,
            velocityPxPerSecond,
        )
    }

    private fun defaultOverdragPx(): Float =
        DEFAULT_SIDE_DRAWER_OVERDRAG_DP * resources.displayMetrics.density

    private fun setHighFrameRateRequested(requested: Boolean) {
        if (highFrameRateRequested == requested) return
        highFrameRateRequested = requested
        applyRequestedFrameRate(this)
        panelView?.let(::applyRequestedFrameRate)
        applyRequestedFrameRate(contentPresentationView)
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

    private fun applyPresentation() {
        val currentProgress = if (laidOutDrawerWidthPx > 0f) {
            (revealPx / laidOutDrawerWidthPx).coerceIn(0f, 1f)
        } else {
            0f
        }
        val panel = panelView
        val drawerOpacity = motion.evaluate(SideDrawerMotionChannel.DrawerOpacity, currentProgress, 1f).coerceIn(0f, 1f)
        val drawerScale = motion.evaluate(SideDrawerMotionChannel.DrawerScale, currentProgress, 1f)
        val drawerTranslationX = motion.evaluate(SideDrawerMotionChannel.DrawerTranslationX, currentProgress, 0f)
        val drawerTranslationY = motion.evaluate(SideDrawerMotionChannel.DrawerTranslationY, currentProgress, 0f)
        if (panel != null) {
            if (panel.alpha != drawerOpacity) panel.alpha = drawerOpacity
            if (panel.scaleX != drawerScale) panel.scaleX = drawerScale
            if (panel.scaleY != drawerScale) panel.scaleY = drawerScale
            if (panel.translationX != drawerTranslationX) panel.translationX = drawerTranslationX
            if (panel.translationY != drawerTranslationY) panel.translationY = drawerTranslationY
        }

        val content = contentView
        val contentOpacity =
            motion.evaluate(SideDrawerMotionChannel.ContentOpacity, currentProgress, 1f).coerceIn(0f, 1f)
        val contentScale = motion.evaluate(SideDrawerMotionChannel.ContentScale, currentProgress, 1f)
        val contentTranslationX =
            openingDirection() * revealPx +
                motion.evaluate(SideDrawerMotionChannel.ContentTranslationX, currentProgress, 0f)
        val contentTranslationY =
            motion.evaluate(SideDrawerMotionChannel.ContentTranslationY, currentProgress, 0f)
        if (contentPresentationView.scaleX != contentScale) contentPresentationView.scaleX = contentScale
        if (contentPresentationView.scaleY != contentScale) contentPresentationView.scaleY = contentScale
        if (contentPresentationView.translationX != contentTranslationX) {
            contentPresentationView.translationX = contentTranslationX
        }
        if (contentPresentationView.translationY != contentTranslationY) {
            contentPresentationView.translationY = contentTranslationY
        }
        contentPresentationView.setShadowOpacity(
            motion.evaluate(SideDrawerMotionChannel.ContentShadowOpacity, currentProgress, 1f),
        )
        if (content != null) {
            if (content.alpha != contentOpacity) content.alpha = contentOpacity
            content.setDrawerOverlayOpacity(
                motion.evaluate(SideDrawerMotionChannel.OverlayOpacity, currentProgress, 0f),
            )
            content.setDrawerBorderOpacity(
                motion.evaluate(SideDrawerMotionChannel.ContentBorderOpacity, currentProgress, 1f),
            )
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
        if (contentView?.importantForAccessibility != contentState) {
            contentView?.importantForAccessibility = contentState
        }
    }

    private fun revealProgress(): Float {
        return if (laidOutDrawerWidthPx > 0f) {
            (revealPx / laidOutDrawerWidthPx).coerceIn(0f, 1f)
        } else {
            0f
        }
    }

    private fun targetPosition(nextOpen: Boolean): Float = if (nextOpen) laidOutDrawerWidthPx else 0f

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
            putDouble("progress", revealProgress().toDouble())
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
        const val NANOS_PER_SECOND = 1_000_000_000.0
        const val SETTLE_POSITION_EPSILON_PX = 0.5
        const val SETTLE_VELOCITY_EPSILON_PX_PER_SECOND = 5.0
    }
}
