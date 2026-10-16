#import "RNSideDrawerGestureScrollView.h"

#import <React/RCTSurfaceTouchHandler.h>
#import <React/RCTTouchHandler.h>

namespace {

UIGestureRecognizer *findReactTouchHandler(UIView *view)
{
  for (UIView *ancestor = view; ancestor != nil; ancestor = ancestor.superview) {
    for (UIGestureRecognizer *gestureRecognizer in ancestor.gestureRecognizers) {
      if ([gestureRecognizer isKindOfClass:RCTTouchHandler.class] ||
          [gestureRecognizer isKindOfClass:RCTSurfaceTouchHandler.class]) {
        return gestureRecognizer;
      }
    }
  }
  return nil;
}

bool horizontalScrollRange(UIScrollView *scrollView, CGFloat &minimumOffset, CGFloat &maximumOffset)
{
  if (!scrollView.scrollEnabled || !scrollView.panGestureRecognizer.enabled) return false;

  const UIEdgeInsets inset = scrollView.adjustedContentInset;
  minimumOffset = -inset.left;
  maximumOffset = MAX(minimumOffset, scrollView.contentSize.width - scrollView.bounds.size.width + inset.right);
  return maximumOffset > minimumOffset;
}

bool touchedDescendantCanScrollHorizontally(
    UIView *touchedView,
    UIScrollView *drawerScrollView,
    UIPanGestureRecognizer *drawerPanGestureRecognizer)
{
  for (UIView *candidate = touchedView;
       candidate != nil && candidate != drawerScrollView;
       candidate = candidate.superview) {
    if (![candidate isKindOfClass:UIScrollView.class]) continue;

    UIScrollView *scrollView = (UIScrollView *)candidate;
    CGFloat minimumOffset;
    CGFloat maximumOffset;
    if (!horizontalScrollRange(scrollView, minimumOffset, maximumOffset)) continue;

    const CGFloat velocity = [drawerPanGestureRecognizer velocityInView:scrollView].x;
    if ((velocity > 0 && scrollView.contentOffset.x > minimumOffset) ||
        (velocity < 0 && scrollView.contentOffset.x < maximumOffset)) {
      return true;
    }
  }
  return false;
}

bool isDescendantScrollViewPan(UIGestureRecognizer *gestureRecognizer, UIScrollView *drawerScrollView)
{
  if (![gestureRecognizer.view isKindOfClass:UIScrollView.class]) return false;

  UIScrollView *scrollView = (UIScrollView *)gestureRecognizer.view;
  return scrollView != drawerScrollView && gestureRecognizer == scrollView.panGestureRecognizer &&
      [scrollView isDescendantOfView:drawerScrollView];
}

void cancelTouchedScrollViewPans(UIView *touchedView, UIScrollView *drawerScrollView)
{
  for (UIView *candidate = touchedView;
       candidate != nil && candidate != drawerScrollView;
       candidate = candidate.superview) {
    if (![candidate isKindOfClass:UIScrollView.class]) continue;

    UIScrollView *scrollView = (UIScrollView *)candidate;
    if (!scrollView.scrollEnabled || !scrollView.panGestureRecognizer.enabled) continue;

    scrollView.panGestureRecognizer.enabled = NO;
    scrollView.panGestureRecognizer.enabled = YES;
  }
}

void cancelReactTouches(UIGestureRecognizer *touchHandler)
{
  if (!touchHandler.enabled) return;

  if ([touchHandler isKindOfClass:RCTTouchHandler.class]) {
    [(RCTTouchHandler *)touchHandler cancel];
  } else {
    touchHandler.enabled = NO;
    touchHandler.enabled = YES;
  }
}

} // namespace

@interface RNSideDrawerGestureScrollView () <UIGestureRecognizerDelegate>
@end

@implementation RNSideDrawerGestureScrollView {
  __weak UIView *_touchedView;
  UIPanGestureRecognizer *_verticalPanGestureRecognizer;
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if ((self = [super initWithFrame:frame])) {
    // The horizontal scroll pan can remain possible throughout a vertical drag.
    // Recognize vertical starts so UIKit rejects the drawer until the gesture ends.
    _verticalPanGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:nil action:nil];
    _verticalPanGestureRecognizer.delegate = self;
    _verticalPanGestureRecognizer.cancelsTouchesInView = NO;
    _verticalPanGestureRecognizer.delaysTouchesEnded = NO;
    _verticalPanGestureRecognizer.allowedScrollTypesMask = self.panGestureRecognizer.allowedScrollTypesMask;
    _verticalPanGestureRecognizer.allowedTouchTypes = self.panGestureRecognizer.allowedTouchTypes;
    _verticalPanGestureRecognizer.enabled = self.scrollEnabled;
    [self addGestureRecognizer:_verticalPanGestureRecognizer];
    [self.panGestureRecognizer requireGestureRecognizerToFail:_verticalPanGestureRecognizer];
  }
  return self;
}

- (void)setScrollEnabled:(BOOL)scrollEnabled
{
  [super setScrollEnabled:scrollEnabled];
  _verticalPanGestureRecognizer.enabled = self.scrollEnabled;
}

- (BOOL)touchesShouldBegin:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event inContentView:(UIView *)view
{
  _touchedView = view;
  if (self.didBeginContact != nil) self.didBeginContact();
  return [super touchesShouldBegin:touches withEvent:event inContentView:view];
}

- (BOOL)touchesShouldCancelInContentView:(UIView *)view
{
  (void)view;
  return YES;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
  if (gestureRecognizer == _verticalPanGestureRecognizer) {
    const CGPoint velocity = [_verticalPanGestureRecognizer velocityInView:self];
    return fabs(velocity.y) >= fabs(velocity.x);
  }

  if (gestureRecognizer != self.panGestureRecognizer || self.canBeginDrawerPan == nil) {
    return [super gestureRecognizerShouldBegin:gestureRecognizer];
  }

  const BOOL drawerCanMove = self.canBeginDrawerPan([self.panGestureRecognizer velocityInView:self]);
  const BOOL descendantCanScroll = drawerCanMove &&
      touchedDescendantCanScrollHorizontally(_touchedView, self, self.panGestureRecognizer);
  const BOOL accepted = drawerCanMove && !descendantCanScroll;

  if (!accepted) _touchedView = nil;
  return accepted;
}

- (void)cancelCompetingTouches
{
  cancelReactTouches(findReactTouchHandler(_touchedView != nil ? _touchedView : self));
  cancelTouchedScrollViewPans(_touchedView, self);
  _touchedView = nil;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
  if (gestureRecognizer == _verticalPanGestureRecognizer || otherGestureRecognizer == _verticalPanGestureRecognizer) {
    return gestureRecognizer != self.panGestureRecognizer && otherGestureRecognizer != self.panGestureRecognizer;
  }
  // A decelerating descendant can otherwise prevent the drawer before its direction gate runs.
  if (gestureRecognizer == self.panGestureRecognizer) {
    return isDescendantScrollViewPan(otherGestureRecognizer, self);
  }
  if (otherGestureRecognizer == self.panGestureRecognizer) {
    return isDescendantScrollViewPan(gestureRecognizer, self);
  }
  return NO;
}

@end
