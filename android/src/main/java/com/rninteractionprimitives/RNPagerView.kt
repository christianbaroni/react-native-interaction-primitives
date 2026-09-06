package com.rninteractionprimitives

import android.os.Bundle
import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
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

internal class RNPagerView(private val reactContext: ThemedReactContext) : ViewGroup(reactContext) {
    enum class Orientation {
        Horizontal,
        Vertical,
    }

    private enum class Phase {
        Empty,
        Idle,
        Dragging,
        Settling,
    }

    private enum class SettlingSource {
        None,
        Programmatic,
        Release,
    }

    private val pages = ArrayList<RNPagerPageView>()
    private val scroller = OverScroller(reactContext)
    private val targetResolverScroller = OverScroller(reactContext)
    private val nestedScrollCoordinator = RNNestedScrollCoordinator(this)
    private val touchSlop = ViewConfiguration.get(reactContext).scaledTouchSlop
    private val maximumFlingVelocity = ViewConfiguration.get(reactContext).scaledMaximumFlingVelocity

    private var activePointerId = INVALID_POINTER_ID
    private var anchorOffsetPx = 0f
    private var anchorPage = 0
    private var downCrossAxisPx = 0f
    private var downMainAxisPx = 0f
    private var descendantRequestedDisallowIntercept = false
    private var gestureEligible = false
    private var hasLaidOutPages = false
    private var interruptedSettleVelocityPxPerSecond = 0f
    private var isDragging = false
    private var lastEmittedPage = Int.MIN_VALUE
    private var lastMainAxisPx = 0f
    private var laidOutPageExtentPx = 0f
    private var pausedSettleVelocityPxPerSecond = 0f
    private var phase = Phase.Empty
    private var selectedPage = 0
    private var settlePausedForTouch = false
    private var settlingSource = SettlingSource.None
    private var targetPage = -1
    private var velocityTracker: VelocityTracker? = null

    var initialPage: Int = 0
        set(value) {
            field = max(0, value)
            if (!hasLaidOutPages) {
                selectedPage = clampPage(field)
                updatePageAccessibility()
            }
        }

    var orientation: Orientation = Orientation.Horizontal
        set(value) {
            if (field == value) return

            if (phase == Phase.Settling) synchronizeScrollerFrame()
            val page = when (phase) {
                Phase.Settling -> targetPage
                Phase.Dragging -> currentSettledPage()
                Phase.Empty, Phase.Idle -> selectedPage
            }
            clearTouchTracking()
            scroller.abortAnimation()
            if (phase == Phase.Dragging || phase == Phase.Settling) {
                finishSettlingAtPage(page)
            }

            field = value
            laidOutPageExtentPx = 0f
            requestLayout()
        }

    var pageInsetPx: Float = 0f
        set(value) {
            field = max(0f, value)
            requestLayout()
        }

    var pageChangeEventsEnabled: Boolean = false

    var pageScrollEventsEnabled: Boolean = false

    var pageSpacingPx: Float = 0f
        set(value) {
            field = max(0f, value)
            requestLayout()
        }

    var pagerScrollEnabled: Boolean = true
        set(value) {
            if (field == value) return
            field = value
            if (!value) {
                if (isDragging) {
                    val page = clampPage((currentOffsetPx() / max(pageExtentPx(), 1f)).roundToInt())
                    settleToPage(page, SettlingSource.Release, true)
                } else {
                    resumePausedSettle()
                }
                clearTouchTracking()
            }
        }

    var stateEventsEnabled: Boolean = false

    init {
        clipChildren = false
        clipToPadding = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
    }

    override fun onDetachedFromWindow() {
        if (phase == Phase.Settling) synchronizeScrollerFrame()
        scroller.abortAnimation()
        when (phase) {
            Phase.Dragging -> finishSettlingAtPage(
                clampPage((currentOffsetPx() / max(pageExtentPx(), 1f)).roundToInt()),
            )
            Phase.Settling -> finishSettlingAtPage(targetPage)
            Phase.Empty, Phase.Idle -> Unit
        }
        cancelTouchInteraction()
        super.onDetachedFromWindow()
    }

    override fun requestLayout() {
        val layoutWasRequested = isLayoutRequested
        super.requestLayout()
        if (layoutWasRequested) return
        // React Native parents do not propagate native child layout requests.
        post {
            if (!isLayoutRequested) return@post
            measure(
                MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY),
                MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY),
            )
            layout(left, top, right, bottom)
        }
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val measuredWidth = MeasureSpec.getSize(widthMeasureSpec)
        val measuredHeight = MeasureSpec.getSize(heightMeasureSpec)
        setMeasuredDimension(measuredWidth, measuredHeight)

        val childWidth = if (orientation == Orientation.Horizontal) {
            max(0f, measuredWidth - pageInsetPx * 2f)
        } else {
            measuredWidth.toFloat()
        }.roundToInt()
        val childHeight = if (orientation == Orientation.Horizontal) {
            measuredHeight.toFloat()
        } else {
            max(0f, measuredHeight - pageInsetPx * 2f)
        }.roundToInt()
        val childWidthSpec = MeasureSpec.makeMeasureSpec(childWidth, MeasureSpec.EXACTLY)
        val childHeightSpec = MeasureSpec.makeMeasureSpec(childHeight, MeasureSpec.EXACTLY)
        pages.forEach { it.measure(childWidthSpec, childHeightSpec) }
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        val previousPageExtent = laidOutPageExtentPx
        val pageExtent = pageExtentPx()
        val pageExtentChanged = previousPageExtent > 0f && pageExtent != previousPageExtent
        val resizeDuringSettling = pageExtentChanged && phase == Phase.Settling
        if (resizeDuringSettling && !settlePausedForTouch) scroller.computeScrollOffset()
        val previousOffset = if (resizeDuringSettling && !settlePausedForTouch) {
            currentScrollerOffsetPx()
        } else {
            currentOffsetPx()
        }
        val previousPosition = if (previousPageExtent > 0f) {
            previousOffset / previousPageExtent
        } else {
            selectedPage.toFloat()
        }
        val settleVelocityInPagesPerSecond = when {
            !resizeDuringSettling -> 0f
            settlePausedForTouch -> pausedSettleVelocityPxPerSecond / previousPageExtent
            scroller.isFinished -> 0f
            else -> currentScrollerVelocityPxPerSecond() / previousPageExtent
        }
        if (resizeDuringSettling) scroller.abortAnimation()
        if (pageExtentChanged) {
            val pageExtentScale = pageExtent / previousPageExtent
            anchorOffsetPx *= pageExtentScale
            if (phase == Phase.Dragging) interruptedSettleVelocityPxPerSecond *= pageExtentScale
        }
        laidOutPageExtentPx = pageExtent

        pages.forEachIndexed { index, page ->
            val pageLeft: Int
            val pageTop: Int
            if (orientation == Orientation.Horizontal) {
                pageLeft = (pageInsetPx + index * pageExtent).roundToInt()
                pageTop = 0
            } else {
                pageLeft = 0
                pageTop = (pageInsetPx + index * pageExtent).roundToInt()
            }
            page.layout(pageLeft, pageTop, pageLeft + page.measuredWidth, pageTop + page.measuredHeight)
        }

        val nextPosition = if (previousPageExtent > 0f && hasLaidOutPages) {
            previousPosition
        } else {
            selectedPage.toFloat()
        }
        scrollToOffsetPx(nextPosition * pageExtent)
        hasLaidOutPages = pages.isNotEmpty()
        if (pages.isEmpty()) {
            transitionToPhase(Phase.Empty)
        } else if (phase == Phase.Empty) {
            transitionToPhase(Phase.Idle)
        }
        if (resizeDuringSettling && phase == Phase.Settling) {
            val resizedVelocityPxPerSecond = settleVelocityInPagesPerSecond * pageExtent
            if (settlePausedForTouch) {
                pausedSettleVelocityPxPerSecond = resizedVelocityPxPerSecond
            } else {
                startSettlingAnimation(animated = true, initialVelocityPxPerSecond = resizedVelocityPxPerSecond)
            }
        }
        publishState()
        publishPageScroll()
    }

    override fun onInitializeAccessibilityEvent(event: AccessibilityEvent) {
        super.onInitializeAccessibilityEvent(event)
        event.className = ACCESSIBILITY_CLASS_NAME
        event.isScrollable = pagerScrollEnabled && pages.size > 1
        event.itemCount = pages.size
        event.fromIndex = selectedPage
        event.toIndex = selectedPage
    }

    // CollectionInfo.Builder requires API 33; obtain supports the package's API 24 floor.
    @Suppress("DEPRECATION")
    override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) {
        super.onInitializeAccessibilityNodeInfo(info)
        info.className = ACCESSIBILITY_CLASS_NAME
        info.collectionInfo = AccessibilityNodeInfo.CollectionInfo.obtain(
            if (orientation == Orientation.Vertical) pages.size else 1,
            if (orientation == Orientation.Horizontal) pages.size else 1,
            false,
            AccessibilityNodeInfo.CollectionInfo.SELECTION_MODE_NONE,
        )
        if (!pagerScrollEnabled || pages.size <= 1) return

        val page = if (phase == Phase.Settling) targetPage else selectedPage
        if (page > 0) info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_BACKWARD)
        if (page < pages.lastIndex) info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_FORWARD)
        info.isScrollable = true
    }

    override fun performAccessibilityAction(action: Int, arguments: Bundle?): Boolean {
        if (!pagerScrollEnabled || pages.size <= 1) return super.performAccessibilityAction(action, arguments)
        val page = if (phase == Phase.Settling) targetPage else selectedPage
        val target = when (action) {
            AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD -> page - 1
            AccessibilityNodeInfo.ACTION_SCROLL_FORWARD -> page + 1
            else -> return super.performAccessibilityAction(action, arguments)
        }
        if (target !in pages.indices) return false
        setPage(target, animated = true)
        return true
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if (pagerScrollEnabled && pages.size > 1 && event.actionMasked == MotionEvent.ACTION_DOWN) {
            pauseSettleForTouch()
        }
        val handled = super.dispatchTouchEvent(event)
        if (event.actionMasked == MotionEvent.ACTION_UP || event.actionMasked == MotionEvent.ACTION_CANCEL) {
            resumePausedSettle()
            finishTouch(event)
        }
        return handled
    }

    override fun onInterceptTouchEvent(event: MotionEvent): Boolean {
        if (!pagerScrollEnabled || pages.size <= 1) return false
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                gestureEligible = true
                initializeTouch(event)
            }
            MotionEvent.ACTION_MOVE -> {
                if (!gestureEligible) return false
                val pointerIndex = event.findPointerIndex(activePointerId)
                if (pointerIndex < 0) return false
                val main = mainAxis(event, pointerIndex)
                val cross = crossAxis(event, pointerIndex)
                val mainDelta = main - downMainAxisPx
                val crossDelta = cross - downCrossAxisPx
                val mainAxisIntent = abs(mainDelta) > touchSlop && abs(mainDelta) > abs(crossDelta)
                if (mainAxisIntent && touchedDescendantCanScroll(mainDelta)) {
                    yieldGestureToDescendant()
                    return false
                }
                if (mainAxisIntent) {
                    beginDraggingFromCurrentOffset()
                    lastMainAxisPx = main
                    nestedScrollCoordinator.beginNativeGesture(event)
                    parent?.requestDisallowInterceptTouchEvent(true)
                    return true
                }
                if (max(abs(mainDelta), abs(crossDelta)) > touchSlop && abs(crossDelta) >= abs(mainDelta)) {
                    yieldGestureToDescendant()
                }
            }
            MotionEvent.ACTION_CANCEL, MotionEvent.ACTION_UP -> {
                resumePausedSettle()
                finishTouch(event)
            }
        }
        return false
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

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!pagerScrollEnabled || pages.isEmpty()) return false
        if (event.actionMasked == MotionEvent.ACTION_DOWN) {
            if (isDragging) return true
            gestureEligible = true
            initializeTouch(event)
            return true
        }
        ensureVelocityTracker().addMovement(event)
        when (event.actionMasked) {
            MotionEvent.ACTION_POINTER_UP -> handlePointerUp(event)
            MotionEvent.ACTION_MOVE -> {
                val pointerIndex = event.findPointerIndex(activePointerId)
                if (pointerIndex < 0) return false
                val main = mainAxis(event, pointerIndex)
                if (!isDragging) {
                    val mainDelta = main - downMainAxisPx
                    val crossDelta = crossAxis(event, pointerIndex) - downCrossAxisPx
                    if (abs(mainDelta) > touchSlop && abs(mainDelta) > abs(crossDelta)) {
                        beginDraggingFromCurrentOffset()
                        nestedScrollCoordinator.beginNativeGesture(event)
                        parent?.requestDisallowInterceptTouchEvent(true)
                    }
                }
                if (isDragging) {
                    scrollToOffsetPx(currentOffsetPx() + lastMainAxisPx - main)
                    lastMainAxisPx = main
                    publishPageScroll()
                }
                return true
            }
            MotionEvent.ACTION_UP -> {
                if (isDragging) {
                    val tracker = ensureVelocityTracker()
                    tracker.computeCurrentVelocity(1000, maximumFlingVelocity.toFloat())
                    val velocity = if (orientation == Orientation.Horizontal) {
                        -tracker.getXVelocity(activePointerId)
                    } else {
                        -tracker.getYVelocity(activePointerId)
                    }
                    settleFromRelease(velocity)
                }
                finishTouch(event)
                return true
            }
            MotionEvent.ACTION_CANCEL -> {
                if (isDragging) {
                    settleToPage(
                        clampPage((currentOffsetPx() / max(pageExtentPx(), 1f)).roundToInt()),
                        SettlingSource.Release,
                        true,
                    )
                }
                finishTouch(event)
                return true
            }
        }
        return true
    }

    override fun computeScroll() {
        if (phase != Phase.Settling || settlePausedForTouch) return
        if (scroller.computeScrollOffset()) {
            val offset = if (orientation == Orientation.Horizontal) scroller.currX else scroller.currY
            scrollToOffsetPx(offset.toFloat())
            publishPageScroll()
            postInvalidateOnAnimation()
            return
        }
        finishSettlingAtPage(targetPage)
    }

    fun addPagerPage(page: RNPagerPageView, index: Int) {
        val boundedIndex = index.coerceIn(0, pages.size)
        pages.add(boundedIndex, page)
        super.addView(page, boundedIndex, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        if (!hasLaidOutPages) selectedPage = clampPage(initialPage)
        if (phase == Phase.Empty) transitionToPhase(Phase.Idle)
        updatePageAccessibility()
        requestLayout()
        publishState()
    }

    fun getPagerPageAt(index: Int): RNPagerPageView? = pages.getOrNull(index)

    fun pagerPageCount(): Int = pages.size

    fun removePagerPageAt(index: Int) {
        val page = pages.removeAt(index)
        super.removeView(page)
        selectedPage = clampPage(selectedPage)
        if (pages.isEmpty()) {
            hasLaidOutPages = false
            transitionToPhase(Phase.Empty)
            cancelTouchInteraction()
            scroller.abortAnimation()
            clearPausedSettle()
            scrollToOffsetPx(0f)
        }
        updatePageAccessibility()
        requestLayout()
        publishState()
    }

    fun setPage(page: Int, animated: Boolean) {
        if (page !in pages.indices) return
        if (phase == Phase.Settling) synchronizeScrollerFrame()
        clearTouchTracking()
        settleToPage(page, SettlingSource.Programmatic, animated)
    }

    fun requestPageScrollSnapshot() {
        // RN commands can bypass UI queue work, including Reanimated registration.
        post {
            if (hasLaidOutPages || pages.isEmpty()) publishPageScroll()
        }
    }

    fun prepareForRemoval() {
        cancelTouchInteraction()
        scroller.abortAnimation()
        clearPausedSettle()
        pages.clear()
        removeAllViews()
        hasLaidOutPages = false
        pageScrollEventsEnabled = false
        transitionToPhase(Phase.Empty)
    }

    private fun initializeTouch(event: MotionEvent) {
        velocityTracker?.recycle()
        velocityTracker = VelocityTracker.obtain().also { it.addMovement(event) }
        activePointerId = event.getPointerId(0)
        downMainAxisPx = mainAxis(event, 0)
        downCrossAxisPx = crossAxis(event, 0)
        lastMainAxisPx = downMainAxisPx
        descendantRequestedDisallowIntercept = false
        isDragging = false
    }

    private fun clearTouchTracking() {
        activePointerId = INVALID_POINTER_ID
        gestureEligible = false
        isDragging = false
        descendantRequestedDisallowIntercept = false
        super.requestDisallowInterceptTouchEvent(false)
        velocityTracker?.recycle()
        velocityTracker = null
    }

    private fun finishTouch(event: MotionEvent) {
        clearTouchTracking()
        nestedScrollCoordinator.endNativeGesture(event)
    }

    private fun cancelTouchInteraction() {
        clearTouchTracking()
        nestedScrollCoordinator.cancelNativeGesture()
    }

    private fun yieldGestureToDescendant() {
        gestureEligible = false
        if (descendantRequestedDisallowIntercept) super.requestDisallowInterceptTouchEvent(true)
    }

    private fun touchedDescendantCanScroll(mainAxisDelta: Float): Boolean {
        return if (orientation == Orientation.Horizontal) {
            nestedScrollCoordinator.touchedDescendantCanScrollHorizontally(
                downMainAxisPx,
                downCrossAxisPx,
                mainAxisDelta,
            )
        } else {
            nestedScrollCoordinator.touchedDescendantCanScrollVertically(
                downCrossAxisPx,
                downMainAxisPx,
                mainAxisDelta,
            )
        }
    }

    private fun handlePointerUp(event: MotionEvent) {
        val actionIndex = event.actionIndex
        if (event.getPointerId(actionIndex) != activePointerId) return
        val nextIndex = if (actionIndex == 0) 1 else 0
        activePointerId = event.getPointerId(nextIndex)
        lastMainAxisPx = mainAxis(event, nextIndex)
        velocityTracker?.clear()
    }

    private fun synchronizeScrollerFrame() {
        if (!scroller.computeScrollOffset()) return
        val offset = if (orientation == Orientation.Horizontal) scroller.currX else scroller.currY
        scrollToOffsetPx(offset.toFloat())
        publishPageScroll()
    }

    private fun beginDraggingFromCurrentOffset() {
        if (isDragging) return
        val interruptedTarget = if (phase == Phase.Settling) targetPage else null
        val interruptedVelocity = when {
            phase != Phase.Settling -> 0f
            settlePausedForTouch -> pausedSettleVelocityPxPerSecond
            !scroller.isFinished -> currentScrollerVelocityPxPerSecond()
            else -> 0f
        }
        clearPausedSettle()
        scroller.abortAnimation()
        isDragging = true
        anchorOffsetPx = currentOffsetPx()
        val extent = pageExtentPx()
        anchorPage = interruptedTarget?.let(::clampPage)
            ?: clampPage(if (extent > 0f) (anchorOffsetPx / extent).roundToInt() else selectedPage)
        targetPage = anchorPage
        interruptedSettleVelocityPxPerSecond = interruptedVelocity
        settlingSource = SettlingSource.None
        transitionToPhase(Phase.Dragging)
        publishState()
    }

    private fun settleFromRelease(velocityPxPerSecond: Float) {
        val resolvedVelocity = velocityPxPerSecond + interruptedSettleVelocityPxPerSecond
        interruptedSettleVelocityPxPerSecond = 0f
        val naturalOffset = naturalTargetOffset(currentOffsetPx(), resolvedVelocity)
        val target = resolveTargetPage(anchorPage, naturalOffset, pages.size, pageExtentPx())
        settleToPage(target, SettlingSource.Release, true, resolvedVelocity)
    }

    private fun settleToPage(
        page: Int,
        source: SettlingSource,
        animated: Boolean,
        releaseVelocityPxPerSecond: Float = 0f,
    ) {
        clearPausedSettle()
        if (source == SettlingSource.Programmatic) {
            anchorOffsetPx = currentOffsetPx()
            anchorPage = currentSettledPage()
        }
        targetPage = clampPage(page)
        settlingSource = source
        transitionToPhase(Phase.Settling)
        publishState()

        startSettlingAnimation(animated, releaseVelocityPxPerSecond)
    }

    private fun finishSettlingAtPage(page: Int) {
        if (phase != Phase.Settling && phase != Phase.Dragging) return
        clearPausedSettle()
        val nextPage = clampPage(page)
        val selectionChanged = nextPage != selectedPage
        selectedPage = nextPage
        scrollToOffsetPx(offsetForPage(selectedPage))
        updatePageAccessibility()
        transitionToPhase(if (pages.isEmpty()) Phase.Empty else Phase.Idle)
        publishState()
        publishPageScroll()
        if (selectionChanged) sendAccessibilityEvent(AccessibilityEvent.TYPE_VIEW_SCROLLED)
        if (lastEmittedPage != selectedPage) {
            lastEmittedPage = selectedPage
            if (!pageChangeEventsEnabled) return
            val payload = Arguments.createMap()
            payload.putInt("page", selectedPage)
            dispatchEvent("topPageChange", payload, coalesces = false)
        }
    }

    private fun updatePageAccessibility() {
        pages.forEachIndexed { index, page ->
            val importance = if (index == selectedPage) {
                IMPORTANT_FOR_ACCESSIBILITY_AUTO
            } else {
                IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            }
            if (page.importantForAccessibility != importance) page.importantForAccessibility = importance
        }
    }

    private fun currentScrollerVelocityPxPerSecond(): Float {
        val remaining = if (orientation == Orientation.Horizontal) {
            scroller.finalX - scroller.currX
        } else {
            scroller.finalY - scroller.currY
        }
        if (remaining == 0) return 0f
        return scroller.currVelocity * if (remaining > 0) 1f else -1f
    }

    private fun currentScrollerOffsetPx(): Float {
        return if (orientation == Orientation.Horizontal) {
            scroller.currX.toFloat()
        } else {
            scroller.currY.toFloat()
        }
    }

    private fun pauseSettleForTouch() {
        if (phase != Phase.Settling || settlePausedForTouch) return
        synchronizeScrollerFrame()
        if (phase != Phase.Settling) return
        pausedSettleVelocityPxPerSecond = if (scroller.isFinished) {
            0f
        } else {
            currentScrollerVelocityPxPerSecond()
        }
        scroller.abortAnimation()
        settlePausedForTouch = true
    }

    private fun resumePausedSettle() {
        if (!settlePausedForTouch || phase != Phase.Settling) return
        clearPausedSettle()
        startSettlingAnimation(animated = true, initialVelocityPxPerSecond = 0f)
    }

    private fun clearPausedSettle() {
        settlePausedForTouch = false
        pausedSettleVelocityPxPerSecond = 0f
    }

    private fun startSettlingAnimation(animated: Boolean, initialVelocityPxPerSecond: Float) {
        val start = currentOffsetPx().roundToInt()
        val end = offsetForPage(targetPage).roundToInt()
        scroller.abortAnimation()
        if (!animated || start == end) {
            scrollToOffsetPx(end.toFloat())
            publishPageScroll()
            finishSettlingAtPage(targetPage)
            return
        }
        if (!tryStartFling(start, end, initialVelocityPxPerSecond)) {
            if (orientation == Orientation.Horizontal) {
                scroller.startScroll(start, 0, end - start, 0)
            } else {
                scroller.startScroll(0, start, 0, end - start)
            }
        }
        postInvalidateOnAnimation()
    }

    private fun tryStartFling(start: Int, end: Int, velocityPxPerSecond: Float): Boolean {
        val distance = end - start
        if (distance == 0 || velocityPxPerSecond * distance <= 0f) return false
        val minOffset = min(start, end)
        val maxOffset = max(start, end)
        if (orientation == Orientation.Horizontal) {
            scroller.fling(start, 0, velocityPxPerSecond.roundToInt(), 0, minOffset, maxOffset, 0, 0)
            if (scroller.finalX == end) return true
        } else {
            scroller.fling(0, start, 0, velocityPxPerSecond.roundToInt(), 0, 0, minOffset, maxOffset)
            if (scroller.finalY == end) return true
        }
        scroller.abortAnimation()
        return false
    }

    private fun naturalTargetOffset(currentOffset: Float, velocityPxPerSecond: Float): Float {
        val maxOffset = maxScrollOffsetPx().roundToInt()
        targetResolverScroller.forceFinished(true)
        if (orientation == Orientation.Horizontal) {
            targetResolverScroller.fling(
                currentOffset.roundToInt(), 0, velocityPxPerSecond.roundToInt(), 0, 0, maxOffset, 0, 0,
            )
            return targetResolverScroller.finalX.toFloat()
        }
        targetResolverScroller.fling(
            0, currentOffset.roundToInt(), 0, velocityPxPerSecond.roundToInt(), 0, 0, 0, maxOffset,
        )
        return targetResolverScroller.finalY.toFloat()
    }

    private fun statePayload(): WritableMap {
        val extentPx = pageExtentPx()
        val offsetPx = currentOffsetPx()
        val position = if (extentPx > 0f) offsetPx / extentPx else 0f
        val payload = Arguments.createMap()
        payload.putDouble("anchorOffset", toDip(anchorOffsetPx))
        payload.putInt("anchorPage", anchorPage)
        payload.putDouble("offset", toDip(offsetPx))
        payload.putInt("page", if (pages.isEmpty()) 0 else clampPage(position.roundToInt()))
        payload.putInt("pageCount", pages.size)
        payload.putDouble("pageExtent", toDip(extentPx))
        payload.putString("phase", phaseName())
        payload.putDouble("position", position.toDouble())
        payload.putString("settlingSource", settlingSourceName())
        payload.putInt("targetPage", if (phase == Phase.Settling) targetPage else -1)
        return payload
    }

    private fun publishState() {
        if (!stateEventsEnabled) return
        dispatchEvent("topStateChange", statePayload(), coalesces = false)
    }

    private fun publishPageScroll() {
        if (!pageScrollEventsEnabled) return
        dispatchEvent("topPageScroll", statePayload(), coalesces = true)
    }

    private fun dispatchEvent(eventName: String, payload: WritableMap, coalesces: Boolean) {
        val tag = id
        if (tag == View.NO_ID) return
        UIManagerHelper.getEventDispatcherForReactTag(reactContext, tag)
            ?.dispatchEvent(RNDirectEvent(UIManagerHelper.getSurfaceId(this), tag, eventName, payload, coalesces))
    }

    private fun transitionToPhase(next: Phase) {
        phase = if (pages.isEmpty()) Phase.Empty else next
    }

    private fun phaseName(): String = when (phase) {
        Phase.Empty -> "empty"
        Phase.Idle -> "idle"
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

    private fun mainAxis(event: MotionEvent, pointerIndex: Int): Float {
        return if (orientation == Orientation.Horizontal) event.getX(pointerIndex) else event.getY(pointerIndex)
    }

    private fun crossAxis(event: MotionEvent, pointerIndex: Int): Float {
        return if (orientation == Orientation.Horizontal) event.getY(pointerIndex) else event.getX(pointerIndex)
    }

    private fun currentOffsetPx(): Float {
        return if (orientation == Orientation.Horizontal) scrollX.toFloat() else scrollY.toFloat()
    }

    private fun scrollToOffsetPx(offset: Float) {
        val bounded = offset.coerceIn(0f, maxScrollOffsetPx()).roundToInt()
        if (orientation == Orientation.Horizontal) scrollTo(bounded, 0) else scrollTo(0, bounded)
    }

    private fun offsetForPage(page: Int): Float = clampPage(page) * pageExtentPx()

    private fun maxScrollOffsetPx(): Float = max(0f, (pages.size - 1) * pageExtentPx())

    private fun pageExtentPx(): Float {
        return if (orientation == Orientation.Horizontal) pageWidthPx() + pageSpacingPx else pageHeightPx() + pageSpacingPx
    }

    private fun pageWidthPx(): Float {
        return if (orientation == Orientation.Horizontal) max(0f, width - pageInsetPx * 2f) else width.toFloat()
    }

    private fun pageHeightPx(): Float {
        return if (orientation == Orientation.Horizontal) height.toFloat() else max(0f, height - pageInsetPx * 2f)
    }

    private fun currentSettledPage(): Int {
        val extent = pageExtentPx()
        return clampPage(if (extent > 0f) (currentOffsetPx() / extent).roundToInt() else selectedPage)
    }

    private fun clampPage(page: Int): Int {
        return if (pages.isEmpty()) 0 else page.coerceIn(0, pages.lastIndex)
    }

    private fun toDip(px: Float): Double = PixelUtil.toDIPFromPixel(px).toDouble()

    private fun ensureVelocityTracker(): VelocityTracker {
        return velocityTracker ?: VelocityTracker.obtain().also { velocityTracker = it }
    }

    private fun resolveTargetPage(
        anchor: Int,
        naturalTargetOffset: Float,
        pageCount: Int,
        pageExtent: Float,
    ): Int {
        if (pageCount <= 0) return 0
        val boundedAnchor = anchor.coerceIn(0, pageCount - 1)
        if (pageExtent <= 0f) return boundedAnchor
        val projectedPage = (naturalTargetOffset / pageExtent).roundToInt().coerceIn(0, pageCount - 1)
        return projectedPage.coerceIn(boundedAnchor - 1, boundedAnchor + 1).coerceIn(0, pageCount - 1)
    }

    private companion object {
        const val ACCESSIBILITY_CLASS_NAME = "androidx.viewpager.widget.ViewPager"
        const val INVALID_POINTER_ID = -1
    }
}
