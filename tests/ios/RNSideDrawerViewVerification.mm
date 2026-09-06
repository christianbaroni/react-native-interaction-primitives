#import "RNSideDrawerContentView.h"
#import "RNSideDrawerView.h"
#import <React/RCTSurfaceTouchHandler.h>
#import <React/RCTTouchHandler.h>
#import <React/UIView+React.h>

#include <cassert>
#include <cmath>
#include <cstdio>

// These tests exercise UIKit hit testing, not React touch dispatch.
@implementation RCTTouchHandler
- (void)cancel {}
@end

@implementation RCTSurfaceTouchHandler
@end

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

int main()
{
  @autoreleasepool {
    verifyScrim(false);
    verifyScrim(true);
    std::puts("iOS drawer UIKit verification passed");
  }
}
