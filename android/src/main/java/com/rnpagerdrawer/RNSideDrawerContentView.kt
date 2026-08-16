package com.rnpagerdrawer

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.os.Build
import android.view.RoundedCorner
import android.view.View
import android.view.ViewOutlineProvider
import android.view.WindowInsets
import android.widget.FrameLayout
import com.facebook.react.uimanager.ThemedReactContext
import kotlin.math.max
import kotlin.math.min

private class RNSideDrawerBorderView(context: Context) : View(context) {
    private val outerCornerRadii = FloatArray(8)
    private val strokeCornerRadii = FloatArray(8)
    private val strokePath = Path()
    private val strokeRect = RectF()
    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.TRANSPARENT
        style = Paint.Style.STROKE
    }
    private var pathDirty = true

    override fun hasOverlappingRendering(): Boolean = false

    override fun onDraw(canvas: Canvas) {
        if (strokePaint.strokeWidth <= 0f || Color.alpha(strokePaint.color) == 0) return
        updatePathIfNeeded()
        canvas.drawPath(strokePath, strokePaint)
    }

    override fun onSizeChanged(width: Int, height: Int, oldWidth: Int, oldHeight: Int) {
        super.onSizeChanged(width, height, oldWidth, oldHeight)
        pathDirty = true
    }

    fun setColor(color: Int) {
        if (strokePaint.color == color) return
        strokePaint.color = color
        invalidate()
    }

    fun setCornerRadii(radii: FloatArray) {
        if (outerCornerRadii.contentEquals(radii)) return
        radii.copyInto(outerCornerRadii)
        pathDirty = true
        invalidate()
    }

    fun setWidth(width: Float) {
        if (strokePaint.strokeWidth == width) return
        strokePaint.strokeWidth = width
        pathDirty = true
        invalidate()
    }

    private fun updatePathIfNeeded() {
        if (!pathDirty) return
        pathDirty = false

        val halfWidth = strokePaint.strokeWidth * 0.5f
        val horizontalInset = min(halfWidth, width * 0.5f)
        val verticalInset = min(halfWidth, height * 0.5f)
        strokeRect.set(horizontalInset, verticalInset, width - horizontalInset, height - verticalInset)
        for (index in strokeCornerRadii.indices) {
            strokeCornerRadii[index] = max(0f, outerCornerRadii[index] - halfWidth)
        }
        strokePath.rewind()
        strokePath.addRoundRect(strokeRect, strokeCornerRadii, Path.Direction.CW)
    }
}

private class RNSideDrawerShadowView(context: Context) : View(context) {
    private val cornerRadii = FloatArray(8)
    private val shadowPath = Path()
    private val shadowRect = RectF()
    private var colorAlpha = 0f
    private var motionOpacity = 1f
    private var pathDirty = true

    init {
        forceHasOverlappingRendering(false)
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        isClickable = false
        setWillNotDraw(true)
        outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(view: View, outline: Outline) {
                if (view.width <= 0 || view.height <= 0) {
                    outline.setEmpty()
                    return
                }
                updatePathIfNeeded()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    outline.setPath(shadowPath)
                } else {
                    @Suppress("DEPRECATION")
                    outline.setConvexPath(shadowPath)
                }
                outline.alpha = 1f
            }
        }
    }

    override fun onSizeChanged(width: Int, height: Int, oldWidth: Int, oldHeight: Int) {
        super.onSizeChanged(width, height, oldWidth, oldHeight)
        pathDirty = true
        invalidateOutline()
    }

    fun setColor(color: Int) {
        val nextAlpha = Color.alpha(color) / 255f
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val opaqueColor = Color.rgb(Color.red(color), Color.green(color), Color.blue(color))
            if (outlineAmbientShadowColor != opaqueColor) outlineAmbientShadowColor = opaqueColor
            if (outlineSpotShadowColor != opaqueColor) outlineSpotShadowColor = opaqueColor
        }
        if (colorAlpha == nextAlpha) return
        colorAlpha = nextAlpha
        updateAlpha()
    }

    fun setCornerRadii(radii: FloatArray) {
        if (cornerRadii.contentEquals(radii)) return
        radii.copyInto(cornerRadii)
        pathDirty = true
        invalidateOutline()
    }

    fun setMotionOpacity(opacity: Float) {
        val value = opacity.coerceIn(0f, 1f)
        if (motionOpacity == value) return
        motionOpacity = value
        updateAlpha()
    }

    private fun updateAlpha() {
        val value = colorAlpha * motionOpacity
        if (alpha != value) alpha = value
    }

    private fun updatePathIfNeeded() {
        if (!pathDirty) return
        pathDirty = false
        shadowRect.set(0f, 0f, width.toFloat(), height.toFloat())
        shadowPath.rewind()
        shadowPath.addRoundRect(shadowRect, cornerRadii, Path.Direction.CW)
    }
}

internal class RNSideDrawerContentPresentationView(context: Context) : FrameLayout(context) {
    private val resolvedCornerRadii = FloatArray(8)
    private val screenCornerRadii = FloatArray(4)
    private val shadow = RNSideDrawerShadowView(context)
    private var content: RNSideDrawerContentView? = null
    private var shadowElevationPx = 0f

    var contentCornerRadiusPx: Float = -1f
        set(value) {
            if (field == value) return
            field = value
            updateCornerRadii()
        }

    init {
        clipChildren = false
        clipToPadding = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        isClickable = false
        super.addView(shadow, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
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
            updateCornerRadii()
        }
        return super.onApplyWindowInsets(insets)
    }

    override fun onSizeChanged(width: Int, height: Int, oldWidth: Int, oldHeight: Int) {
        super.onSizeChanged(width, height, oldWidth, oldHeight)
        updateCornerRadii()
    }

    fun setContentView(view: RNSideDrawerContentView) {
        if (content === view) return
        content?.let { super.removeView(it) }
        content = view
        view.outlineProvider = null
        view.elevation = shadowElevationPx
        super.addView(view, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        view.setCornerRadii(resolvedCornerRadii)
    }

    fun removeContentView(view: RNSideDrawerContentView) {
        if (content !== view) return
        content = null
        super.removeView(view)
    }

    fun setShadowColor(color: Int) {
        shadow.setColor(color)
    }

    fun setShadowElevation(elevationPx: Float) {
        val value = if (elevationPx.isFinite()) elevationPx.coerceAtLeast(0f) else 0f
        if (shadowElevationPx == value) return
        shadowElevationPx = value
        shadow.elevation = value
        content?.elevation = value
    }

    fun setShadowOpacity(opacity: Float) {
        shadow.setMotionOpacity(opacity)
    }

    private fun updateCornerRadii() {
        val override = contentCornerRadiusPx
        val topLeft = if (override >= 0f) override else screenCornerRadii[0]
        val topRight = if (override >= 0f) override else screenCornerRadii[1]
        val bottomRight = if (override >= 0f) override else screenCornerRadii[2]
        val bottomLeft = if (override >= 0f) override else screenCornerRadii[3]
        val horizontalScale = min(
            1f,
            min(
                width.toFloat() / max(1f, topLeft + topRight),
                width.toFloat() / max(1f, bottomLeft + bottomRight),
            ),
        )
        val verticalScale = min(
            1f,
            min(
                height.toFloat() / max(1f, topLeft + bottomLeft),
                height.toFloat() / max(1f, topRight + bottomRight),
            ),
        )
        val scale = min(horizontalScale, verticalScale)
        resolvedCornerRadii[0] = topLeft * scale
        resolvedCornerRadii[1] = topLeft * scale
        resolvedCornerRadii[2] = topRight * scale
        resolvedCornerRadii[3] = topRight * scale
        resolvedCornerRadii[4] = bottomRight * scale
        resolvedCornerRadii[5] = bottomRight * scale
        resolvedCornerRadii[6] = bottomLeft * scale
        resolvedCornerRadii[7] = bottomLeft * scale
        shadow.setCornerRadii(resolvedCornerRadii)
        content?.setCornerRadii(resolvedCornerRadii)
    }
}

internal class RNSideDrawerContentView(reactContext: ThemedReactContext) : FrameLayout(reactContext) {
    private val clipPath = Path()
    private val clipRect = RectF()
    private val cornerRadii = FloatArray(8)
    private var clipPathDirty = true
    private var shouldClipCorners = false
    private val scrim = View(reactContext).apply {
        forceHasOverlappingRendering(false)
        isClickable = false
        setBackgroundColor(Color.TRANSPARENT)
        setOnClickListener { onScrimPress?.invoke() }
    }
    private val border = RNSideDrawerBorderView(reactContext).apply {
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        isClickable = false
    }
    var onScrimPress: (() -> Unit)? = null

    init {
        clipChildren = true
        clipToPadding = true
        super.addView(scrim, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        super.addView(border, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
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
        super.addView(child, index.coerceIn(0, reactChildCount()))
        scrim.bringToFront()
        border.bringToFront()
    }

    fun getReactChildAt(index: Int): View? = if (index in 0 until reactChildCount()) getChildAt(index) else null

    fun reactChildCount(): Int = childCount - PRIVATE_CHILD_COUNT

    fun removeReactChildAt(index: Int) {
        super.removeViewAt(index)
    }

    fun setDrawerProgress(progress: Float) {
        val clickable = progress > 0.001f
        if (scrim.isClickable != clickable) scrim.isClickable = clickable
    }

    fun setDrawerBorderColor(color: Int) {
        border.setColor(color)
    }

    fun setDrawerBorderOpacity(opacity: Float) {
        val boundedOpacity = opacity.coerceIn(0f, 1f)
        if (border.alpha != boundedOpacity) border.alpha = boundedOpacity
    }

    fun setDrawerBorderWidth(widthPx: Float) {
        val resolvedWidth = if (widthPx.isFinite()) widthPx.coerceAtLeast(0f) else 0f
        border.setWidth(resolvedWidth)
    }

    fun setCornerRadii(radii: FloatArray) {
        if (cornerRadii.contentEquals(radii)) return
        radii.copyInto(cornerRadii)
        border.setCornerRadii(cornerRadii)
        shouldClipCorners = cornerRadii.any { it > 0f }
        clipPathDirty = true
        invalidate()
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

        if (!shouldClipCorners) {
            clipPath.rewind()
            return
        }

        clipRect.set(0f, 0f, width.toFloat(), height.toFloat())
        clipPath.rewind()
        clipPath.addRoundRect(clipRect, cornerRadii, Path.Direction.CW)
    }

    private companion object {
        const val PRIVATE_CHILD_COUNT = 2
    }
}
