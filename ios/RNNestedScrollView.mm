#import "RNNestedScrollView.h"

#import <React/RCTSurfaceTouchHandler.h>
#import <React/RCTTouchHandler.h>

namespace {

CGFloat axisValue(CGPoint point, RNScrollAxis axis)
{
  return axis == RNScrollAxisHorizontal ? point.x : point.y;
}

CGFloat contentOffset(UIScrollView *scrollView, RNScrollAxis axis)
{
  return axis == RNScrollAxisHorizontal ? scrollView.contentOffset.x : scrollView.contentOffset.y;
}

bool scrollRange(
    UIScrollView *scrollView,
    RNScrollAxis axis,
    CGFloat &minimumOffset,
    CGFloat &maximumOffset)
{
  if (!scrollView.scrollEnabled || !scrollView.panGestureRecognizer.enabled) return false;

  const UIEdgeInsets inset = scrollView.adjustedContentInset;
  if (axis == RNScrollAxisHorizontal) {
    minimumOffset = -inset.left;
    maximumOffset = MAX(
        minimumOffset,
        scrollView.contentSize.width - scrollView.bounds.size.width + inset.right);
  } else {
    minimumOffset = -inset.top;
    maximumOffset = MAX(
        minimumOffset,
        scrollView.contentSize.height - scrollView.bounds.size.height + inset.bottom);
  }
  return maximumOffset > minimumOffset;
}

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

bool touchedDescendantCanScroll(
    UIView *touchedView,
    RNNestedScrollView *container,
    UIPanGestureRecognizer *containerPan)
{
  for (UIView *candidate = touchedView;
       candidate != nil && candidate != container;
       candidate = candidate.superview) {
    if (![candidate isKindOfClass:UIScrollView.class]) continue;

    UIScrollView *scrollView = (UIScrollView *)candidate;
    CGFloat minimumOffset;
    CGFloat maximumOffset;
    if (!scrollRange(scrollView, container.scrollAxis, minimumOffset, maximumOffset)) continue;

    const CGFloat fingerVelocity = axisValue([containerPan velocityInView:scrollView], container.scrollAxis);
    const CGFloat offset = contentOffset(scrollView, container.scrollAxis);
    if ((fingerVelocity > 0 && offset > minimumOffset) ||
        (fingerVelocity < 0 && offset < maximumOffset)) {
      return true;
    }
  }
  return false;
}

bool isDescendantScrollViewPan(UIGestureRecognizer *gestureRecognizer, RNNestedScrollView *container)
{
  if (![gestureRecognizer.view isKindOfClass:UIScrollView.class]) return false;

  UIScrollView *scrollView = (UIScrollView *)gestureRecognizer.view;
  return scrollView != container && gestureRecognizer == scrollView.panGestureRecognizer &&
      [scrollView isDescendantOfView:container];
}

void cancelTouchedScrollViewPans(UIView *touchedView, RNNestedScrollView *container)
{
  for (UIView *candidate = touchedView;
       candidate != nil && candidate != container;
       candidate = candidate.superview) {
    if (![candidate isKindOfClass:UIScrollView.class]) continue;

    UIScrollView *scrollView = (UIScrollView *)candidate;
    if (!scrollView.scrollEnabled || !scrollView.panGestureRecognizer.enabled) continue;

    scrollView.panGestureRecognizer.enabled = NO;
    scrollView.panGestureRecognizer.enabled = YES;
  }
}

} // namespace

@implementation RNNestedScrollView {
  __weak UIView *_touchedView;
  __weak UIGestureRecognizer *_reactTouchHandler;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event
{
  if ([super pointInside:point withEvent:event]) return YES;
  UIView *interactionBoundsView = self.interactionBoundsView;
  if (interactionBoundsView == nil) return NO;
  CGPoint interactionPoint = [interactionBoundsView convertPoint:point fromView:self];
  return [interactionBoundsView pointInside:interactionPoint withEvent:event];
}

- (BOOL)touchesShouldBegin:(NSSet<UITouch *> *)touches
                 withEvent:(UIEvent *)event
             inContentView:(UIView *)view
{
  _touchedView = view;
  _reactTouchHandler = findReactTouchHandler(view);
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
  if (gestureRecognizer != self.panGestureRecognizer || self.canBeginPan == nil) {
    return [super gestureRecognizerShouldBegin:gestureRecognizer];
  }

  const BOOL containerCanScroll = self.canBeginPan([self.panGestureRecognizer velocityInView:self]);
  const BOOL descendantCanScroll = containerCanScroll &&
      touchedDescendantCanScroll(_touchedView, self, self.panGestureRecognizer);
  if (containerCanScroll && !descendantCanScroll) cancelTouchedScrollViewPans(_touchedView, self);

  _touchedView = nil;
  const BOOL accepted = containerCanScroll && !descendantCanScroll;
  if (!accepted) _reactTouchHandler = nil;
  return accepted;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
  // A decelerating descendant can otherwise prevent the container before its
  // direction and scroll-range decision runs.
  if (gestureRecognizer == self.panGestureRecognizer) {
    return isDescendantScrollViewPan(otherGestureRecognizer, self);
  }
  if (otherGestureRecognizer == self.panGestureRecognizer) {
    return isDescendantScrollViewPan(gestureRecognizer, self);
  }
  return NO;
}

- (void)cancelReactTouchesForActivePan
{
  UIGestureRecognizer *touchHandler = _reactTouchHandler;
  _reactTouchHandler = nil;
  if (!touchHandler.enabled) return;

  if ([touchHandler isKindOfClass:RCTTouchHandler.class]) {
    [(RCTTouchHandler *)touchHandler cancel];
  } else {
    touchHandler.enabled = NO;
    touchHandler.enabled = YES;
  }
}

@end
