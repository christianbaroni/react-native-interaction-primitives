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

  verifyPendingPanCommand(drawer, false, false);
  verifyPendingPanCommand(drawer, false, true);
  verifyPendingPanCommand(drawer, true, false);
  verifyPendingPanCommand(drawer, true, true);

  [drawer closeAnimated:NO];
  [drawer prepareForRemoval];
  [drawer removeFromSuperview];
  window.hidden = YES;
}

int main()
{
  @autoreleasepool {
    verifyScrim(false);
    verifyScrim(true);
    verifyAnimatedInteractions();
    std::puts("iOS drawer UIKit verification passed");
  }
}
