#import "RNSideDrawerContentView.h"
#import "RNSideDrawerView.h"
#import <React/RCTSurfaceTouchHandler.h>
#import <React/RCTTouchHandler.h>
#import <React/UIView+React.h>

#include <cassert>
#include <cmath>
#include <cstdio>

// These tests exercise UIKit and native drawer callbacks, not React touch dispatch.
@implementation RCTTouchHandler
- (void)cancel {}
@end

@implementation RCTSurfaceTouchHandler
@end

@interface RNSideDrawerView (Verification)
- (void)handleContactBegin;
@end

@interface CallbackVerificationDrawer : RNSideDrawerView
@property (nonatomic, assign) CGFloat panTranslation;
@end

@implementation CallbackVerificationDrawer
// Control gesture input while exercising the native callbacks and actual animator.
- (CGFloat)dragTranslation
{
  return self.panTranslation;
}
@end

static UIViewPropertyAnimator *waitForAnimation(RNSideDrawerView *drawer)
{
  UIView *pane = [drawer valueForKey:@"contentPresentationView"];
  UIViewPropertyAnimator *animator = nil;
  CFTimeInterval deadline = CACurrentMediaTime() + 2;
  do {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    animator = [drawer valueForKey:@"transitionAnimator"];
  } while ((animator.fractionComplete <= 0.01 || pane.layer.presentationLayer == nil) && CACurrentMediaTime() < deadline);
  assert(animator != nil && animator.fractionComplete > 0.01 && animator.fractionComplete < 1);
  assert(pane.layer.presentationLayer != nil);
  return animator;
}

static void verifyPendingPanCommand(RNSideDrawerView *drawer, bool frozen, bool commandOpen)
{
  [drawer closeAnimated:NO];
  [drawer openAnimated:YES];
  [CATransaction flush];
  waitForAnimation(drawer);

  UIScrollView *scroll = [drawer valueForKey:@"scrollView"];
  id<UIScrollViewDelegate> delegate = (id<UIScrollViewDelegate>)drawer;
  // Enter the accepted-pan boundary directly; the animator and display link are real.
  [delegate scrollViewWillBeginDragging:scroll];
  assert([[drawer valueForKey:@"transitionInterruptionPending"] boolValue]);
  UIView *pane = [drawer valueForKey:@"contentPresentationView"];
  if (frozen) {
    CFTimeInterval deadline = CACurrentMediaTime() + 2;
    do {
      [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    } while (pane.layer.speed != 0 && CACurrentMediaTime() < deadline);
    assert(pane.layer.speed == 0);
  }

  if (commandOpen) [drawer openAnimated:YES];
  else [drawer closeAnimated:YES];
  assert(![[drawer valueForKey:@"transitionInterruptionPending"] boolValue]);
  assert([[drawer valueForKey:@"suppressCurrentDragRelease"] boolValue]);
  assert(pane.layer.speed == 1);

  [scroll.panGestureRecognizer setTranslation:CGPointMake(commandOpen ? -200 : 200, 0) inView:drawer];
  CGPoint targetOffset = scroll.contentOffset;
  [delegate scrollViewWillEndDragging:scroll withVelocity:CGPointZero targetContentOffset:&targetOffset];
  [delegate scrollViewDidEndDragging:scroll willDecelerate:NO];
  assert([[drawer valueForKey:@"targetOpen"] boolValue] == commandOpen);
  [drawer closeAnimated:NO];
}

static void verifyContactDuringSettling(RNSideDrawerView *drawer, RNSideDrawerContentView *slot)
{
  [drawer openAnimated:NO];
  [drawer closeAnimated:YES];
  [CATransaction flush];
  UIViewPropertyAnimator *animator = waitForAnimation(drawer);
  UIView *pane = [drawer valueForKey:@"contentPresentationView"];
  assert([drawer hitTest:CGPointMake(95, 50) withEvent:nil] == slot.subviews.firstObject);
  CGFloat beforeContact = pane.layer.presentationLayer.position.x;
  [drawer handleContactBegin];
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.04]];
  assert([drawer valueForKey:@"transitionAnimator"] == animator);
  assert(pane.layer.speed == 1);
  assert(![[drawer valueForKey:@"transitionInterruptionPending"] boolValue]);
  assert(pane.layer.presentationLayer.position.x < beforeContact);

  [drawer closeAnimated:NO];
  [drawer openAnimated:YES];
  [CATransaction flush];
  waitForAnimation(drawer);
  assert(slot.onScrimPress != nil);
  slot.onScrimPress();
  assert(![[drawer valueForKey:@"targetOpen"] boolValue]);
  [drawer closeAnimated:NO];
}

static void verifyScrim(bool initiallyOpen)
{
  RNSideDrawerView *drawer = [[RNSideDrawerView alloc] initWithFrame:CGRectMake(0, 0, 400, 800)];
  drawer.contentCornerRadius = 0;
  drawer.drawerWidth = 300;
  drawer.initialOpen = initiallyOpen;
  RNSideDrawerContentView *slot = [[RNSideDrawerContentView alloc] initWithFrame:drawer.bounds];
  UIView *content = [[UIView alloc] initWithFrame:slot.bounds];
  content.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [slot insertReactSubview:content atIndex:0];
  [slot didUpdateReactSubviews];
  [drawer mountSlot:slot atIndex:0];
  [drawer layoutIfNeeded];
  if (!initiallyOpen) [drawer openAnimated:NO];

  UIView *scrim = slot.subviews.lastObject;
  assert([drawer hitTest:CGPointMake(350, 400) withEvent:nil] == scrim);
  UIView *overlay = scrim.subviews.firstObject;
  assert(overlay != nil && !overlay.userInteractionEnabled);

  UIColor *dynamicColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
    return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? UIColor.whiteColor : UIColor.blackColor;
  }];
  for (UIColor *color in @[UIColor.clearColor, [UIColor.blueColor colorWithAlphaComponent:0.4], dynamicColor]) {
    [slot setDrawerOverlayColor:color];
    for (NSNumber *opacity in @[@0, @0.005, @0.02, @1, @-1, @2]) {
      [slot setDrawerOverlayOpacity:opacity.doubleValue];
      assert([drawer hitTest:CGPointMake(350, 400) withEvent:nil] == scrim);
      assert(scrim.alpha == 1);
      assert(std::abs(overlay.alpha - MIN(1, MAX(0, opacity.doubleValue))) < 1e-7);
      assert([overlay.backgroundColor isEqual:color]);
    }
  }

  drawer.frame = CGRectMake(0, 0, 500, 900);
  [drawer layoutIfNeeded];
  assert(CGRectEqualToRect(scrim.frame, slot.bounds));
  assert(CGRectEqualToRect(overlay.frame, scrim.bounds));
  assert([drawer hitTest:CGPointMake(450, 450) withEvent:nil] == scrim);

  [drawer closeAnimated:NO];
  for (NSNumber *opacity in @[@0, @1]) {
    [slot setDrawerOverlayOpacity:opacity.doubleValue];
    assert([drawer hitTest:CGPointMake(350, 400) withEvent:nil] == content);
  }
  [drawer prepareForRemoval];
}

static void verifyRootHitEligibility(RNSideDrawerView *drawer)
{
  CGPoint inside = CGPointMake(75, 50);
  assert([drawer hitTest:inside withEvent:nil] != nil);
  assert([drawer hitTest:CGPointMake(125, 50) withEvent:nil] == nil);
  drawer.userInteractionEnabled = NO;
  assert([drawer hitTest:inside withEvent:nil] == nil);
  drawer.userInteractionEnabled = YES;
  drawer.hidden = YES;
  assert([drawer hitTest:inside withEvent:nil] == nil);
  drawer.hidden = NO;
  for (NSNumber *alpha in @[@0, @0.005]) {
    drawer.alpha = alpha.doubleValue;
    assert([drawer hitTest:inside withEvent:nil] == nil);
  }
  drawer.alpha = 1;
}

static void verifyAnimatedInteractions()
{
  UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 200, 200)];
  UIViewController *controller = [[UIViewController alloc] init];
  window.rootViewController = controller;
  [window makeKeyAndVisible];
  RNSideDrawerView *drawer = [[RNSideDrawerView alloc] initWithFrame:CGRectMake(20, 20, 100, 100)];
  drawer.contentCornerRadius = 0;
  drawer.drawerWidth = 50;
  drawer.springMass = 1;
  drawer.springStiffness = 10;
  drawer.springDamping = 2;
  RNSideDrawerContentView *slot = [[RNSideDrawerContentView alloc] initWithFrame:drawer.bounds];
  UIView *content = [[UIView alloc] initWithFrame:slot.bounds];
  [slot insertReactSubview:content atIndex:0];
  [slot didUpdateReactSubviews];
  [drawer mountSlot:slot atIndex:0];
  [controller.view addSubview:drawer];
  [window layoutIfNeeded];
  verifyRootHitEligibility(drawer);

  [drawer openAnimated:YES];
  [CATransaction flush];
  waitForAnimation(drawer);
  verifyRootHitEligibility(drawer);
  assert([drawer hitTest:CGPointMake(95, 50) withEvent:nil] == slot.subviews.lastObject);

  verifyPendingPanCommand(drawer, false, false);
  verifyPendingPanCommand(drawer, false, true);
  verifyPendingPanCommand(drawer, true, false);
  verifyPendingPanCommand(drawer, true, true);
  verifyContactDuringSettling(drawer, slot);

  [drawer closeAnimated:NO];
  [drawer prepareForRemoval];
  [drawer removeFromSuperview];
  window.hidden = YES;
}

static void waitForSettle(RNSideDrawerView *drawer)
{
  [CATransaction flush];
  CFTimeInterval deadline = CACurrentMediaTime() + 2;
  while ([[drawer valueForKey:@"transitionActive"] boolValue] && CACurrentMediaTime() < deadline) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
  }
  assert(![[drawer valueForKey:@"transitionActive"] boolValue]);
}

static void endPan(CallbackVerificationDrawer *drawer, CGFloat translation, bool cancelled)
{
  UIScrollView *scroll = [drawer valueForKey:@"scrollView"];
  id<UIScrollViewDelegate> delegate = (id<UIScrollViewDelegate>)drawer;
  drawer.panTranslation = 0;
  [delegate scrollViewWillBeginDragging:scroll];
  drawer.panTranslation = translation;
  if (!cancelled) {
    CGPoint targetOffset = scroll.contentOffset;
    [delegate scrollViewWillEndDragging:scroll withVelocity:CGPointZero targetContentOffset:&targetOffset];
  }
  [delegate scrollViewDidEndDragging:scroll willDecelerate:NO];
}

static void verifyTransitionCallbacks(bool paper)
{
  UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 200, 200)];
  UIViewController *controller = [[UIViewController alloc] init];
  window.rootViewController = controller;
  [window makeKeyAndVisible];
  CallbackVerificationDrawer *drawer = [[CallbackVerificationDrawer alloc] initWithFrame:window.bounds];
  drawer.drawerWidth = 120;
  drawer.initialOpen = YES;
  NSMutableArray<NSString *> *events = [NSMutableArray array];
  void (^start)(NSDictionary *) = ^(NSDictionary *event) {
    [events addObject:[NSString stringWithFormat:@"start:%d", [event[@"open"] boolValue]]];
  };
  void (^end)(NSDictionary *) = ^(NSDictionary *event) {
    [events addObject:[NSString stringWithFormat:@"end:%d:%d", [event[@"open"] boolValue], [event[@"changed"] boolValue]]];
  };
  if (paper) {
    drawer.onTransitionStart = start;
    drawer.onTransitionEnd = end;
  } else {
    drawer.transitionStartHandler = start;
    drawer.transitionEndHandler = end;
  }
  drawer.transitionStartEventsEnabled = YES;
  drawer.transitionEndEventsEnabled = YES;
  assert(events.count == 0);
  [drawer openAnimated:YES];
  assert(events.count == 0);
  [drawer closeAnimated:NO];
  assert(([events isEqualToArray:@[@"start:0", @"end:0:1"]]));
  [controller.view addSubview:drawer];
  [window layoutIfNeeded];
  [events removeAllObjects];
  [drawer closeAnimated:YES];
  assert(events.count == 0);

  drawer.transitionStartEventsEnabled = NO;
  drawer.transitionEndEventsEnabled = NO;
  [drawer openAnimated:NO];
  assert(events.count == 0);
  drawer.transitionStartEventsEnabled = YES;
  drawer.transitionEndEventsEnabled = YES;
  [drawer closeAnimated:NO];
  assert(([events isEqualToArray:@[@"start:0", @"end:0:1"]]));
  [events removeAllObjects];

  [drawer openAnimated:YES];
  [CATransaction flush];
  waitForAnimation(drawer);
  assert(([events isEqualToArray:@[@"start:1"]]));
  assert([drawer valueForKey:@"presentationDisplayLink"] == nil);
  [drawer openAnimated:YES];
  drawer.drawerWidth = 140;
  [drawer layoutIfNeeded];
  assert(([events isEqualToArray:@[@"start:1"]]));
  waitForSettle(drawer);
  assert(([events isEqualToArray:@[@"start:1", @"end:1:1"]]));

  const bool origins[] = {false, true};
  for (bool originOpen : origins) {
    if (originOpen) [drawer openAnimated:NO];
    else [drawer closeAnimated:NO];
    [events removeAllObjects];
    endPan(drawer, originOpen ? -25 : 25, false);
    assert(([events isEqualToArray:@[originOpen ? @"start:1" : @"start:0"]]));
    waitForSettle(drawer);
    assert(([events isEqualToArray:originOpen ? @[@"start:1", @"end:1:0"] : @[@"start:0", @"end:0:0"]]));
    [events removeAllObjects];
    endPan(drawer, originOpen ? -110 : 110, true);
    waitForSettle(drawer);
    assert(([events isEqualToArray:originOpen ? @[@"start:0", @"end:0:1"] : @[@"start:1", @"end:1:1"]]));
  }

  [drawer closeAnimated:NO];
  [events removeAllObjects];
  [drawer openAnimated:YES];
  [CATransaction flush];
  waitForAnimation(drawer);
  [drawer closeAnimated:YES];
  waitForSettle(drawer);
  assert(([events isEqualToArray:@[@"start:1", @"start:0", @"end:0:0"]]));

  [events removeAllObjects];
  [drawer openAnimated:YES];
  [CATransaction flush];
  waitForAnimation(drawer);
  endPan(drawer, -200, false);
  waitForSettle(drawer);
  assert(([events isEqualToArray:@[@"start:1", @"start:0", @"end:0:0"]]));

  [events removeAllObjects];
  [drawer openAnimated:YES];
  [drawer openAnimated:NO];
  assert(([events isEqualToArray:@[@"start:1", @"start:1", @"end:1:1"]]));
  [events removeAllObjects];
  [drawer closeAnimated:YES];
  [drawer prepareForRemoval];
  [drawer removeFromSuperview];
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.04]];
  assert(([events isEqualToArray:@[@"start:0"]]));
  window.hidden = YES;
}

int main()
{
  @autoreleasepool {
    verifyScrim(false);
    verifyScrim(true);
    verifyAnimatedInteractions();
    verifyTransitionCallbacks(false);
    verifyTransitionCallbacks(true);
    std::puts("iOS drawer UIKit verification passed");
  }
}
