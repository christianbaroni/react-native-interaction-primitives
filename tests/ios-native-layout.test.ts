import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const iosSource = resolve(process.cwd(), 'ios');

function source(filename: string): string {
  return readFileSync(resolve(iosSource, filename), 'utf8');
}

function between(value: string, start: string, end: string): string {
  const startIndex = value.indexOf(start);
  if (startIndex < 0) throw new Error(`Missing source boundary: ${start}`);
  const contentStart = startIndex + start.length;
  const endIndex = value.indexOf(end, contentStart);
  if (endIndex < 0) throw new Error(`Missing source boundary: ${end}`);
  return value.slice(contentStart, endIndex);
}

describe('iOS native view ownership', () => {
  it('clips transformed drawer content only at the drawer root', () => {
    const paperPanel = source('RNSideDrawerPanelView.mm');
    const fabricManager = source('RNSideDrawerViewManager.mm');
    const root = source('RNSideDrawerView.mm');

    expect(paperPanel).toContain('self.clipsToBounds = NO;');
    expect(fabricManager).toContain('self.clipsToBounds = NO;');
    expect(root).toContain('self.clipsToBounds = YES;');
  });
});

describe('iOS drawer transition ownership', () => {
  it('freezes the target frame, then restores ordinary layer timing', () => {
    const root = source('RNSideDrawerView.mm');
    const start = between(root, '- (void)startTransitionAnimator\n{', '- (BOOL)prepareTransitionWithTargetOpen:');
    const stop = between(root, '- (CGFloat)stopTransitionAtCurrentPosition\n{', '- (void)requestTransitionPause');
    const request = between(root, '- (void)requestTransitionPause\n{', '- (void)handleContactBegin');
    const restore = between(root, '- (void)restoreTransitionLayerTiming\n{', '- (void)handleContactBegin');
    const sample = between(root, '- (void)samplePresentedTransition:(CADisplayLink *)displayLink\n{', '#pragma mark - Events');

    expect(start).toContain('UIViewPropertyAnimator');
    expect(start).toContain('[strongSelf positionContentForReveal:targetPosition]');
    expect(stop).toContain('[_transitionAnimator stopAnimation:YES]');
    expect(stop).toContain('if (layerPaused) [self restoreTransitionLayerTiming]');
    expect(stop).toContain('[self applyPresentationAtProgress:[self revealProgress]]');
    expect(request).toContain('_transitionPauseRequested = YES');
    expect(request).toContain('[self startPresentationDisplayLink]');
    expect(request).not.toContain('pauseAnimation');
    expect(request).not.toContain('stopTransitionAtCurrentPosition');
    expect(request).not.toContain('stopAnimation');
    expect(request).not.toContain('presentedReveal');
    expect(request).not.toContain('applyPresentationAtProgress');
    expect(restore).toContain('layer.speed = 1');
    expect(restore).toContain('layer.timeOffset = 0');
    expect(restore).toContain('layer.beginTime = 0');
    expect(sample).not.toContain('pauseAnimation');
    expect(sample).toContain('[layer convertTime:displayLink.targetTimestamp fromLayer:nil]');
    expect(sample).toContain('layer.speed = 0');
    expect(sample).toContain('layer.timeOffset = pausedTime');
    expect(sample).toContain('if (layer.speed == 0)');
    expect(sample).toContain('_transitionActive = YES');
    expect(sample).toContain('_transitionPauseRequested = YES');
    expect(sample).toContain('if (_scrollView.tracking) return;');
    expect(sample).toContain('(void)[self stopTransitionAtCurrentPosition]');
    expect(sample).not.toContain('positionContentForReveal');
    expect(sample).not.toContain('applyPresentationAtProgress');
    expect(root).toContain('[screen displayLinkWithTarget:self selector:@selector(samplePresentedTransition:)]');
    expect(root).toContain('CAFrameRateRangeMake(frameRate, frameRate, frameRate)');
  });
});
