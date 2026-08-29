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

  it('derives scrim hit ownership from the drawer target, not visual progress', () => {
    const paperContent = source('RNSideDrawerContentView.mm');
    const fabricContent = source('RNSideDrawerViewManager.mm');
    const slots = source('RNSideDrawerSlots.h');
    const root = source('RNSideDrawerView.mm');
    const mount = between(root, '- (void)mountSlot:', '- (void)unmountSlot:');
    const presentation = between(
      root,
      '- (void)applyPresentationAtProgress:(CGFloat)progress\n{',
      '- (void)applyMotionAtProgress:(CGFloat)progress\n{'
    );
    const prepare = between(root, '- (void)prepareViewsForTransition\n{', '- (UIScreen *)currentScreen\n{');

    expect(slots).toContain('- (void)setDrawerScrimEnabled:(BOOL)enabled;');
    expect(paperContent).toContain('- (void)setDrawerScrimEnabled:(BOOL)enabled');
    expect(paperContent).toContain('_scrimView.userInteractionEnabled != enabled');
    expect(fabricContent).toContain('- (void)setDrawerScrimEnabled:(BOOL)enabled');
    expect(fabricContent).toContain('_scrimView.userInteractionEnabled != enabled');
    expect(mount).toContain('[_contentView setDrawerScrimEnabled:_targetOpen]');
    expect(presentation).toContain('[_contentView setDrawerScrimEnabled:_targetOpen]');
    expect(prepare).toContain('[_contentView setDrawerScrimEnabled:_targetOpen]');
    expect(paperContent + fabricContent + slots + root).not.toContain('setDrawerProgress');
  });
});

describe('iOS drawer transition ownership', () => {
  it('hands finite release velocity directly to the spring', () => {
    const interaction = source('RNSideDrawerInteraction.mm');
    const root = source('RNSideDrawerView.mm');
    const release = between(root, '- (void)commitCurrentDragRelease\n{', '- (void)commitCancelledDrag');
    const start = between(root, '- (void)startTransitionAnimator\n{', '- (BOOL)prepareTransitionWithTargetOpen:');

    expect(release).toContain('revealVelocity * _activeInteraction.releaseVelocityTransfer');
    expect(release).toContain('_releaseRevealVelocity = isfinite(transferredVelocity) ? transferredVelocity : 0');
    expect(release).not.toContain('overdrag');
    expect(start).toContain('_transitionVelocity / distance');
    expect(interaction).not.toContain('limitReleaseVelocity');
    expect(interaction).not.toContain('maximumOutwardDistance');
  });

  it('admits interruptions at pan intent and adopts a stable display-link frame', () => {
    const root = source('RNSideDrawerView.mm');
    const start = between(root, '- (void)startTransitionAnimator\n{', '- (BOOL)prepareTransitionWithTargetOpen:');
    const stop = between(root, '- (CGFloat)stopTransitionAtCurrentPosition\n{', '- (void)requestTransitionInterruption');
    const request = between(root, '- (void)requestTransitionInterruption\n{', '- (void)restoreTransitionLayerTiming');
    const restore = between(root, '- (void)restoreTransitionLayerTiming\n{', '- (void)handleContactBegin');
    const contact = between(root, '- (void)handleContactBegin\n{', '- (void)completeTransitionWithDrawerOpen:');
    const admission = between(root, '- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView\n{', '- (void)beginAdmittedDrag');
    const begin = between(root, '- (void)beginAdmittedDrag\n{', '- (void)scrollViewDidScroll:');
    const scroll = between(root, '- (void)scrollViewDidScroll:(UIScrollView *)scrollView\n{', '- (void)scrollViewWillEndDragging:');
    const willEnd = between(root, '- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView', '- (void)scrollViewDidEndDragging:');
    const didEnd = between(
      root,
      '- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate\n{',
      '- (void)scrollViewWillBeginDecelerating:'
    );
    const sample = between(root, '- (void)samplePresentedTransition:(CADisplayLink *)displayLink\n{', '#pragma mark - Events');

    expect(start).toContain('UIViewPropertyAnimator');
    expect(start).toContain('[strongSelf positionContentForReveal:targetPosition]');
    expect(root).toContain('CGFloat reveal = _transitionActive ? [self presentedReveal] : _reveal');
    expect(contact).not.toContain('requestTransitionInterruption');
    expect(contact).not.toContain('stopTransitionAtCurrentPosition');
    expect(admission).toContain('[self requestTransitionInterruption]');
    expect(admission).not.toContain('stopTransitionAtCurrentPosition');
    expect(admission).toContain('_admittedInteraction = rnsidedrawer::resolveInteraction(_configuredInteraction)');
    expect(begin).toContain('_activeInteraction = _admittedInteraction');
    expect(scroll).toContain('[self setScrollOffset:_interruptionScrollOffset]');
    expect(willEnd).toContain('if (_transitionInterruptionPending)');
    expect(willEnd).toContain('_deferredPanState = UIGestureRecognizerStateEnded');
    expect(willEnd).toContain('_deferredPanTranslation = [_scrollView.panGestureRecognizer translationInView:self].x');
    expect(willEnd).toContain('_deferredPanVelocity = [_scrollView.panGestureRecognizer velocityInView:self].x');
    expect(didEnd).toContain('if (_transitionInterruptionPending) {');
    expect(didEnd).toContain('_deferredPanState = UIGestureRecognizerStateCancelled');
    expect(stop).toContain('[_transitionAnimator stopAnimation:YES]');
    expect(stop).toContain('if (layerPaused) [self restoreTransitionLayerTiming]');
    expect(stop).toContain('[self applyPresentationAtProgress:[self revealProgress]]');
    expect(request).toContain('_transitionInterruptionPending = YES');
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
    expect(sample).toContain('if (layer.speed == 0 || _transitionAnimator == nil)');
    expect(sample).toContain('(void)[self stopTransitionAtCurrentPosition]');
    expect(sample).toContain('[self beginAdmittedDrag]');
    expect(sample).toContain('_deferredPanState == UIGestureRecognizerStatePossible');
    expect(sample).toContain('if (state == UIGestureRecognizerStateEnded)');
    expect(sample).toContain('[self commitCurrentDragRelease]');
    expect(sample).toContain('[self startCommittedRelease]');
    expect(sample).not.toContain('if (_scrollView.tracking) return;');
    expect(sample).not.toContain('positionContentForReveal');
    expect(sample).not.toContain('applyPresentationAtProgress');
    expect(root).toContain('[screen displayLinkWithTarget:self selector:@selector(samplePresentedTransition:)]');
    expect(root).toContain('CAFrameRateRangeMake(frameRate, frameRate, frameRate)');
  });
});
