#import "RNPagerScrollView.h"

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIGestureRecognizerSubclass.h>
#import <math.h>

namespace {

bool scrollRange(
    UIScrollView *scrollView,
    RNPagerOrientation orientation,
    CGFloat &minimumOffset,
    CGFloat &maximumOffset)
{
  if (!scrollView.scrollEnabled || !scrollView.panGestureRecognizer.enabled) return false;

  const UIEdgeInsets inset = scrollView.adjustedContentInset;

  if (orientation == RNPagerOrientationHorizontal) {
    minimumOffset = -inset.left;
    maximumOffset = MAX(minimumOffset, scrollView.contentSize.width - scrollView.bounds.size.width + inset.right);
  } else {
    minimumOffset = -inset.top;
    maximumOffset = MAX(minimumOffset, scrollView.contentSize.height - scrollView.bounds.size.height + inset.bottom);
  }

  const BOOL alwaysBouncesOnAxis = orientation == RNPagerOrientationHorizontal
      ? scrollView.alwaysBounceHorizontal
      : scrollView.alwaysBounceVertical;

  return maximumOffset > minimumOffset || (scrollView.bounces && alwaysBouncesOnAxis);
}

CGFloat axisValue(CGPoint point, RNPagerOrientation orientation)
{
  return orientation == RNPagerOrientationHorizontal ? point.x : point.y;
}

CGFloat scrollOffset(UIScrollView *scrollView, RNPagerOrientation orientation)
{
  return orientation == RNPagerOrientationHorizontal ? scrollView.contentOffset.x : scrollView.contentOffset.y;
}

bool touchedChainContainsScrollView(UIView *touchedView, UIScrollView *pagerScrollView)
{
  for (UIView *candidate = touchedView;
       candidate != nil && candidate != pagerScrollView;
       candidate = candidate.superview) {
    if ([candidate isKindOfClass:UIScrollView.class]) return true;
  }
  return false;
}

bool touchedScrollViewCanConsumePan(
    UIView *touchedView,
    UIScrollView *pagerScrollView,
    RNPagerOrientation orientation,
    CGFloat fingerVelocity)
{
  for (UIView *candidate = touchedView;
       candidate != nil && candidate != pagerScrollView;
       candidate = candidate.superview) {
    if (![candidate isKindOfClass:UIScrollView.class]) continue;

    UIScrollView *scrollView = (UIScrollView *)candidate;
    CGFloat minimumOffset;
    CGFloat maximumOffset;
    if (!scrollRange(scrollView, orientation, minimumOffset, maximumOffset)) continue;

    const CGFloat offset = scrollOffset(scrollView, orientation);
    if ((fingerVelocity > 0 && offset > minimumOffset) ||
        (fingerVelocity < 0 && offset < maximumOffset)) {
      return true;
    }
  }
  return false;
}

bool isTouchedScrollViewPan(
    UIGestureRecognizer *gestureRecognizer,
    UIView *touchedView,
    UIScrollView *pagerScrollView,
    RNPagerOrientation orientation)
{
  if (![gestureRecognizer.view isKindOfClass:UIScrollView.class]) return false;

  UIScrollView *scrollView = (UIScrollView *)gestureRecognizer.view;
  if (scrollView == pagerScrollView || gestureRecognizer != scrollView.panGestureRecognizer) return false;

  CGFloat minimumOffset;
  CGFloat maximumOffset;
  if (!scrollRange(scrollView, orientation, minimumOffset, maximumOffset)) return false;

  for (UIView *candidate = touchedView;
       candidate != nil && candidate != pagerScrollView;
       candidate = candidate.superview) {
    if (candidate == scrollView) return true;
  }
  return false;
}

CGPoint boundedContentOffset(UIScrollView *scrollView)
{
  const UIEdgeInsets inset = scrollView.adjustedContentInset;
  const CGFloat minimumX = -inset.left;
  const CGFloat maximumX = MAX(
      minimumX,
      scrollView.contentSize.width - scrollView.bounds.size.width + inset.right);
  const CGFloat minimumY = -inset.top;
  const CGFloat maximumY = MAX(
      minimumY,
      scrollView.contentSize.height - scrollView.bounds.size.height + inset.bottom);
  return CGPointMake(
      MIN(maximumX, MAX(minimumX, scrollView.contentOffset.x)),
      MIN(maximumY, MAX(minimumY, scrollView.contentOffset.y)));
}

void stopScrollMotion(UIScrollView *scrollView)
{
  if (!scrollView.scrollEnabled) return;

  if (@available(iOS 17.4, *)) {
    [scrollView stopScrollingAndZooming];
    return;
  }

  const CGPoint stoppedOffset = boundedContentOffset(scrollView);
  const BOOL panWasEnabled = scrollView.panGestureRecognizer.enabled;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  scrollView.scrollEnabled = NO;
  scrollView.scrollEnabled = YES;
  scrollView.panGestureRecognizer.enabled = panWasEnabled;
  scrollView.contentOffset = stoppedOffset;
  [CATransaction commit];
}

} // namespace

@class RNPagerScrollView;

@interface RNPagerContactObserver : UIGestureRecognizer
@property (nonatomic, weak) RNPagerScrollView *scrollView;
@property (nonatomic, assign, readonly) BOOL hasActiveTouches;

- (void)completeTouches:(NSSet<UITouch *> *)touches;
@end

@interface RNPagerScrollView ()
- (void)captureTouchedScrollViewsFromView:(UIView *)view;
- (void)clearTouchedScrollViews;
- (void)beginNextContact;
- (void)completeContact;
- (void)admitPagerGesture;
- (void)stopCapturedScrollViews;
- (void)yieldToDescendant;
@end

@implementation RNPagerContactObserver {
  NSUInteger _activeTouchCount;
}

- (BOOL)hasActiveTouches
{
  return _activeTouchCount != 0;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
  [super touchesBegan:touches withEvent:event];
  _activeTouchCount += touches.count;
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
  [super touchesEnded:touches withEvent:event];
  [self completeTouches:touches];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
  [super touchesCancelled:touches withEvent:event];
  [self completeTouches:touches];
}

- (void)reset
{
  [super reset];
  if (_activeTouchCount == 0) return;

  _activeTouchCount = 0;
  [self.scrollView completeContact];
}

- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)preventedGestureRecognizer
{
  (void)preventedGestureRecognizer;
  return NO;
}

- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)preventingGestureRecognizer
{
  (void)preventingGestureRecognizer;
  return NO;
}

- (void)completeTouches:(NSSet<UITouch *> *)touches
{
  _activeTouchCount -= MIN(_activeTouchCount, touches.count);
  if (_activeTouchCount != 0) return;

  [self.scrollView completeContact];
  self.state = UIGestureRecognizerStateFailed;
}

@end

@implementation RNPagerScrollView {
  __weak UIView *_interactionBoundsView;
  __weak UIView *_touchedPage;
  __weak UIView *_touchedView;
  NSPointerArray *_touchedScrollViews;
  RNPagerContactObserver *_contactObserver;
  BOOL _descendantOwnsInteraction;
  BOOL _pagerScrollEnabled;
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if ((self = [super initWithFrame:frame])) {
    _pagerScrollEnabled = YES;
    _touchedScrollViews = [NSPointerArray weakObjectsPointerArray];
    _contactObserver = [RNPagerContactObserver new];
    _contactObserver.scrollView = self;
    _contactObserver.cancelsTouchesInView = NO;
    _contactObserver.delaysTouchesBegan = NO;
    _contactObserver.delaysTouchesEnded = NO;
    _contactObserver.requiresExclusiveTouchType = NO;
  }
  return self;
}

- (void)dealloc
{
  [_interactionBoundsView removeGestureRecognizer:_contactObserver];
  _contactObserver.scrollView = nil;
  _contactObserver.enabled = NO;
}

- (void)didMoveToWindow
{
  [super didMoveToWindow];
  if (self.window == nil) [self prepareForPagerMotion];
}

- (void)setInteractionBoundsView:(UIView *)interactionBoundsView
{
  if (_interactionBoundsView == interactionBoundsView) return;

  [_interactionBoundsView removeGestureRecognizer:_contactObserver];
  _interactionBoundsView = interactionBoundsView;
  [_interactionBoundsView addGestureRecognizer:_contactObserver];
}

- (UIView *)interactionBoundsView
{
  return _interactionBoundsView;
}

- (void)setPagerOrientation:(RNPagerOrientation)pagerOrientation
{
  if (_pagerOrientation == pagerOrientation) return;
  _pagerOrientation = pagerOrientation;
}

- (void)setPagerScrollEnabled:(BOOL)pagerScrollEnabled
{
  _pagerScrollEnabled = pagerScrollEnabled;
  [super setScrollEnabled:pagerScrollEnabled && !_descendantOwnsInteraction];
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event
{
  if ([super pointInside:point withEvent:event]) return YES;
  UIView *interactionBoundsView = self.interactionBoundsView;
  if (interactionBoundsView == nil) return NO;
  CGPoint interactionPoint = [interactionBoundsView convertPoint:point fromView:self];
  return [interactionBoundsView pointInside:interactionPoint withEvent:event];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
  if (_descendantOwnsInteraction && !_contactObserver.hasActiveTouches &&
      event != nil && event.type == UIEventTypeTouches) {
    [self beginNextContact];
  }
  return [super hitTest:point withEvent:event];
}

- (BOOL)touchesShouldBegin:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event inContentView:(UIView *)view
{
  if (_touchedView == nil) {
    _touchedView = view;
    [self captureTouchedScrollViewsFromView:view];
  }
  return [super touchesShouldBegin:touches withEvent:event inContentView:view];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
  if (gestureRecognizer != self.panGestureRecognizer) {
    return [super gestureRecognizerShouldBegin:gestureRecognizer];
  }

  if (!touchedChainContainsScrollView(_touchedView, self)) {
    [self admitPagerGesture];
    return [super gestureRecognizerShouldBegin:gestureRecognizer];
  }

  const CGPoint velocity = [self.panGestureRecognizer velocityInView:self];
  const CGFloat mainAxisVelocity = axisValue(velocity, self.pagerOrientation);
  const CGFloat crossAxisVelocity = self.pagerOrientation == RNPagerOrientationHorizontal
      ? velocity.y
      : velocity.x;

  if (fabs(mainAxisVelocity) <= fabs(crossAxisVelocity)) {
    [self yieldToDescendant];
    return NO;
  }

  if (touchedScrollViewCanConsumePan(
          _touchedView,
          self,
          self.pagerOrientation,
          mainAxisVelocity)) {
    [self yieldToDescendant];
    return NO;
  }

  [self admitPagerGesture];
  const BOOL pagerCanBegin = [super gestureRecognizerShouldBegin:gestureRecognizer];
  if (!pagerCanBegin) [self yieldToDescendant];
  return pagerCanBegin;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
  return gestureRecognizer == self.panGestureRecognizer &&
      isTouchedScrollViewPan(
      otherGestureRecognizer,
      _touchedView,
      self,
      self.pagerOrientation);
}

- (void)completeContact
{
  if (!_descendantOwnsInteraction) [self clearTouchedScrollViews];
}

- (void)admitPagerGesture
{
  _descendantOwnsInteraction = NO;
  [super setPagingEnabled:YES];
}

- (void)prepareForPagerMotion
{
  [super setScrollEnabled:NO];
  [self stopCapturedScrollViews];

  _contactObserver.enabled = NO;
  _contactObserver.enabled = YES;
  _descendantOwnsInteraction = NO;
  [self clearTouchedScrollViews];
  [super setPagingEnabled:YES];
  [super setScrollEnabled:_pagerScrollEnabled];
}

- (void)stopPagerScrollMotion
{
  [super setScrollEnabled:NO];
  [super setScrollEnabled:_pagerScrollEnabled && !_descendantOwnsInteraction];
}

- (void)willRemoveContentView:(UIView *)view
{
  if (_touchedPage == view || [_touchedPage isDescendantOfView:view]) {
    [self prepareForPagerMotion];
  }
}

- (void)captureTouchedScrollViewsFromView:(UIView *)view
{
  [_touchedScrollViews setCount:0];
  _touchedPage = nil;
  for (UIView *candidate = view;
       candidate != nil && candidate != self;
       candidate = candidate.superview) {
    if ([candidate isKindOfClass:UIScrollView.class]) {
      [_touchedScrollViews addPointer:(__bridge void *)candidate];
    }
    if (candidate.superview.superview == self) _touchedPage = candidate;
  }
}

- (void)clearTouchedScrollViews
{
  _touchedPage = nil;
  _touchedView = nil;
  [_touchedScrollViews setCount:0];
}

- (void)beginNextContact
{
  _descendantOwnsInteraction = NO;
  [self clearTouchedScrollViews];
  [super setScrollEnabled:_pagerScrollEnabled];
}

- (void)stopCapturedScrollViews
{
  UIView *touchedPage = _touchedPage;
  if (touchedPage == nil || ![touchedPage isDescendantOfView:self]) return;

  for (NSUInteger index = 0; index < _touchedScrollViews.count; index += 1) {
    UIScrollView *scrollView = (__bridge UIScrollView *)[_touchedScrollViews pointerAtIndex:index];
    if ([scrollView isDescendantOfView:touchedPage]) stopScrollMotion(scrollView);
  }
}

- (void)yieldToDescendant
{
  if (_descendantOwnsInteraction) return;

  _descendantOwnsInteraction = YES;
  [super setPagingEnabled:NO];
  [super setScrollEnabled:NO];
}

@end
