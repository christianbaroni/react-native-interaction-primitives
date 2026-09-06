#import "RNPagerView.h"

#include <cassert>
#include <initializer_list>

@interface RNPagerView (Verification)
- (NSDictionary *)state;
- (void)publishPageScrollSnapshot;
- (NSInteger)resolveSettlingTargetForNaturalTargetOffset:(CGFloat)naturalTargetOffset;
- (void)startNativeReleaseSnapAnimationToPage:(NSInteger)page;
- (void)stopNativeScrollAnimationAtPresentationOffset;
- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView;
@end

static void drainMainQueue()
{
  CFRunLoopRef runLoop = CFRunLoopGetCurrent();
  dispatch_async(dispatch_get_main_queue(), ^{ CFRunLoopStop(runLoop); });
  CFRunLoopRun();
}

void verifyPagerObservations()
{
  for (bool paper : {false, true}) {
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 320, 640)];
    UIViewController *controller = [UIViewController new];
    window.rootViewController = controller;
    RNPagerView *pager = [[RNPagerView alloc] initWithFrame:CGRectMake(0, 0, 320, 200)];
    [controller.view addSubview:pager];
    [window makeKeyAndVisible];
    UIView *firstPage = [UIView new];
    UIView *secondPage = [UIView new];
    [pager mountPage:firstPage atIndex:0];
    [pager mountPage:secondPage atIndex:1];
    [pager layoutIfNeeded];

    __block NSDictionary *snapshot = nil;
    __block NSUInteger count = 0;
    void (^observe)(NSDictionary *) = ^(NSDictionary *event) {
      snapshot = event;
      count += 1;
    };
    if (paper) pager.onPageScroll = observe;
    else pager.pageScrollHandler = observe;
    pager.pageScrollEventsEnabled = YES;

    for (NSInteger page : {1, 0}) {
      [pager setPage:page animated:NO];
      assert([snapshot[@"phase"] isEqual:@"idle"]);
      assert([snapshot[@"page"] integerValue] == page);
      assert([snapshot[@"position"] doubleValue] == page);
      assert([snapshot[@"settlingSource"] isEqual:@"none"]);
      assert([snapshot[@"targetPage"] integerValue] == -1);
    }

    [pager setPage:1 animated:NO];
    [CATransaction flush];
    UIScrollView *scroll = [pager valueForKey:@"scrollView"];
    CFTimeInterval deadline = CACurrentMediaTime() + 2;
    while ((scroll.layer.presentationLayer == nil || scroll.layer.presentationLayer.bounds.origin.x != 320)
        && CACurrentMediaTime() < deadline) {
      [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    }
    assert(scroll.layer.presentationLayer != nil);
    [pager setPage:0 animated:NO];
    assert(scroll.contentOffset.x == 0);
    assert(scroll.layer.presentationLayer.bounds.origin.x == 320);
    [pager setNeedsLayout];
    [pager layoutIfNeeded];
    assert([snapshot[@"phase"] isEqual:@"idle"]);
    assert([snapshot[@"position"] doubleValue] == 0);

    pager.pageScrollEventsEnabled = NO;
    pager.pageScrollEventsEnabled = YES;
    [pager publishPageScrollSnapshot];
    assert([snapshot[@"position"] doubleValue] == 0);

    [pager setPage:1 animated:YES];
    CGFloat visibleOffset = scroll.layer.presentationLayer.bounds.origin.x;
    assert(visibleOffset != scroll.contentOffset.x);
    pager.pageScrollEventsEnabled = NO;
    pager.pageScrollEventsEnabled = YES;
    [pager publishPageScrollSnapshot];
    assert([snapshot[@"phase"] isEqual:@"settling"]);
    assert([snapshot[@"offset"] doubleValue] == visibleOffset);
    [pager setPage:0 animated:NO];

    pager.pageScrollEventsEnabled = NO;
    NSUInteger previousCount = count;
    [pager setPage:1 animated:NO];
    assert(count == previousCount);

    pager.initialPage = 1;
    pager.pageScrollEventsEnabled = YES;
    for (NSInteger page : {0, 1}) {
      for (bool layoutWhileEmpty : {false, true}) {
        [pager setPage:page animated:NO];
        previousCount = count;
        [pager unmountPage:secondPage];
        [pager unmountPage:firstPage];
        if (layoutWhileEmpty) {
          [pager layoutIfNeeded];
          assert(count > previousCount);
          assert([snapshot[@"phase"] isEqual:@"empty"]);
          assert([snapshot[@"offset"] doubleValue] == 0);
        }

        pager.pageScrollEventsEnabled = NO;
        pager.pageScrollEventsEnabled = YES;
        previousCount = count;
        [pager publishPageScrollSnapshot];
        assert(count == previousCount + 1);
        assert([snapshot[@"phase"] isEqual:@"empty"]);
        assert([snapshot[@"pageCount"] integerValue] == 0);
        assert([snapshot[@"offset"] doubleValue] == 0);
        assert([snapshot[@"position"] doubleValue] == 0);
        assert([snapshot[@"settlingSource"] isEqual:@"none"]);
        assert([snapshot[@"targetPage"] integerValue] == -1);

        [pager mountPage:firstPage atIndex:0];
        [pager mountPage:secondPage atIndex:1];
        pager.pageScrollEventsEnabled = NO;
        pager.pageScrollEventsEnabled = YES;
        previousCount = count;
        [pager publishPageScrollSnapshot];
        assert(count == previousCount);
        [pager layoutIfNeeded];
        assert(count > previousCount);
        assert([snapshot[@"phase"] isEqual:@"idle"]);
        assert([snapshot[@"position"] doubleValue] == 1);
      }
    }

    pager.initialPage = 0;
    __block NSUInteger pageChanges = 0;
    void (^observePageChange)(NSDictionary *) = ^(__unused NSDictionary *event) { pageChanges += 1; };
    if (paper) pager.onPageChange = observePageChange;
    else pager.pageChangeHandler = observePageChange;
    pager.pageChangeEventsEnabled = YES;
    for (bool release : {false, true}) {
      [pager setPage:0 animated:NO];
      if (release) {
        NSInteger target = [pager resolveSettlingTargetForNaturalTargetOffset:320];
        [pager startNativeReleaseSnapAnimationToPage:target];
      } else {
        [pager setPage:1 animated:YES];
      }
      assert([[pager valueForKey:@"nativeScrollAnimationActive"] boolValue]);
      UIViewPropertyAnimator *animator = [pager valueForKey:@"snapAnimator"];
      if (release) assert(animator != nil);
      NSUInteger previousPageChanges = pageChanges;
      [pager unmountPage:secondPage];
      [pager unmountPage:firstPage];
      assert(![[pager valueForKey:@"nativeScrollAnimationActive"] boolValue]);
      assert([pager valueForKey:@"snapAnimator"] == nil);
      assert([pager valueForKey:@"settlingFinishDisplayLink"] == nil);
      assert(!animator.running);
      assert(pageChanges == previousPageChanges);
      [pager mountPage:firstPage atIndex:0];
      [pager mountPage:secondPage atIndex:1];
      [pager layoutIfNeeded];
      assert([snapshot[@"phase"] isEqual:@"idle"]);
      assert([snapshot[@"position"] doubleValue] == 0);
      assert(pageChanges == previousPageChanges);
    }

    [pager setPage:1 animated:YES];
    NSUInteger previousPageChanges = pageChanges;
    [pager stopNativeScrollAnimationAtPresentationOffset];
    [pager scrollViewDidEndScrollingAnimation:scroll];
    assert([pager.state[@"phase"] isEqual:@"settling"]);
    assert(pageChanges == previousPageChanges);
    [pager setPage:0 animated:NO];

    [pager requestPageScrollSnapshot];
    [pager setPage:1 animated:NO];
    previousCount = count;
    drainMainQueue();
    assert(count > previousCount);
    assert([snapshot[@"position"] doubleValue] == 1);

    [pager requestPageScrollSnapshot];
    pager.pageScrollEventsEnabled = NO;
    previousCount = count;
    drainMainQueue();
    assert(count == previousCount);
    [pager unmountPage:secondPage];
    [pager unmountPage:firstPage];
    [pager layoutIfNeeded];
    [pager publishPageScrollSnapshot];
    assert(count == previousCount);
    pager.pageScrollEventsEnabled = YES;
    [pager requestPageScrollSnapshot];
    [pager prepareForRemoval];
    drainMainQueue();
    assert(count == previousCount);
    window.hidden = YES;
  }
}
