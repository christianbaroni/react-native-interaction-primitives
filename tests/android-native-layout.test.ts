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
});

describe('Android drawer transition ownership', () => {
  it('hands finite release velocity directly to the spring', () => {
    const interaction = source('RNSideDrawerInteraction.kt');
    const root = source('RNSideDrawerView.kt');
    const release = between(root, 'private fun startReleaseTransition(', 'private fun startTransition(');

    expect(release).toContain('presentedVelocity * interaction.releaseVelocityTransfer');
    expect(release).toContain('if (transferredVelocity.isFinite()) transferredVelocity else 0.0');
    expect(release).not.toContain('overdrag');
    expect(release).toContain('startTransition(nextOpen, SettlingSource.Release, true, initialVelocity, interaction)');
    expect(interaction).not.toContain('limitSideDrawerReleaseVelocity');
    expect(interaction).not.toContain('maximumOutwardDistance');
  });

  it('keeps touch pauses on the last choreographer-owned frame', () => {
    const root = source('RNSideDrawerView.kt');
    const pause = between(root, 'private fun pauseTransitionForTouch() {', 'private fun resumePausedTransition()');

    expect(pause).toContain('stopTransitionAnimation()');
    expect(pause).toContain('transitionPausedForTouch = true');
    expect(pause).not.toContain('synchronizeTransition()');
    expect(pause).not.toContain('updateTransitionFrame(');
  });
});
