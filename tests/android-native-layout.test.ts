import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const androidSource = resolve(process.cwd(), 'android/src/main/java/com/rninteractionprimitives');

function source(filename: string): string {
  return readFileSync(resolve(androidSource, filename), 'utf8');
}

function between(value: string, start: string, end: string): string {
  const startIndex = value.indexOf(start);
  if (startIndex < 0) throw new Error(`Missing source boundary: ${start}`);
  const contentStart = startIndex + start.length;
  const endIndex = value.indexOf(end, contentStart);
  if (endIndex < 0) throw new Error(`Missing source boundary: ${end}`);
  return value.slice(contentStart, endIndex);
}

describe('Android native view ownership', () => {
  it('lays out only component-owned layers in the drawer content host', () => {
    const content = source('RNSideDrawerContentView.kt');
    const manager = source('RNSideDrawerContentViewManager.kt');
    const measure = between(content, 'override fun onMeasure', 'override fun onLayout');
    const layout = between(content, 'override fun onLayout', 'override fun onSizeChanged');

    expect(measure).toContain('scrim.measure');
    expect(measure).toContain('border.measure');
    expect([...measure.matchAll(/\.measure\(/g)]).toHaveLength(2);
    expect(measure).not.toContain('super.onMeasure');
    expect(layout).toContain('scrim.layout');
    expect(layout).toContain('border.layout');
    expect([...layout.matchAll(/\.layout\(/g)]).toHaveLength(2);
    expect(layout).not.toContain('super.onLayout');
    expect(measure + layout).not.toContain('getChildAt');
    expect(manager).not.toContain('needsCustomLayoutForChildren');
  });

  it('leaves panel child layout entirely to UIManager', () => {
    const panel = source('RNSideDrawerPanelView.kt');
    const manager = source('RNSideDrawerPanelViewManager.kt');

    expect(panel).toContain('setMeasuredDimension');
    expect(panel).toContain('override fun onLayout');
    expect(panel).not.toContain('super.onMeasure');
    expect(panel).not.toContain('super.onLayout');
    expect(panel).not.toContain('.measure(');
    expect(panel).not.toContain('.layout(');
    expect(manager).not.toContain('needsCustomLayoutForChildren');
  });

  it('clips transformed drawer content only at the drawer root', () => {
    const panel = source('RNSideDrawerPanelView.kt');
    const root = source('RNSideDrawerView.kt');

    expect(panel).toContain('clipChildren = false');
    expect(panel).toContain('clipToPadding = false');
    expect(root).toContain('clipChildren = true');
    expect(root).toContain('clipToPadding = true');
  });

  it('derives scrim hit ownership from the drawer target, not visual progress', () => {
    const content = source('RNSideDrawerContentView.kt');
    const root = source('RNSideDrawerView.kt');
    const mount = between(root, 'fun addDrawerSlot(', 'fun drawerSlotCount');
    const transition = between(root, 'private fun startTransition(', 'private fun startTransitionAnimation');
    const presentation = between(root, 'private fun applyPresentation()', 'private fun publishProgress');

    expect(content).toContain('fun setDrawerScrimEnabled(enabled: Boolean)');
    expect(content).toContain('if (scrim.isClickable != enabled) scrim.isClickable = enabled');
    expect(content).toContain('get() = if (isClickable) PointerEvents.AUTO else PointerEvents.NONE');
    expect(mount).toContain('child.setDrawerScrimEnabled(targetOpen)');
    expect(transition).toContain('contentView?.setDrawerScrimEnabled(openAtEnd)');
    expect(presentation).toContain('content.setDrawerScrimEnabled(targetOpen)');
    expect(content + root).not.toContain('setDrawerProgress');
  });

  it('dismisses content input only after an opening action is accepted', () => {
    const root = source('RNSideDrawerView.kt');
    const dismiss = between(root, 'private fun dismissContentKeyboard()', 'override fun onAttachedToWindow()');
    const command = between(root, 'private fun setOpen(', 'private fun startReleaseTransition(');
    const drag = between(root, 'private fun beginDragging(', 'private fun clearTouchTracking(');
    const sameStateGuard = 'if ((phase == Phase.Open && nextOpen) || (phase == Phase.Closed && !nextOpen)) return';

    expect(dismiss).toContain('contentView?.findFocus()');
    expect(dismiss).toContain('focusedView.onCheckIsTextEditor()');
    expect(dismiss).toContain('focusedView.clearFocus()');
    expect(dismiss).toContain('hideSoftInputFromWindow(windowToken, 0)');
    expect(dismiss).toContain('Build.VERSION.SDK_INT <= Build.VERSION_CODES.P');
    expect(dismiss).toContain('focusRoot.descendantFocusability = FOCUS_BLOCK_DESCENDANTS');
    expect(command).toContain('if (nextOpen) dismissContentKeyboard()');
    expect(command.indexOf(sameStateGuard)).toBeLessThan(command.lastIndexOf('dismissContentKeyboard()'));
    expect(drag).toContain('if (!interruptedTarget) dismissContentKeyboard()');
    expect(root.match(/dismissContentKeyboard\(\)/g)).toHaveLength(4);
    expect(root).not.toContain('showSoftInput');
    expect(root).not.toContain('requestFocus()');
  });
});

describe('Android drawer transition ownership', () => {
  it('selects the target from displayed velocity and limits transferred extremes once', () => {
    const interaction = source('RNSideDrawerInteraction.kt');
    const root = source('RNSideDrawerView.kt');
    const release = between(root, 'private fun startReleaseTransition(', 'private fun startTransition(');

    expect(release).toContain('displayedVelocity * interaction.releaseVelocityTransfer');
    expect(release).toContain('limitSideDrawerReleaseVelocity(');
    expect(release).toContain('interaction.spring');
    expect(release).toContain('RELEASE_VELOCITY_LIMIT_DISTANCE_DP * resources.displayMetrics.density');
    expect(release.indexOf('projectedReleasePosition')).toBeLessThan(release.indexOf('limitSideDrawerReleaseVelocity'));
    expect(release).not.toContain('overdrag');
    expect(release).toContain('startTransition(nextOpen, SettlingSource.Release, true, initialVelocity, interaction)');
    expect(interaction).toContain('limitDistance / spring.peakDisplacementPerVelocity');
    expect(interaction).toContain('sinh(asinh(scaledSquare) / 3.0)');
    expect(root.match(/limitSideDrawerReleaseVelocity/g)).toHaveLength(1);
    expect(root).not.toContain('SideDrawerTrajectory');
  });

  it('interrupts only after horizontal intent at the last choreographer-owned frame', () => {
    const root = source('RNSideDrawerView.kt');
    const dispatch = between(root, 'override fun dispatchTouchEvent(', 'override fun requestDisallowInterceptTouchEvent(');
    const intercept = between(root, 'override fun onInterceptTouchEvent(', 'override fun onTouchEvent(');
    const begin = between(root, 'private fun beginDragging(', 'private fun clearTouchTracking(');
    const direction = between(root, 'private fun canMoveInDirection(', 'private fun setUnconstrainedDragPosition(');
    const transition = between(root, 'private fun startTransition(', 'private fun startTransitionAnimation(');

    expect(root).not.toContain('transitionPausedForTouch');
    expect(root).not.toContain('pauseTransitionForTouch');
    expect(root).not.toContain('resumePausedTransition');
    expect(dispatch).not.toContain('stopTransitionAnimation()');
    expect(intercept).toContain('abs(deltaX) > touchSlop && abs(deltaX) > abs(deltaY)');
    expect(intercept).toContain('if (drawerCanMove && horizontalIntent)');
    expect(intercept).toContain('beginDragging(event.getX(pointerIndex))');
    expect(begin).toContain('stopTransitionAnimation()');
    expect(begin).not.toContain('synchronizeTransition()');
    expect(begin).not.toContain('updateTransitionFrame(');
    expect(direction).toContain('return if (targetOpen) revealDelta < 0f else revealDelta > 0f');
    expect(transition).toContain('revealPx == target && resolvedInitialVelocity == 0.0');
  });

  it('preserves the complete settling state across width changes and completes by displacement bound', () => {
    const interaction = source('RNSideDrawerInteraction.kt');
    const root = source('RNSideDrawerView.kt');
    const layout = between(root, 'override fun onLayout(', 'override fun onInterceptTouchEvent(');
    const frame = between(root, 'private fun updateTransitionFrame(', 'private fun projectedReleasePosition(');

    expect(layout).toContain('remapSideDrawerState(');
    expect(layout).toContain('transitionVelocityPxPerSecond');
    expect(layout).toContain('resumedTransitionState?.velocity');
    expect(frame).toContain('sideDrawerSpringDisplacementBound(');
    expect(frame).toContain('TRANSITION_COMPLETION_DISTANCE_DP * resources.displayMetrics.density');
    expect(frame).toContain('if (!displacement.isFinite() || !velocity.isFinite())');
    expect(root).not.toContain('TRANSITION_VELOCITY_EPSILON_PX_PER_SECOND');
    expect(interaction).not.toContain('MINIMUM_SIDE_DRAWER_DOMINANT_DECAY_RATE');
  });

  it('derives each immutable configured interaction once', () => {
    const interaction = source('RNSideDrawerInteraction.kt');
    const root = source('RNSideDrawerView.kt');
    const properties = between(root, '// Properties', 'var contentBorderColor');

    expect(interaction).toContain('internal data class SideDrawerInteraction(');
    expect(interaction).toContain('val spring = resolveSideDrawerSpring(springMass, springStiffness, springDamping)');
    expect(root).toContain('private var configuredInteraction = defaultSideDrawerInteraction(defaultOverdragPx())');
    expect(root).toContain('private var activeInteraction = configuredInteraction');
    expect(root).not.toContain('resolveSideDrawerInteraction(');
    expect(properties).toContain('configuredInteraction.copy(springMass = resolved)');
    expect(properties).toContain('configuredInteraction.copy(springStiffness = resolved)');
    expect(properties).toContain('configuredInteraction.copy(springDamping = resolved)');
    expect(properties).not.toContain('resolveSideDrawerSpring');
  });
});
