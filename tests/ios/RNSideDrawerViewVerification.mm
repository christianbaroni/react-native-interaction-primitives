#import "RNSideDrawerContentView.h"
#import "RNSideDrawerView.h"
#import <React/RCTSurfaceTouchHandler.h>
#import <React/RCTTouchHandler.h>
#import <React/UIView+React.h>
#import <objc/runtime.h>

#include <cassert>
#include <cmath>
#include <initializer_list>

// These tests exercise UIKit and native drawer callbacks, not React touch dispatch.
@implementation RCTTouchHandler
- (void)cancel {}
@end

@implementation RCTSurfaceTouchHandler
@end

@interface RNSideDrawerView (Verification)
- (void)handleContactBegin;
- (BOOL)canBeginPanWithVelocity:(CGPoint)velocity;
- (void)handlePanGesture:(UIPanGestureRecognizer *)pan;
@end

@interface VerificationPanInput : NSObject
@property (nonatomic, assign) CGFloat translation;
@property (nonatomic, assign) CGFloat velocity;
@property (nonatomic, assign) UIGestureRecognizerState state;
@end

@implementation VerificationPanInput
@end

static char panInputKey;

static VerificationPanInput *panInput(UIPanGestureRecognizer *pan)
{
  return objc_getAssociatedObject(pan, &panInputKey);
}

static CGPoint panTranslation(UIPanGestureRecognizer *pan, SEL, UIView *)
{
  return CGPointMake(panInput(pan).translation, 0);
}

static CGPoint panVelocity(UIPanGestureRecognizer *pan, SEL, UIView *)
{
  return CGPointMake(panInput(pan).velocity, 0);
}

static UIGestureRecognizerState panState(UIPanGestureRecognizer *pan, SEL)
{
  return panInput(pan).state;
}

static VerificationPanInput *controlPan(RNSideDrawerView *drawer)
{
  // Supply gesture samples at the delegate boundary while retaining UIKit's scroll view and animator.
  UIScrollView *scroll = [drawer valueForKey:@"scrollView"];
  UIPanGestureRecognizer *pan = scroll.panGestureRecognizer;
  Class parent = object_getClass(pan);
  Class subclass = objc_lookUpClass("RNIPVerificationPan");
  if (subclass == Nil) {
    subclass = objc_allocateClassPair(parent, "RNIPVerificationPan", 0);
    class_addMethod(subclass, @selector(translationInView:), (IMP)panTranslation,
        method_getTypeEncoding(class_getInstanceMethod(parent, @selector(translationInView:))));
    class_addMethod(subclass, @selector(velocityInView:), (IMP)panVelocity,
        method_getTypeEncoding(class_getInstanceMethod(parent, @selector(velocityInView:))));
    class_addMethod(subclass, @selector(state), (IMP)panState,
        method_getTypeEncoding(class_getInstanceMethod(parent, @selector(state))));
    objc_registerClassPair(subclass);
  }
  VerificationPanInput *input = [VerificationPanInput new];
  objc_setAssociatedObject(pan, &panInputKey, input, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  object_setClass(pan, subclass);
  return input;
}

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

static void verifyPanCommand(RNSideDrawerView *drawer, bool commandOpen)
{
  [drawer closeAnimated:NO];
  [drawer openAnimated:YES];
  [CATransaction flush];
  waitForAnimation(drawer);

  UIScrollView *scroll = [drawer valueForKey:@"scrollView"];
  id<UIScrollViewDelegate> delegate = (id<UIScrollViewDelegate>)drawer;
  [delegate scrollViewWillBeginDragging:scroll];
  assert([drawer valueForKey:@"transitionAnimator"] == nil);

  if (commandOpen) [drawer openAnimated:YES];
  else [drawer closeAnimated:YES];
  assert([[drawer valueForKey:@"suppressCurrentDragRelease"] boolValue]);

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

  verifyPanCommand(drawer, false);
  verifyPanCommand(drawer, true);
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

static void endPan(RNSideDrawerView *drawer, CGFloat translation, bool cancelled)
{
  UIScrollView *scroll = [drawer valueForKey:@"scrollView"];
  id<UIScrollViewDelegate> delegate = (id<UIScrollViewDelegate>)drawer;
  VerificationPanInput *input = panInput(scroll.panGestureRecognizer);
  input.translation = 0;
  input.state = UIGestureRecognizerStateBegan;
  [delegate scrollViewWillBeginDragging:scroll];
  input.translation = translation;
  input.state = cancelled ? UIGestureRecognizerStateCancelled : UIGestureRecognizerStateEnded;
  if (!cancelled) {
    CGPoint targetOffset = scroll.contentOffset;
    [delegate scrollViewWillEndDragging:scroll withVelocity:CGPointZero targetContentOffset:&targetOffset];
  }
  [delegate scrollViewDidEndDragging:scroll willDecelerate:NO];
}

static void verifyPanInterruption(bool opening, bool endSide, bool observed)
{
  UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 400, 800)];
  window.rootViewController = [UIViewController new];
  [window makeKeyAndVisible];
  RNSideDrawerView *drawer = [[RNSideDrawerView alloc] initWithFrame:window.bounds];
  drawer.drawerWidth = 320;
  drawer.side = endSide ? RNSideDrawerSideEnd : RNSideDrawerSideStart;
  drawer.initialOpen = !opening;
  drawer.springMass = 0.8;
  drawer.springStiffness = 680;
  drawer.springDamping = 46;
  drawer.progressEventsEnabled = observed;
  [window.rootViewController.view addSubview:drawer];
  [window layoutIfNeeded];
  VerificationPanInput *input = controlPan(drawer);
  UIScrollView *scroll = [drawer valueForKey:@"scrollView"];
  id<UIScrollViewDelegate> delegate = (id<UIScrollViewDelegate>)drawer;
  CGFloat direction = endSide ? -1 : 1;
  CGFloat travelDirection = (opening ? 1 : -1) * direction;

  // Settle from a preceding drag, so the reversing gesture changes an interior scroll offset.
  input.state = UIGestureRecognizerStateBegan;
  [delegate scrollViewWillBeginDragging:scroll];
  input.translation = travelDirection * 160;
  input.velocity = travelDirection * 700;
  input.state = UIGestureRecognizerStateChanged;
  scroll.contentOffset = CGPointMake(160, 0);
  [drawer handlePanGesture:scroll.panGestureRecognizer];
  input.state = UIGestureRecognizerStateEnded;
  CGPoint targetOffset = scroll.contentOffset;
  [delegate scrollViewWillEndDragging:scroll withVelocity:CGPointZero targetContentOffset:&targetOffset];
  [delegate scrollViewDidEndDragging:scroll willDecelerate:NO];
  [CATransaction flush];

  UIView *pane = [drawer valueForKey:@"contentPresentationView"];
  CGFloat target = opening ? 320 : 0;
  CGFloat before = opening ? 0 : 320;
  CFTimeInterval deadline = CACurrentMediaTime() + 2;
  do {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    CALayer *presentation = pane.layer.presentationLayer ?: pane.layer;
    before = (presentation.position.x - scroll.contentOffset.x - drawer.bounds.size.width / 2) * direction;
  } while (std::abs(target - before) > (observed ? 16 : 32) && CACurrentMediaTime() < deadline);
  assert(CACurrentMediaTime() < deadline);
  assert([drawer valueForKey:@"transitionAnimator"] != nil);

  input.translation = -travelDirection * 8;
  input.velocity = -travelDirection * 700;
  input.state = UIGestureRecognizerStateBegan;
  assert([drawer canBeginPanWithVelocity:CGPointMake(input.velocity, 0)]);
  [delegate scrollViewWillBeginDragging:scroll];
  assert([drawer valueForKey:@"transitionAnimator"] == nil);
  assert(![[drawer valueForKey:@"transitionActive"] boolValue]);
  assert(std::abs([[drawer valueForKey:@"reveal"] doubleValue] - before) < 0.001);

  for (int step = 1; step <= 2; step++) {
    input.translation -= travelDirection * 8;
    input.state = UIGestureRecognizerStateChanged;
    scroll.contentOffset = CGPointMake(scroll.contentOffset.x + travelDirection * 8, 0);
    [drawer handlePanGesture:scroll.panGestureRecognizer];
    CGFloat expected = before + (opening ? -1 : 1) * step * 8;
    assert(std::abs([[drawer valueForKey:@"reveal"] doubleValue] - expected) < 0.001);
    CGFloat model = (pane.layer.position.x - scroll.contentOffset.x - drawer.bounds.size.width / 2) * direction;
    assert(std::abs(model - expected) < 0.001);
  }

  CGFloat beforeLayout = [[drawer valueForKey:@"reveal"] doubleValue];
  drawer.side = endSide ? RNSideDrawerSideStart : RNSideDrawerSideEnd;
  drawer.drawerWidth = 400;
  [drawer layoutIfNeeded];
  [drawer handlePanGesture:scroll.panGestureRecognizer];
  assert(std::abs([[drawer valueForKey:@"reveal"] doubleValue] - beforeLayout * 1.25) < 0.001);
  input.velocity = travelDirection * 700;
  input.state = UIGestureRecognizerStateEnded;
  targetOffset = scroll.contentOffset;
  [delegate scrollViewWillEndDragging:scroll withVelocity:CGPointZero targetContentOffset:&targetOffset];
  [delegate scrollViewDidEndDragging:scroll willDecelerate:NO];
  assert([[drawer valueForKey:@"targetOpen"] boolValue] == !opening);
  waitForSettle(drawer);
  [drawer prepareForRemoval];
  [drawer removeFromSuperview];
  window.hidden = YES;
}

static void verifyTransitionCallbacks(bool paper)
{
  UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 200, 200)];
  UIViewController *controller = [[UIViewController alloc] init];
  window.rootViewController = controller;
  [window makeKeyAndVisible];
  RNSideDrawerView *drawer = [[RNSideDrawerView alloc] initWithFrame:window.bounds];
  controlPan(drawer);
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

void verifySideDrawer()
{
  verifyScrim(false);
  verifyScrim(true);
  verifyAnimatedInteractions();
  for (bool opening : {false, true}) {
    for (bool endSide : {false, true}) {
      for (bool observed : {false, true}) verifyPanInterruption(opening, endSide, observed);
    }
  }
  verifyTransitionCallbacks(false);
  verifyTransitionCallbacks(true);
}
