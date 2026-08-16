#import "RNPagerView.h"

#import "RNPagerPageView.h"
#import "RNPagerScrollView.h"

#import <React/UIView+React.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>

typedef NS_ENUM(NSInteger, RNPagerPhase) {
  RNPagerPhaseEmpty,
  RNPagerPhaseIdle,
  RNPagerPhaseDragging,
  RNPagerPhaseSettling,
};

typedef NS_ENUM(NSInteger, RNPagerSettlingSource) {
  RNPagerSettlingSourceNone,
  RNPagerSettlingSourceProgrammatic,
  RNPagerSettlingSourceRelease,
};

@interface RNPagerView () <UIScrollViewDelegate>
- (NSInteger)resolveSettlingTargetForNaturalTargetOffset:(CGFloat)naturalTargetOffset;
- (void)applyScrollPhysicsConfiguration;
- (CGRect)scrollViewFrameForPageExtent:(CGFloat)pageExtent;
- (void)setCurrentOffset:(CGFloat)offset allowingBounce:(BOOL)allowingBounce;
- (void)stopNativeScrollAnimationAtPresentationOffset;
- (void)startNativeReleaseSnapAnimationToPage:(NSInteger)page;
- (void)stopSettlingFinishWatcher;
- (void)stepSettlingFinishWatcher:(CADisplayLink *)displayLink;
- (CGFloat)projectedOffsetForReleaseVelocity:(CGFloat)releaseVelocity;
- (CGFloat)scrollPixelTolerance;
- (BOOL)shouldDeferSettlingFinish;
- (void)finishSettlingAtPageIfMotionIsAtRest:(NSInteger)page;
- (void)publishState;
@end

@implementation RNPagerView {
  RNPagerScrollView *_scrollView;
  UIView *_contentView;
  NSMutableArray<UIView *> *_pages;
  RNPagerPhase _phase;
  NSInteger _anchorPage;
  CGFloat _anchorOffset;
  NSInteger _targetPage;
  RNPagerSettlingSource _settlingSource;
  NSInteger _selectedPage;
  NSInteger _lastEmittedPage;
  UIViewPropertyAnimator *_snapAnimator;
  CADisplayLink *_settlingFinishDisplayLink;
  BOOL _nativeScrollAnimationActive;
  BOOL _hasScrollVelocitySample;
  CGFloat _lastScrollSampleOffset;
  CFTimeInterval _lastScrollSampleTime;
  CGFloat _scrollVelocity;
  CGFloat _interruptedSettleVelocity;
  BOOL _hasLaidOutPages;
}

static const CGFloat RNPagerMillisecondsPerSecond = 1000.0;

static CGFloat RNPagerBoundedDecelerationRate(CGFloat decelerationRate)
{
  if (!isfinite(decelerationRate)) return UIScrollViewDecelerationRateNormal;
  return MIN(0.999999, MAX(0.0, decelerationRate));
}

static CGFloat RNPagerProjectOffset(CGFloat offset, CGFloat velocity, CGFloat decelerationRate)
{
  if (!isfinite(velocity)) return offset;
  CGFloat rate = RNPagerBoundedDecelerationRate(decelerationRate);
  return offset + velocity * rate / (1.0 - rate);
}

static NSInteger RNPagerClampPage(NSInteger page, NSInteger pageCount)
{
  if (pageCount <= 0) return 0;
  return MIN(pageCount - 1, MAX(0, page));
}

static NSInteger RNPagerResolveTargetPage(
    NSInteger anchorPage,
    CGFloat naturalTargetOffset,
    NSInteger pageCount,
    CGFloat pageExtent)
{
  if (pageCount <= 0) return 0;
  NSInteger boundedAnchor = RNPagerClampPage(anchorPage, pageCount);
  if (pageExtent <= 0) return boundedAnchor;

  NSInteger projectedPage = RNPagerClampPage((NSInteger)llround(naturalTargetOffset / pageExtent), pageCount);
  NSInteger candidatePage = MIN(boundedAnchor + 1, MAX(boundedAnchor - 1, projectedPage));
  return RNPagerClampPage(candidatePage, pageCount);
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if ((self = [super initWithFrame:frame])) {
    self.clipsToBounds = NO;
    _scrollEnabled = YES;
    _initialPage = 0;
    _pageInset = 0;
    _pageSpacing = 0;
    _orientation = RNPagerOrientationHorizontal;
    _phase = RNPagerPhaseEmpty;
    _settlingSource = RNPagerSettlingSourceNone;
    _selectedPage = 0;
    _lastEmittedPage = NSNotFound;
    _pages = [NSMutableArray array];

    RNPagerScrollView *scrollView = [[RNPagerScrollView alloc] initWithFrame:self.bounds];
    scrollView.interactionBoundsView = self;
    scrollView.pagerOrientation = _orientation;
    scrollView.pagerScrollEnabled = _scrollEnabled;
    _scrollView = scrollView;
    _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scrollView.clipsToBounds = NO;
    _scrollView.delegate = self;
    _scrollView.decelerationRate = UIScrollViewDecelerationRateNormal;
    _scrollView.pagingEnabled = YES;
    _scrollView.bounces = YES;
    _scrollView.delaysContentTouches = NO;
    _scrollView.canCancelContentTouches = YES;
    _scrollView.directionalLockEnabled = YES;
    _scrollView.showsHorizontalScrollIndicator = NO;
    _scrollView.showsVerticalScrollIndicator = NO;
    [self applyScrollPhysicsConfiguration];
    [super addSubview:_scrollView];

    _contentView = [[UIView alloc] initWithFrame:_scrollView.bounds];
    _contentView.clipsToBounds = NO;
    [_scrollView addSubview:_contentView];
  }
  return self;
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  [self layoutPagesPreservingPosition:YES];
  _hasLaidOutPages = _pages.count > 0;
}

- (void)dealloc
{
  [self stopSettlingFinishWatcher];
  [_snapAnimator stopAnimation:YES];
  _snapAnimator = nil;
}

- (void)setScrollEnabled:(BOOL)scrollEnabled
{
  _scrollEnabled = scrollEnabled;
  _scrollView.pagerScrollEnabled = scrollEnabled;
}

- (void)setInitialPage:(NSInteger)initialPage
{
  _initialPage = MAX(0, initialPage);
  if (!_hasLaidOutPages) {
    _selectedPage = RNPagerClampPage(_initialPage, _pages.count);
  }
}

- (void)setPageInset:(CGFloat)pageInset
{
  _pageInset = MAX(0, pageInset);
  [self setNeedsLayout];
}

- (void)setPageSpacing:(CGFloat)pageSpacing
{
  _pageSpacing = MAX(0, pageSpacing);
  [self setNeedsLayout];
}

- (void)setOrientation:(RNPagerOrientation)orientation
{
  if (_orientation == orientation) return;

  const BOOL motionWasActive = _phase == RNPagerPhaseDragging || _phase == RNPagerPhaseSettling;
  NSInteger page = _selectedPage;
  if (_phase == RNPagerPhaseSettling) {
    page = _targetPage;
  } else if (_phase == RNPagerPhaseDragging) {
    page = [self currentSettledPage];
  }

  [_scrollView prepareForPagerMotion];
  [self stopSettlingFinishWatcher];
  if (_nativeScrollAnimationActive) [self stopNativeScrollAnimationAtPresentationOffset];
  if (motionWasActive) [self finishSettlingAtPage:page];

  _orientation = orientation;
  _scrollView.pagerOrientation = orientation;
  [self applyScrollPhysicsConfiguration];
  [self layoutPagesPreservingPosition:NO];
  [self setNeedsLayout];
}

- (void)mountPage:(UIView *)page atIndex:(NSInteger)index
{
  NSUInteger boundedIndex = MIN((NSUInteger)MAX(index, 0), _pages.count);
  [_pages insertObject:page atIndex:boundedIndex];
  [_contentView insertSubview:page atIndex:boundedIndex];
  if (!_hasLaidOutPages) {
    _selectedPage = RNPagerClampPage(_initialPage, _pages.count);
  }
  if (_phase == RNPagerPhaseEmpty) {
    [self transitionToPhase:RNPagerPhaseIdle];
  }
  [self layoutPagesPreservingPosition:NO];
  [self publishState];
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-missing-super-calls"
// React pages are mounted into _contentView; calling super would make the pager
// a second page attachment owner.
- (NSArray<UIView *> *)reactSubviews
{
  return [_pages copy];
}

- (void)insertReactSubview:(UIView *)subview atIndex:(NSInteger)atIndex
{
  if (![subview isKindOfClass:RNPagerPageView.class]) return;
  [self mountPage:subview atIndex:atIndex];
}

- (void)removeReactSubview:(UIView *)subview
{
  if (![subview isKindOfClass:RNPagerPageView.class]) return;
  [self unmountPage:subview];
}

- (void)didUpdateReactSubviews
{
  // Paper calls this after child mutations. Pages are mounted into the internal
  // scroll content view by insertReactSubview so the pager remains the only
  // page-list owner.
}
#pragma clang diagnostic pop

- (void)unmountPage:(UIView *)page
{
  [_scrollView willRemoveContentView:page];
  [_pages removeObjectIdenticalTo:page];
  [page removeFromSuperview];
  _selectedPage = RNPagerClampPage(_selectedPage, _pages.count);
  if (_pages.count == 0) {
    _hasLaidOutPages = NO;
    [self transitionToPhase:RNPagerPhaseEmpty];
  }
  [self layoutPagesPreservingPosition:NO];
  [self publishState];
}

- (void)setPage:(NSInteger)page animated:(BOOL)animated
{
  if (page < 0 || page >= (NSInteger)_pages.count) return;
  [_scrollView prepareForPagerMotion];
  if (_phase == RNPagerPhaseSettling) {
    [self stopNativeScrollAnimationAtPresentationOffset];
  }
  _anchorPage = [self currentSettledPage];
  _anchorOffset = [self currentOffset];
  _targetPage = page;
  _settlingSource = RNPagerSettlingSourceProgrammatic;
  [self transitionToPhase:RNPagerPhaseSettling];
  CGPoint offset = [self contentOffsetForPage:page];
  if (animated) {
    [self publishState];
    [self startNativeScrollAnimationToPage:page];
  } else {
    [self publishState];
    [_scrollView setContentOffset:offset animated:NO];
    [self finishSettlingAtPage:page];
  }
}

- (NSDictionary *)state
{
  NSInteger pageCount = _pages.count;
  CGFloat extent = [self pageExtent];
  CGFloat offset = [self currentOffset];
  CGFloat position = extent > 0 ? offset / extent : 0;
  NSInteger page = pageCount > 0 ? RNPagerClampPage((NSInteger)llround(position), pageCount) : 0;
  return @{
    @"anchorOffset" : @(_anchorOffset),
    @"anchorPage" : @(_anchorPage),
    @"offset" : @(offset),
    @"page" : @(page),
    @"pageCount" : @(pageCount),
    @"pageExtent" : @(extent),
    @"phase" : [self phaseName],
    @"position" : @(position),
    @"settlingSource" : [self settlingSourceName],
    @"targetPage" : @(_phase == RNPagerPhaseSettling ? _targetPage : -1),
  };
}

- (void)prepareForRemoval
{
  [_scrollView prepareForPagerMotion];
  [self stopSettlingFinishWatcher];
  if (_nativeScrollAnimationActive || _phase == RNPagerPhaseSettling) {
    [self stopNativeScrollAnimationAtPresentationOffset];
  }
  [_pages removeAllObjects];
  _hasLaidOutPages = NO;
  [_contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
  [self transitionToPhase:RNPagerPhaseEmpty];
}

- (void)layoutPagesPreservingPosition:(BOOL)preservePosition
{
  CGFloat oldExtent = [self pageExtent];
  CGFloat oldPosition = oldExtent > 0 ? [self currentOffset] / oldExtent : _selectedPage;
  CGSize pageSize = [self pageSize];
  CGFloat extent = [self pageExtentForPageSize:pageSize];
  _scrollView.frame = [self scrollViewFrameForPageExtent:extent];
  for (NSUInteger index = 0; index < _pages.count; index += 1) {
    UIView *container = _pages[index];
    CGRect frame;
    if (_orientation == RNPagerOrientationHorizontal) {
      frame = CGRectMake(_pageSpacing * 0.5 + (CGFloat)index * extent, 0, pageSize.width, pageSize.height);
    } else {
      frame = CGRectMake(0, _pageSpacing * 0.5 + (CGFloat)index * extent, pageSize.width, pageSize.height);
    }
    container.frame = frame;
  }
  CGFloat contentLength = _pages.count == 0 ? extent : (CGFloat)_pages.count * extent;
  if (_orientation == RNPagerOrientationHorizontal) {
    _contentView.frame = CGRectMake(0, 0, MAX(0, contentLength), self.bounds.size.height);
  } else {
    _contentView.frame = CGRectMake(0, 0, self.bounds.size.width, MAX(0, contentLength));
  }
  _scrollView.contentSize = _contentView.bounds.size;
  CGFloat nextPosition = preservePosition ? oldPosition : _selectedPage;
  if (!isfinite(nextPosition)) nextPosition = _selectedPage;
  [self setCurrentOffset:nextPosition * extent allowingBounce:preservePosition];
}

- (CGSize)pageSize
{
  if (_orientation == RNPagerOrientationHorizontal) {
    return CGSizeMake(MAX(0, self.bounds.size.width - _pageInset * 2), self.bounds.size.height);
  }
  return CGSizeMake(self.bounds.size.width, MAX(0, self.bounds.size.height - _pageInset * 2));
}

- (CGFloat)pageExtent
{
  return [self pageExtentForPageSize:[self pageSize]];
}

- (CGFloat)pageExtentForPageSize:(CGSize)pageSize
{
  return (_orientation == RNPagerOrientationHorizontal ? pageSize.width : pageSize.height) + _pageSpacing;
}

- (CGRect)scrollViewFrameForPageExtent:(CGFloat)pageExtent
{
  CGFloat extent = MAX(0, pageExtent);
  if (_orientation == RNPagerOrientationHorizontal) {
    CGFloat originX = (self.bounds.size.width - extent) * 0.5;
    return CGRectMake(originX, 0, extent, self.bounds.size.height);
  }
  CGFloat originY = (self.bounds.size.height - extent) * 0.5;
  return CGRectMake(0, originY, self.bounds.size.width, extent);
}

- (CGFloat)currentOffset
{
  return _orientation == RNPagerOrientationHorizontal ? _scrollView.contentOffset.x : _scrollView.contentOffset.y;
}

- (CGFloat)presentationOffset
{
  CALayer *presentationLayer = _scrollView.layer.presentationLayer;
  if (presentationLayer == nil) return [self currentOffset];
  CGFloat offset = _orientation == RNPagerOrientationHorizontal ? presentationLayer.bounds.origin.x : presentationLayer.bounds.origin.y;
  return offset;
}

- (CGFloat)maxScrollOffset
{
  return MAX(0, ((CGFloat)_pages.count - 1) * [self pageExtent]);
}

- (void)setCurrentOffset:(CGFloat)offset
{
  [self setCurrentOffset:offset allowingBounce:NO];
}

- (void)setCurrentOffset:(CGFloat)offset allowingBounce:(BOOL)allowingBounce
{
  CGPoint point = _scrollView.contentOffset;
  CGFloat resolvedOffset = allowingBounce ? offset : MAX(0, MIN(offset, [self maxScrollOffset]));
  if (_orientation == RNPagerOrientationHorizontal) point.x = resolvedOffset;
  else point.y = resolvedOffset;
  _scrollView.contentOffset = point;
}

- (CGPoint)contentOffsetForPage:(NSInteger)page
{
  CGFloat offset = RNPagerClampPage(page, _pages.count) * [self pageExtent];
  return _orientation == RNPagerOrientationHorizontal ? CGPointMake(offset, 0) : CGPointMake(0, offset);
}

- (CGFloat)releaseVelocityFromScrollVelocity:(CGPoint)velocity
{
  CGFloat platformVelocity = _orientation == RNPagerOrientationHorizontal ? velocity.x : velocity.y;
  return platformVelocity;
}

- (CGFloat)releaseVelocityFromPanGesture
{
  CGPoint velocity = [_scrollView.panGestureRecognizer velocityInView:self];
  CGFloat fingerVelocity = _orientation == RNPagerOrientationHorizontal ? velocity.x : velocity.y;
  return -fingerVelocity / RNPagerMillisecondsPerSecond;
}

- (void)applyScrollPhysicsConfiguration
{
  BOOL isHorizontal = _orientation == RNPagerOrientationHorizontal;
  _scrollView.bounces = YES;
  _scrollView.alwaysBounceHorizontal = isHorizontal;
  _scrollView.alwaysBounceVertical = !isHorizontal;
  if (@available(iOS 17.4, *)) {
    if (isHorizontal) {
      _scrollView.bouncesHorizontally = YES;
      _scrollView.transfersHorizontalScrollingToParent = NO;
      _scrollView.transfersVerticalScrollingToParent = YES;
    } else {
      _scrollView.bouncesVertically = YES;
      _scrollView.transfersHorizontalScrollingToParent = YES;
      _scrollView.transfersVerticalScrollingToParent = NO;
    }
  }
}

- (void)recordScrollVelocitySample
{
  CFTimeInterval now = CACurrentMediaTime();
  CGFloat offset = [self currentOffset];
  if (_hasScrollVelocitySample && now > _lastScrollSampleTime) {
    _scrollVelocity = (offset - _lastScrollSampleOffset) / (now - _lastScrollSampleTime);
  }
  _lastScrollSampleOffset = offset;
  _lastScrollSampleTime = now;
  _hasScrollVelocitySample = YES;
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
  (void)scrollView;
  NSInteger interruptedTargetPage = _phase == RNPagerPhaseSettling ? _targetPage : NSNotFound;
  CGFloat interruptedSettleVelocity = _phase == RNPagerPhaseSettling ? _scrollVelocity / RNPagerMillisecondsPerSecond : 0;
  if (_nativeScrollAnimationActive) {
    [self stopNativeScrollAnimationAtPresentationOffset];
  }
  [self stopSettlingFinishWatcher];
  _anchorOffset = [self currentOffset];
  if (interruptedTargetPage != NSNotFound) {
    _anchorPage = RNPagerClampPage(interruptedTargetPage, _pages.count);
  } else {
    _anchorPage = RNPagerClampPage((NSInteger)llround([self pageExtent] > 0 ? _anchorOffset / [self pageExtent] : 0), _pages.count);
  }
  _targetPage = _anchorPage;
  _interruptedSettleVelocity = interruptedSettleVelocity;
  _settlingSource = RNPagerSettlingSourceNone;
  [self transitionToPhase:RNPagerPhaseDragging];
  [self publishState];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
  [self recordScrollVelocitySample];
  [self publishPageScroll];
  if (!_nativeScrollAnimationActive && !scrollView.dragging && !scrollView.tracking && !scrollView.decelerating) {
    [self scheduleFinishSettlingAtRestingOffset];
  }
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView
                      withVelocity:(CGPoint)velocity
               targetContentOffset:(inout CGPoint *)targetContentOffset
{
  (void)scrollView;
  CGFloat releaseVelocity = [self releaseVelocityFromScrollVelocity:velocity];
  CGFloat naturalOffset = _orientation == RNPagerOrientationHorizontal ? targetContentOffset->x : targetContentOffset->y;
  if (!isfinite(naturalOffset)) naturalOffset = [self projectedOffsetForReleaseVelocity:releaseVelocity];
  NSInteger target = [self resolveSettlingTargetForNaturalTargetOffset:naturalOffset];
  CGPoint targetOffset = [self contentOffsetForPage:target];
  if (_orientation == RNPagerOrientationHorizontal) targetContentOffset->x = targetOffset.x;
  else targetContentOffset->y = targetOffset.y;
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
  (void)scrollView;
  if (_phase == RNPagerPhaseDragging) {
    CGFloat naturalOffset = [self projectedOffsetForReleaseVelocity:[self releaseVelocityFromPanGesture]];
    [self resolveSettlingTargetForNaturalTargetOffset:naturalOffset];
  }
  if (!decelerate) {
    if ([self shouldDeferSettlingFinish]) {
      [self scheduleFinishSettlingAtRestingOffset];
      return;
    }
    if (_phase == RNPagerPhaseSettling) {
      CGFloat targetOffset = _targetPage * [self pageExtent];
      if (fabs([self currentOffset] - targetOffset) > [self scrollPixelTolerance]) {
        [self startNativeReleaseSnapAnimationToPage:_targetPage];
      } else {
        [self finishSettlingAtPageIfMotionIsAtRest:_targetPage];
      }
    } else {
      [self finishSettlingAtCurrentOffsetIfNeeded];
    }
  }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
  (void)scrollView;
  if (_phase == RNPagerPhaseSettling) {
    [self finishSettlingAtPageIfMotionIsAtRest:_targetPage];
  } else {
    [self finishSettlingAtCurrentOffsetIfNeeded];
  }
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView
{
  (void)scrollView;
  _nativeScrollAnimationActive = NO;
  if (_phase == RNPagerPhaseSettling) {
    [self finishSettlingAtPageIfMotionIsAtRest:_targetPage];
  }
}

- (void)stopNativeScrollAnimationAtPresentationOffset
{
  [self stopSettlingFinishWatcher];
  CGFloat offset = [self presentationOffset];
  [_snapAnimator stopAnimation:YES];
  _snapAnimator = nil;
  _nativeScrollAnimationActive = NO;
  [_scrollView.layer removeAllAnimations];
  [self setCurrentOffset:offset allowingBounce:NO];
  _lastScrollSampleOffset = offset;
  _lastScrollSampleTime = CACurrentMediaTime();
  _hasScrollVelocitySample = YES;
  _scrollVelocity = 0;
}

- (CGFloat)projectedOffsetForReleaseVelocity:(CGFloat)releaseVelocity
{
  CGFloat resolvedVelocity = releaseVelocity + _interruptedSettleVelocity;
  return RNPagerProjectOffset([self currentOffset], resolvedVelocity, _scrollView.decelerationRate);
}

- (NSInteger)resolveSettlingTargetForNaturalTargetOffset:(CGFloat)naturalTargetOffset
{
  NSInteger target = RNPagerResolveTargetPage(
      _anchorPage,
      naturalTargetOffset,
      _pages.count,
      [self pageExtent]);
  _targetPage = target;
  _settlingSource = RNPagerSettlingSourceRelease;
  _interruptedSettleVelocity = 0;
  [self transitionToPhase:RNPagerPhaseSettling];
  [self publishState];
  return target;
}

- (void)startNativeReleaseSnapAnimationToPage:(NSInteger)page
{
  NSInteger target = RNPagerClampPage(page, _pages.count);
  CGFloat targetOffset = target * [self pageExtent];
  [self stopSettlingFinishWatcher];
  if (fabs([self currentOffset] - targetOffset) <= [self scrollPixelTolerance]) {
    [self finishSettlingAtPage:target];
    return;
  }
  [_snapAnimator stopAnimation:YES];
  _snapAnimator = nil;
  _nativeScrollAnimationActive = YES;
  UISpringTimingParameters *timingParameters = [[UISpringTimingParameters alloc] init];
  UIViewPropertyAnimator *animator = [[UIViewPropertyAnimator alloc] initWithDuration:0 timingParameters:timingParameters];
  __weak RNPagerView *weakSelf = self;
  __weak UIViewPropertyAnimator *weakAnimator = animator;
  [animator addAnimations:^{
    [weakSelf setCurrentOffset:targetOffset allowingBounce:NO];
  }];
  [animator addCompletion:^(__unused UIViewAnimatingPosition finalPosition) {
    RNPagerView *strongSelf = weakSelf;
    UIViewPropertyAnimator *strongAnimator = weakAnimator;
    if (strongSelf == nil || strongSelf->_snapAnimator != strongAnimator) return;
    strongSelf->_snapAnimator = nil;
    strongSelf->_nativeScrollAnimationActive = NO;
    [strongSelf finishSettlingAtPageIfMotionIsAtRest:target];
  }];
  _snapAnimator = animator;
  [animator startAnimation];
}

- (void)startNativeScrollAnimationToPage:(NSInteger)page
{
  NSInteger target = RNPagerClampPage(page, _pages.count);
  CGPoint targetOffset = [self contentOffsetForPage:target];
  [self stopSettlingFinishWatcher];
  if (fabs([self currentOffset] - (target * [self pageExtent])) <= [self scrollPixelTolerance]) {
    [self finishSettlingAtPage:target];
    return;
  }
  _nativeScrollAnimationActive = YES;
  [_scrollView setContentOffset:targetOffset animated:YES];
}

- (void)scheduleFinishSettlingAtRestingOffset
{
  if (_phase != RNPagerPhaseDragging && _phase != RNPagerPhaseSettling) return;
  if (_settlingFinishDisplayLink != nil) return;
  _settlingFinishDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(stepSettlingFinishWatcher:)];
  [_settlingFinishDisplayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stopSettlingFinishWatcher
{
  [_settlingFinishDisplayLink invalidate];
  _settlingFinishDisplayLink = nil;
}

- (void)stepSettlingFinishWatcher:(CADisplayLink *)displayLink
{
  (void)displayLink;
  if (_phase != RNPagerPhaseDragging && _phase != RNPagerPhaseSettling) {
    [self stopSettlingFinishWatcher];
    return;
  }
  if ([self shouldDeferSettlingFinish]) return;
  [self stopSettlingFinishWatcher];
  if (_phase == RNPagerPhaseSettling) {
    [self finishSettlingAtPage:_targetPage];
  } else {
    [self finishSettlingAtCurrentOffsetIfNeeded];
  }
}

- (CGFloat)scrollPixelTolerance
{
  return 1.0 / MAX(UIScreen.mainScreen.scale, 1.0);
}

- (BOOL)shouldDeferSettlingFinish
{
  if (_nativeScrollAnimationActive || _scrollView.dragging || _scrollView.tracking || _scrollView.decelerating) {
    return YES;
  }
  CGFloat currentOffset = [self currentOffset];
  CGFloat presentationOffset = [self presentationOffset];
  CGFloat maxOffset = [self maxScrollOffset];
  CGFloat tolerance = [self scrollPixelTolerance];
  if (currentOffset < -tolerance || currentOffset > maxOffset + tolerance) return YES;
  if (presentationOffset < -tolerance || presentationOffset > maxOffset + tolerance) return YES;
  if (fabs(presentationOffset - currentOffset) > tolerance) return YES;
  return NO;
}

- (void)finishSettlingAtPageIfMotionIsAtRest:(NSInteger)page
{
  if ([self shouldDeferSettlingFinish]) {
    [self scheduleFinishSettlingAtRestingOffset];
    return;
  }
  [self finishSettlingAtPage:page];
}

- (void)finishSettlingAtCurrentOffsetIfNeeded
{
  if (_phase != RNPagerPhaseDragging && _phase != RNPagerPhaseSettling) return;
  NSInteger page = RNPagerClampPage(
      (NSInteger)llround([self currentOffset] / MAX([self pageExtent], 1)),
      _pages.count);
  [self finishSettlingAtPage:page];
}

- (void)finishSettlingAtPage:(NSInteger)page
{
  [self stopSettlingFinishWatcher];
  _nativeScrollAnimationActive = NO;
  _interruptedSettleVelocity = 0;
  _selectedPage = RNPagerClampPage(page, _pages.count);
  [self setCurrentOffset:_selectedPage * [self pageExtent]];
  [self transitionToPhase:(_pages.count == 0 ? RNPagerPhaseEmpty : RNPagerPhaseIdle)];
  [self publishState];
  if (_lastEmittedPage != _selectedPage) {
    _lastEmittedPage = _selectedPage;
    if (!_pageChangeEventsEnabled) return;
    if (self.pageChangeHandler == nil && self.onPageChange == nil) return;
    NSDictionary *change = @{ @"page" : @(_selectedPage) };
    if (self.pageChangeHandler != nil) self.pageChangeHandler(change);
    if (self.onPageChange != nil) self.onPageChange(change);
  }
}

- (void)transitionToPhase:(RNPagerPhase)phase
{
  _phase = _pages.count == 0 ? RNPagerPhaseEmpty : phase;
}

- (NSString *)phaseName
{
  switch (_phase) {
    case RNPagerPhaseDragging:
      return @"dragging";
    case RNPagerPhaseSettling:
      return @"settling";
    case RNPagerPhaseIdle:
      return @"idle";
    case RNPagerPhaseEmpty:
      return @"empty";
  }
}

- (NSString *)settlingSourceName
{
  if (_phase != RNPagerPhaseSettling) return @"none";
  switch (_settlingSource) {
    case RNPagerSettlingSourceProgrammatic:
      return @"programmatic";
    case RNPagerSettlingSourceRelease:
      return @"release";
    case RNPagerSettlingSourceNone:
      return @"none";
  }
}

- (NSInteger)currentSettledPage
{
  CGFloat extent = [self pageExtent];
  if (extent <= 0) return RNPagerClampPage(_selectedPage, _pages.count);
  return RNPagerClampPage((NSInteger)llround([self currentOffset] / extent), _pages.count);
}

- (void)publishState
{
  if (!_stateEventsEnabled) return;
  if (self.stateChangeHandler == nil && self.onStateChange == nil) return;
  NSDictionary *state = [self state];
  if (self.stateChangeHandler != nil) self.stateChangeHandler(state);
  if (self.onStateChange != nil) self.onStateChange(state);
}

- (void)publishPageScroll
{
  if (!_pageScrollEventsEnabled) return;
  if (self.pageScrollHandler == nil && self.onPageScroll == nil) return;
  NSDictionary *payload = [self state];
  if (self.pageScrollHandler != nil) self.pageScrollHandler(payload);
  if (self.onPageScroll != nil) self.onPageScroll(payload);
}

@end
