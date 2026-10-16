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

const transitionAnimatorImplementation =
  '- (void)scheduleTransitionAnimatorToPosition:(CGFloat)targetPosition\n                             fromStateAtTime:(CFTimeInterval)stateTime\n{';
const prepareTransitionImplementation =
  '- (BOOL)prepareTransitionWithTargetOpen:(BOOL)targetOpen\n                             fromReveal:(CGFloat)reveal\n                        initialVelocity:(CGFloat)initialVelocity\n{';

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

  it('dismisses content editing only after an opening action is accepted', () => {
    const root = source('RNSideDrawerView.mm');
    const command = between(
      root,
      '- (void)setOpen:(BOOL)open animated:(BOOL)animated source:(RNSideDrawerSettlingSource)source\n{',
      '- (void)startTransitionWithTargetOpen:'
    );
    const drag = between(root, '- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView\n{', '- (void)scrollViewDidScroll:');
    const sameStateGuard = 'if ((_phase == RNSideDrawerPhaseOpen && open) || (_phase == RNSideDrawerPhaseClosed && !open)) return;';

    expect(command).toContain('if (open) [_contentView endEditing:YES]');
    expect(command.indexOf(sameStateGuard)).toBeLessThan(command.lastIndexOf('[_contentView endEditing:YES]'));
    expect(drag).toContain('if (!interruptedTargetOpen) [_contentView endEditing:YES]');
    expect(root.match(/endEditing:YES/g)).toHaveLength(3);
    expect(root).not.toContain('becomeFirstResponder');
  });
});

describe('iOS drawer transition ownership', () => {
  it('selects the target from displayed velocity and limits transferred extremes once', () => {
    const interaction = source('RNSideDrawerInteraction.mm');
    const root = source('RNSideDrawerView.mm');
    const release = between(root, '- (void)commitCurrentDragRelease\n{', '- (void)commitCancelledDrag');
    const animator = between(root, transitionAnimatorImplementation, prepareTransitionImplementation);

    expect(release).toContain('revealVelocity * _activeInteraction.releaseVelocityTransfer');
    expect(release).toContain('_releaseRevealVelocity = rnsidedrawer::limitReleaseVelocity(');
    expect(release).toContain('_activeInteraction.spring');
    expect(release).toContain('RNSideDrawerReleaseVelocityLimitDistance');
    expect(release.indexOf('releaseShouldOpen')).toBeLessThan(release.indexOf('limitReleaseVelocity'));
    expect(release).not.toContain('overdrag');
    expect(animator).toContain('_transitionVelocity / (targetPosition - _reveal)');
    expect(interaction).toContain('limitDistance / spring.peakDisplacementPerVelocity');
    expect(interaction).toContain('std::sinh(std::asinh(scaledSquare) / 3)');
    expect(root.match(/limitReleaseVelocity/g)).toHaveLength(1);
    expect(root).not.toContain('CAKeyframeAnimation');
    expect(root).not.toContain('RNSideDrawerResolveSpringElapsed');
    expect(root).not.toContain('_transitionClock');
  });

  it('takes drag ownership at pan intent and keeps native settling time-aligned', () => {
    const root = source('RNSideDrawerView.mm');
    const start = between(root, transitionAnimatorImplementation, prepareTransitionImplementation);
    const prepared = between(root, '- (void)startPreparedTransition\n{', '- (void)scheduleTransitionAnimatorToPosition:');
    const stop = between(root, '- (CGFloat)stopTransitionAtCurrentPosition\n{', '- (void)handleContactBegin');
    const clock = between(root, '- (BOOL)alignTransitionStateTimeWithAnimator\n{', '- (void)startPresentationDisplayLink');
    const refresh = between(root, '- (void)refreshPresentationDisplayLink\n{', '- (void)handlePresentationDisplayLink:');
    const contact = between(root, '- (void)handleContactBegin\n{', '- (void)completeTransitionWithDrawerOpen:');
    const acceptance = between(root, '- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView\n{', '- (void)scrollViewDidScroll:');
    const displayLink = between(root, '- (void)handlePresentationDisplayLink:(CADisplayLink *)displayLink\n{', '#pragma mark - Events');
    const observed = between(displayLink, 'CGFloat reveal = [self presentedReveal];', '[self publishProgressForReveal:reveal];');
    const prepare = between(root, prepareTransitionImplementation, '- (CGFloat)stopTransitionAtCurrentPosition');

    expect(start).toContain('UIViewPropertyAnimator');
    expect(start).toContain('[strongSelf positionContentForReveal:targetPosition]');
    expect(start).toContain('CFTimeInterval currentTime = CACurrentMediaTime()');
    expect(start).toContain('CFTimeInterval delay = MAX(0, stateTime - currentTime)');
    expect(start).toContain('[animator startAnimationAfterDelay:delay]');
    expect(root).toContain('CGFloat reveal = _transitionActive ? [self presentedReveal] : _reveal');
    expect(contact).not.toContain('stopTransitionAtCurrentPosition');
    expect(acceptance).toContain('if (_transitionActive) [self stopTransitionAtCurrentPosition]');
    expect(acceptance).toContain('_phase = RNSideDrawerPhaseDragging');
    expect(acceptance).toContain('_activeInteraction = rnsidedrawer::resolveInteraction(_configuredInteraction)');
    expect(stop).toContain('[_transitionAnimator stopAnimation:YES]');
    expect(stop).toContain('CGFloat presentedReveal = [self presentedReveal]');
    expect(stop).toContain('_reveal = presentedReveal');
    expect(stop).toContain('[self alignTransitionStateTimeWithAnimator]');
    expect(stop.indexOf('[self presentedReveal]')).toBeLessThan(stop.indexOf('stopAnimation:YES'));
    expect(stop).toContain('[self applyPresentationAtProgress:[self revealProgress]]');
    expect(displayLink).not.toContain('pauseAnimation');
    expect(displayLink).not.toContain('if (_scrollView.tracking) return;');
    expect(displayLink.match(/applyPresentationAtProgress/g)).toHaveLength(1);
    expect(observed).not.toContain('positionContentForReveal');
    expect(observed).not.toContain('applyPresentationAtProgress');
    expect(observed).toContain('BOOL transitionTimeAligned = [self alignTransitionStateTimeWithAnimator]');
    expect(observed).toContain('if (transitionTimeAligned)');
    expect(observed).toContain('displayLink.targetTimestamp - _transitionStateTime');
    expect(observed).toContain('applyMotionAtProgress:RNSideDrawerClamp(motionReveal');
    expect(root).toContain('[screen displayLinkWithTarget:self selector:@selector(handlePresentationDisplayLink:)]');
    expect(root).toContain('CAFrameRateRangeMake(frameRate, frameRate, frameRate)');
    expect(refresh).toContain('_transitionAnimator == nil || _progressEventsEnabled || _motion.hasInterpolations()');
    expect(refresh).not.toContain('_transitionTimeAlignmentPending');
    expect(prepare).toContain('reveal == targetPosition && resolvedVelocity == 0');
    expect(prepared).toContain('[self refreshPresentationDisplayLink]');
    expect(prepared).not.toContain('UIViewPropertyAnimator');
    expect(prepared).not.toContain('startAnimation');
    expect(displayLink).toContain('if (_transitionAnimator == nil)');
    expect(displayLink).toContain('[self advanceTransitionStateToTime:displayLink.targetTimestamp]');
    expect(displayLink).toContain('if (_reveal == target && _transitionVelocity == 0)');
    expect(displayLink).toContain('if (!isfinite(_transitionVelocity / (target - _reveal))) return;');
    expect(displayLink.indexOf('if (_reveal == target && _transitionVelocity == 0)')).toBeLessThan(
      displayLink.indexOf('[self scheduleTransitionAnimatorToPosition:target fromStateAtTime:_transitionStateTime]')
    );
    expect(displayLink).toContain('[self scheduleTransitionAnimatorToPosition:target fromStateAtTime:_transitionStateTime]');
    expect(clock).toContain('_transitionAnimator.fractionComplete * _transitionAnimator.duration');
    expect(clock).toContain('_transitionStateTime = CACurrentMediaTime() - animatorElapsedTime');
    expect(clock).not.toContain('presentedReveal');
    expect(clock).not.toContain('evaluateSpring');
  });

  it('accepts pans against the target while settling', () => {
    const root = source('RNSideDrawerView.mm');
    const acceptance = between(root, '- (BOOL)canBeginPanWithVelocity:(CGPoint)velocity\n{', '- (void)scrollViewWillBeginDragging:');

    expect(acceptance).toContain('return _targetOpen ? revealVelocity < 0 : revealVelocity > 0');
  });

  it('remaps settling position and velocity together when drawer width changes', () => {
    const root = source('RNSideDrawerView.mm');
    const layout = between(root, '- (void)layoutSubviews\n{', '- (void)didMoveToWindow');

    expect(layout).toContain('rnsidedrawer::remapStateForWidthChange(');
    expect(layout).toContain('previousReveal');
    expect(layout).toContain('resumeVelocity');
    expect(layout).toContain('_reveal = resumedTransitionState.position');
    expect(layout).toContain('initialVelocity:resumedTransitionState.velocity');
  });

  it('keeps the rendered and analytical spring identical in every supported damping regime', () => {
    const interaction = source('RNSideDrawerInteraction.mm');
    const root = source('RNSideDrawerView.mm');
    const animator = between(root, transitionAnimatorImplementation, prepareTransitionImplementation);
    const observer = between(root, '#pragma mark - Settling observation', '#pragma mark - Events');

    expect(animator).toContain('initWithDuration:(2 * M_PI / naturalFrequency)');
    expect(animator).toContain('bounce:(naturalFrequency / spring.dampingRate - 1)');
    expect(animator).toContain('initWithMass:spring.mass');
    expect(root).toContain('RNSideDrawerSpringForCurrentOS');
    expect(interaction).toContain('Spring criticallyDampedSpring');
    expect(observer).toContain('evaluateSpring(_transitionSpring');
    expect(observer).not.toContain('evaluateSpring(_activeInteraction.spring');
  });
});
