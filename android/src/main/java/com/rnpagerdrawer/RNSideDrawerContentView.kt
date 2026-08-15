package com.rnpagerdrawer

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Path
import android.graphics.RectF
import android.os.Build
import android.view.View
import android.view.WindowInsets
import android.view.RoundedCorner
import android.widget.FrameLayout
import com.facebook.react.uimanager.ThemedReactContext

internal class RNSideDrawerContentView(reactContext: ThemedReactContext) : FrameLayout(reactContext) {
    private val clipPath = Path()
    private val clipRect = RectF()
    private val cornerRadii = FloatArray(8)
    private val screenCornerRadii = FloatArray(4)
    private var clipPathDirty = true
    private var shouldClipCorners = false
    private val scrim = View(reactContext).apply {
        isClickable = false
        setBackgroundColor(Color.TRANSPARENT)
        setOnClickListener { onScrimPress?.invoke() }
    }

    var onScrimPress: (() -> Unit)? = null

    var contentCornerRadiusPx: Float = -1f
        set(value) {
            if (field == value) return
            field = value
            clipPathDirty = true
            invalidate()
        }

    init {
        clipChildren = true
        clipToPadding = true
        super.addView(scrim, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        requestApplyInsets()
    }

    override fun onApplyWindowInsets(insets: WindowInsets): WindowInsets {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            screenCornerRadii[0] = insets.getRoundedCorner(RoundedCorner.POSITION_TOP_LEFT)?.radius?.toFloat() ?: 0f
            screenCornerRadii[1] = insets.getRoundedCorner(RoundedCorner.POSITION_TOP_RIGHT)?.radius?.toFloat() ?: 0f
            screenCornerRadii[2] = insets.getRoundedCorner(RoundedCorner.POSITION_BOTTOM_RIGHT)?.radius?.toFloat() ?: 0f
            screenCornerRadii[3] = insets.getRoundedCorner(RoundedCorner.POSITION_BOTTOM_LEFT)?.radius?.toFloat() ?: 0f
            clipPathDirty = true
            invalidate()
        }
        return super.onApplyWindowInsets(insets)
    }

    override fun onSizeChanged(width: Int, height: Int, oldWidth: Int, oldHeight: Int) {
        super.onSizeChanged(width, height, oldWidth, oldHeight)
        clipPathDirty = true
    }

    override fun dispatchDraw(canvas: Canvas) {
        updateClipPathIfNeeded()
        if (!shouldClipCorners) {
            super.dispatchDraw(canvas)
            return
        }
        val checkpoint = canvas.save()
        canvas.clipPath(clipPath)
        super.dispatchDraw(canvas)
        canvas.restoreToCount(checkpoint)
    }

    fun addReactChild(child: View, index: Int) {
        super.addView(child, index.coerceIn(0, childCount - 1))
        scrim.bringToFront()
    }

    fun getReactChildAt(index: Int): View? = if (index in 0 until childCount - 1) getChildAt(index) else null

    fun reactChildCount(): Int = childCount - 1

    fun removeReactChildAt(index: Int) {
        super.removeViewAt(index)
    }

    fun setDrawerProgress(progress: Float) {
        val clickable = progress > 0.001f
        if (scrim.isClickable != clickable) scrim.isClickable = clickable
    }

    fun setDrawerOverlayColor(color: Int) {
        scrim.setBackgroundColor(color)
    }

    fun setDrawerOverlayOpacity(opacity: Float) {
        val boundedOpacity = opacity.coerceIn(0f, 1f)
        if (scrim.alpha != boundedOpacity) scrim.alpha = boundedOpacity
    }

    private fun updateClipPathIfNeeded() {
        if (!clipPathDirty) return
        clipPathDirty = false

        val override = contentCornerRadiusPx
        val topLeft = if (override >= 0f) override else screenCornerRadii[0]
        val topRight = if (override >= 0f) override else screenCornerRadii[1]
        val bottomRight = if (override >= 0f) override else screenCornerRadii[2]
        val bottomLeft = if (override >= 0f) override else screenCornerRadii[3]
        shouldClipCorners = topLeft > 0f || topRight > 0f || bottomRight > 0f || bottomLeft > 0f
        if (!shouldClipCorners) {
            clipPath.rewind()
            return
        }

        cornerRadii[0] = topLeft
        cornerRadii[1] = topLeft
        cornerRadii[2] = topRight
        cornerRadii[3] = topRight
        cornerRadii[4] = bottomRight
        cornerRadii[5] = bottomRight
        cornerRadii[6] = bottomLeft
        cornerRadii[7] = bottomLeft
        clipRect.set(0f, 0f, width.toFloat(), height.toFloat())
        clipPath.rewind()
        clipPath.addRoundRect(clipRect, cornerRadii, Path.Direction.CW)
    }
}
