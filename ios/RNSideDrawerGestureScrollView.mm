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

void cancelTouchedHorizontalScrollPans(UIView *touchedView, UIScrollView *drawerScrollView)
{
  for (UIView *candidate = touchedView;
       candidate != nil && candidate != drawerScrollView;
       candidate = candidate.superview) {
    if (![candidate isKindOfClass:UIScrollView.class]) continue;

    UIScrollView *scrollView = (UIScrollView *)candidate;
    CGFloat minimumOffset;
    CGFloat maximumOffset;
    if (!horizontalScrollRange(scrollView, minimumOffset, maximumOffset)) continue;

    scrollView.panGestureRecognizer.enabled = NO;
    scrollView.panGestureRecognizer.enabled = YES;
  }
}

} // namespace

@implementation RNSideDrawerGestureScrollView {
  __weak UIView *_touchedView;
  __weak UIGestureRecognizer *_reactTouchHandler;
}

- (BOOL)touchesShouldBegin:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event inContentView:(UIView *)view
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
  if (gestureRecognizer != self.panGestureRecognizer || self.canBeginDrawerPan == nil) {
    return [super gestureRecognizerShouldBegin:gestureRecognizer];
  }

  const BOOL drawerCanMove = self.canBeginDrawerPan([self.panGestureRecognizer velocityInView:self]);
  const BOOL descendantCanScroll = drawerCanMove &&
      touchedDescendantCanScrollHorizontally(_touchedView, self, self.panGestureRecognizer);
  if (drawerCanMove && !descendantCanScroll) cancelTouchedHorizontalScrollPans(_touchedView, self);

  _touchedView = nil;
  const BOOL accepted = drawerCanMove && !descendantCanScroll;
  if (!accepted) _reactTouchHandler = nil;
  return accepted;
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
