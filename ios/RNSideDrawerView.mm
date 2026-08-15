#import "RNSideDrawerView.h"

#import "RNSideDrawerContentView.h"
#import "RNSideDrawerPanelView.h"
#import "RNSideDrawerSlots.h"

#import <React/UIView+React.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>

typedef NS_ENUM(NSInteger, RNSideDrawerPhase) {
  RNSideDrawerPhaseClosed,
  RNSideDrawerPhaseOpen,
  RNSideDrawerPhaseDragging,
  RNSideDrawerPhaseSettling,
};

typedef NS_ENUM(NSInteger, RNSideDrawerSettlingSource) {
  RNSideDrawerSettlingSourceNone,
  RNSideDrawerSettlingSourceProgrammatic,
  RNSideDrawerSettlingSourceRelease,
};

@interface RNSideDrawerScrollView : UIScrollView
@property (nonatomic, copy, nullable) BOOL (^shouldBeginPan)(CGPoint location, CGPoint velocity);
@property (nonatomic, copy, nullable) BOOL (^shouldPassThroughPoint)(CGPoint point);
@end

@implementation RNSideDrawerScrollView

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
  if (gestureRecognizer == self.panGestureRecognizer && self.shouldBeginPan != nil) {
    UIView *viewport = self.superview ?: self;
    CGPoint location = [gestureRecognizer locationInView:viewport];
    CGPoint velocity = [self.panGestureRecognizer velocityInView:viewport];
    return self.shouldBeginPan(location, velocity);
  }
  return [super gestureRecognizerShouldBegin:gestureRecognizer];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
  CGPoint viewportPoint = self.superview == nil ? point : [self.superview convertPoint:point fromView:self];
  if (self.shouldPassThroughPoint != nil && self.shouldPassThroughPoint(viewportPoint)) return nil;
  return [super hitTest:point withEvent:event];
}

@end

@interface RNSideDrawerView () <UIScrollViewDelegate>
- (void)applyProgress:(CGFloat)progress;
- (void)finishAtOpen:(BOOL)open;
- (CGFloat)progress;
- (void)setOpen:(BOOL)open animated:(BOOL)animated source:(RNSideDrawerSettlingSource)source;
- (void)startAnimationToOpen:(BOOL)open;
- (void)stopAnimationAtPresentationOffset;
@end

@implementation RNSideDrawerView {
  RNSideDrawerScrollView *_scrollView;
  NSMutableArray<UIView *> *_slots;
  UIView<RNSideDrawerPanelSlot> *_panelView;
  UIView<RNSideDrawerContentSlot> *_contentView;
  RNSideDrawerPhase _phase;
  RNSideDrawerSettlingSource _settlingSource;
  UIViewPropertyAnimator *_snapAnimator;
  BOOL _nativeAnimationActive;
  BOOL _hasLaidOut;
  BOOL _open;
  BOOL _targetOpen;
  BOOL _lastEmittedOpen;
  NSInteger _revealDirection;
  CGFloat _laidOutDrawerWidth;
  BOOL _hasVelocitySample;
  CGFloat _lastOffsetSample;
  CFTimeInterval _lastOffsetSampleTime;
  CGFloat _physicalVelocity;
  CGFloat _interruptedRevealVelocity;
}

static CGFloat RNSideDrawerClamp(CGFloat value, CGFloat minimum, CGFloat maximum)
{
  return MIN(maximum, MAX(minimum, value));
}

static CGFloat RNSideDrawerProjectOffset(CGFloat offset, CGFloat velocity, CGFloat decelerationRate)
{
  if (!isfinite(velocity)) return offset;
  CGFloat rate = isfinite(decelerationRate) ? RNSideDrawerClamp(decelerationRate, 0, 0.999999) : UIScrollViewDecelerationRateNormal;
  return offset + velocity * rate / (1 - rate);
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if ((self = [super initWithFrame:frame])) {
    self.clipsToBounds = YES;
    _drawerWidth = 0;
    _edgeWidth = 24;
    _gestureEnabled = YES;
    _side = RNSideDrawerSideStart;
    _phase = RNSideDrawerPhaseClosed;
    _settlingSource = RNSideDrawerSettlingSourceNone;
    _revealDirection = 1;
    _slots = [NSMutableArray arrayWithCapacity:2];

    _scrollView = [[RNSideDrawerScrollView alloc] initWithFrame:self.bounds];
    _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scrollView.backgroundColor = UIColor.clearColor;
    _scrollView.bounces = NO;
    _scrollView.canCancelContentTouches = YES;
    _scrollView.decelerationRate = UIScrollViewDecelerationRateNormal;
    _scrollView.delaysContentTouches = NO;
    _scrollView.directionalLockEnabled = YES;
    _scrollView.delegate = self;
    _scrollView.showsHorizontalScrollIndicator = NO;
    _scrollView.showsVerticalScrollIndicator = NO;

    __weak RNSideDrawerView *weakSelf = self;
    _scrollView.shouldBeginPan = ^BOOL(CGPoint location, CGPoint velocity) {
      RNSideDrawerView *strongSelf = weakSelf;
      return strongSelf != nil && [strongSelf shouldBeginPanAtLocation:location velocity:velocity];
    };
    _scrollView.shouldPassThroughPoint = ^BOOL(CGPoint point) {
      RNSideDrawerView *strongSelf = weakSelf;
      return strongSelf != nil && [strongSelf shouldPassThroughPoint:point];
    };
    [super addSubview:_scrollView];
  }
  return self;
}

- (void)dealloc
{
  [_snapAnimator stopAnimation:YES];
  _snapAnimator = nil;
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  BOOL firstLayout = !_hasLaidOut;
  BOOL resumeSettling = _phase == RNSideDrawerPhaseSettling;
  BOOL targetOpen = _targetOpen;
  if (resumeSettling) [self stopAnimationAtPresentationOffset];
  CGFloat preservedProgress = firstLayout
      ? (_initialOpen ? 1 : 0)
      : [self progressForOffset:[self currentPhysicalOffset] width:_laidOutDrawerWidth direction:_revealDirection];

  _revealDirection = [self resolvedRevealDirection];
  _laidOutDrawerWidth = MAX(0, _drawerWidth);
  _scrollView.frame = self.bounds;

  CGFloat width = self.bounds.size.width;
  CGFloat height = self.bounds.size.height;
  if (_revealDirection > 0) {
    _panelView.frame = CGRectMake(0, 0, _laidOutDrawerWidth, height);
    _contentView.frame = CGRectMake(_laidOutDrawerWidth, 0, width, height);
  } else {
    _panelView.frame = CGRectMake(width - _laidOutDrawerWidth, 0, _laidOutDrawerWidth, height);
    _contentView.frame = CGRectMake(0, 0, width, height);
  }
  _scrollView.contentSize = CGSizeMake(width + _laidOutDrawerWidth, height);
  _hasLaidOut = YES;
  [self setProgress:preservedProgress];

  if (resumeSettling) {
    [self startAnimationToOpen:targetOpen];
  } else if (firstLayout) {
    _open = preservedProgress >= 1;
    _targetOpen = _open;
    _phase = _open ? RNSideDrawerPhaseOpen : RNSideDrawerPhaseClosed;
    _lastEmittedOpen = _open;
  }
}

- (void)setDrawerWidth:(CGFloat)drawerWidth
{
  CGFloat value = MAX(0, drawerWidth);
  if (_drawerWidth == value) return;
  _drawerWidth = value;
  [self setNeedsLayout];
}

- (void)setEdgeWidth:(CGFloat)edgeWidth
{
  _edgeWidth = MAX(0, edgeWidth);
}

- (void)setGestureEnabled:(BOOL)gestureEnabled
{
  if (_gestureEnabled == gestureEnabled) return;
  _gestureEnabled = gestureEnabled;
  _scrollView.scrollEnabled = gestureEnabled;
  if (!gestureEnabled && _phase == RNSideDrawerPhaseDragging) {
    [self setOpen:[self progress] >= 0.5 animated:YES source:RNSideDrawerSettlingSourceRelease];
  }
}

- (void)setInitialOpen:(BOOL)initialOpen
{
  _initialOpen = initialOpen;
  if (_hasLaidOut) return;
  _open = initialOpen;
  _targetOpen = initialOpen;
  _lastEmittedOpen = initialOpen;
  _phase = initialOpen ? RNSideDrawerPhaseOpen : RNSideDrawerPhaseClosed;
}

- (void)setSide:(RNSideDrawerSide)side
{
  if (_side == side) return;
  _side = side;
  [self setNeedsLayout];
}

- (void)mountSlot:(UIView *)slot atIndex:(NSInteger)index
{
  NSUInteger boundedIndex = MIN((NSUInteger)MAX(index, 0), _slots.count);
  [_slots insertObject:slot atIndex:boundedIndex];
  if ([slot conformsToProtocol:@protocol(RNSideDrawerPanelSlot)]) {
    _panelView = (UIView<RNSideDrawerPanelSlot> *)slot;
    [super insertSubview:slot belowSubview:_scrollView];
  } else if ([slot conformsToProtocol:@protocol(RNSideDrawerContentSlot)]) {
    _contentView = (UIView<RNSideDrawerContentSlot> *)slot;
    __weak RNSideDrawerView *weakSelf = self;
    _contentView.onScrimPress = ^{
      [weakSelf closeAnimated:YES];
    };
    [_scrollView addSubview:slot];
  }
  [self setNeedsLayout];
}

- (void)unmountSlot:(UIView *)slot
{
  [_slots removeObjectIdenticalTo:slot];
  if (slot == _panelView) _panelView = nil;
  if (slot == _contentView) {
    _contentView.onScrimPress = nil;
    _contentView = nil;
  }
  [slot removeFromSuperview];
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-missing-super-calls"
- (NSArray<UIView *> *)reactSubviews
{
  return [_slots copy];
}

- (void)insertReactSubview:(UIView *)subview atIndex:(NSInteger)atIndex
{
  [self mountSlot:subview atIndex:atIndex];
}

- (void)removeReactSubview:(UIView *)subview
{
  [self unmountSlot:subview];
}

- (void)didUpdateReactSubviews
{
}
#pragma clang diagnostic pop

- (void)openAnimated:(BOOL)animated
{
  [self setOpen:YES animated:animated source:RNSideDrawerSettlingSourceProgrammatic];
}

- (void)closeAnimated:(BOOL)animated
{
  [self setOpen:NO animated:animated source:RNSideDrawerSettlingSourceProgrammatic];
}

- (void)toggleAnimated:(BOOL)animated
{
  BOOL open = _phase == RNSideDrawerPhaseSettling ? !_targetOpen : [self progress] < 0.5;
  [self setOpen:open animated:animated source:RNSideDrawerSettlingSourceProgrammatic];
}

- (void)setOpen:(BOOL)open animated:(BOOL)animated source:(RNSideDrawerSettlingSource)source
{
  if (!_hasLaidOut) {
    _initialOpen = open;
    _targetOpen = open;
    _open = open;
    _phase = open ? RNSideDrawerPhaseOpen : RNSideDrawerPhaseClosed;
    [self setNeedsLayout];
    [self emitOpenChangeIfNeeded];
    return;
  }
  if (_phase == RNSideDrawerPhaseSettling) [self stopAnimationAtPresentationOffset];
  _targetOpen = open;
  _settlingSource = source;
  _phase = RNSideDrawerPhaseSettling;
  [self publishProgress];
  if (!animated || fabs([self progress] - (open ? 1 : 0)) <= 0.0001) {
    [self finishAtOpen:open];
    return;
  }
  [self startAnimationToOpen:open];
}

- (void)startAnimationToOpen:(BOOL)open
{
  if (fabs([self progress] - (open ? 1 : 0)) <= 0.0001) {
    [self finishAtOpen:open];
    return;
  }
  [_snapAnimator stopAnimation:YES];
  _snapAnimator = nil;
  _nativeAnimationActive = YES;
  CGFloat targetOffset = [self physicalOffsetForProgress:(open ? 1 : 0)];
  UISpringTimingParameters *timing = [[UISpringTimingParameters alloc] init];
  UIViewPropertyAnimator *animator = [[UIViewPropertyAnimator alloc] initWithDuration:0 timingParameters:timing];
  __weak RNSideDrawerView *weakSelf = self;
  __weak UIViewPropertyAnimator *weakAnimator = animator;
  [animator addAnimations:^{
    [weakSelf setPhysicalOffset:targetOffset];
  }];
  [animator addCompletion:^(__unused UIViewAnimatingPosition finalPosition) {
    RNSideDrawerView *strongSelf = weakSelf;
    UIViewPropertyAnimator *strongAnimator = weakAnimator;
    if (strongSelf == nil || strongSelf->_snapAnimator != strongAnimator) return;
    strongSelf->_snapAnimator = nil;
    strongSelf->_nativeAnimationActive = NO;
    [strongSelf finishAtOpen:open];
  }];
  _snapAnimator = animator;
  [animator startAnimation];
}

- (void)stopAnimationAtPresentationOffset
{
  CGFloat offset = [self presentationPhysicalOffset];
  [_snapAnimator stopAnimation:YES];
  _snapAnimator = nil;
  _nativeAnimationActive = NO;
  [_scrollView.layer removeAllAnimations];
  [self setPhysicalOffset:offset];
  _lastOffsetSample = offset;
  _lastOffsetSampleTime = CACurrentMediaTime();
  _hasVelocitySample = YES;
  _physicalVelocity = 0;
}

- (void)finishAtOpen:(BOOL)open
{
  [_snapAnimator stopAnimation:YES];
  _snapAnimator = nil;
  _nativeAnimationActive = NO;
  _interruptedRevealVelocity = 0;
  _open = open;
  _targetOpen = open;
  _settlingSource = RNSideDrawerSettlingSourceNone;
  _phase = open ? RNSideDrawerPhaseOpen : RNSideDrawerPhaseClosed;
  [self setProgress:(open ? 1 : 0)];
  [self publishProgress];
  [self emitOpenChangeIfNeeded];
}

- (void)prepareForRemoval
{
  [self stopAnimationAtPresentationOffset];
  _contentView.onScrimPress = nil;
  [_slots removeAllObjects];
  [_panelView removeFromSuperview];
  [_contentView removeFromSuperview];
  _panelView = nil;
  _contentView = nil;
  _hasLaidOut = NO;
  _open = NO;
  _targetOpen = NO;
  _phase = RNSideDrawerPhaseClosed;
  _settlingSource = RNSideDrawerSettlingSourceNone;
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
  (void)scrollView;
  BOOL interruptedTargetOpen = _phase == RNSideDrawerPhaseSettling ? _targetOpen : _open;
  CGFloat interruptedVelocity = _phase == RNSideDrawerPhaseSettling
      ? [self revealVelocityFromPhysicalVelocity:_physicalVelocity] / 1000
      : 0;
  if (_nativeAnimationActive) [self stopAnimationAtPresentationOffset];
  _targetOpen = interruptedTargetOpen;
  _interruptedRevealVelocity = interruptedVelocity;
  _settlingSource = RNSideDrawerSettlingSourceNone;
  _phase = RNSideDrawerPhaseDragging;
  [self publishProgress];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
  (void)scrollView;
  [self recordVelocitySample];
  [self applyProgress:[self progress]];
  [self publishProgress];
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView
                      withVelocity:(CGPoint)velocity
               targetContentOffset:(inout CGPoint *)targetContentOffset
{
  (void)scrollView;
  CGFloat naturalOffset = targetContentOffset->x;
  CGFloat naturalReveal = [self revealOffsetForPhysicalOffset:naturalOffset];
  naturalReveal = RNSideDrawerProjectOffset(
      naturalReveal,
      _interruptedRevealVelocity,
      _scrollView.decelerationRate);
  BOOL targetOpen = naturalReveal >= _laidOutDrawerWidth * 0.5;
  _targetOpen = targetOpen;
  _settlingSource = RNSideDrawerSettlingSourceRelease;
  _interruptedRevealVelocity = 0;
  _phase = RNSideDrawerPhaseSettling;
  targetContentOffset->x = [self physicalOffsetForProgress:(targetOpen ? 1 : 0)];
  targetContentOffset->y = 0;
  [self publishProgress];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
  (void)scrollView;
  if (_phase == RNSideDrawerPhaseDragging) {
    _targetOpen = [self progress] >= 0.5;
    _settlingSource = RNSideDrawerSettlingSourceRelease;
    _phase = RNSideDrawerPhaseSettling;
  }
  if (!decelerate) {
    CGFloat targetProgress = _targetOpen ? 1 : 0;
    if (fabs([self progress] - targetProgress) <= 0.0001) {
      [self finishAtOpen:_targetOpen];
    } else {
      [self startAnimationToOpen:_targetOpen];
    }
  }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
  (void)scrollView;
  if (_phase != RNSideDrawerPhaseSettling || _nativeAnimationActive) return;
  [self finishAtOpen:_targetOpen];
}

- (BOOL)shouldBeginPanAtLocation:(CGPoint)location velocity:(CGPoint)velocity
{
  if (!_gestureEnabled || _laidOutDrawerWidth <= 0) return NO;
  if (fabs(velocity.x) <= fabs(velocity.y)) return NO;
  CGFloat progress = [self progress];
  if (progress <= 0.001) {
    BOOL startsAtEdge = _revealDirection > 0
        ? location.x <= _edgeWidth
        : location.x >= self.bounds.size.width - _edgeWidth;
    return startsAtEdge && velocity.x * _revealDirection > 0;
  }
  if (progress >= 0.999 && velocity.x * _revealDirection >= 0) return NO;
  return [self pointIsOnContent:location progress:progress];
}

- (BOOL)shouldPassThroughPoint:(CGPoint)point
{
  CGFloat progress = [self progress];
  return progress > 0.001 && ![self pointIsOnContent:point progress:progress];
}

- (BOOL)pointIsOnContent:(CGPoint)point progress:(CGFloat)progress
{
  CGFloat reveal = progress * _laidOutDrawerWidth;
  return _revealDirection > 0
      ? point.x >= reveal
      : point.x <= self.bounds.size.width - reveal;
}

- (NSInteger)resolvedRevealDirection
{
  BOOL isRTL = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
  BOOL revealsLeft = (_side == RNSideDrawerSideStart) != isRTL;
  return revealsLeft ? 1 : -1;
}

- (CGFloat)progress
{
  return [self progressForOffset:[self currentPhysicalOffset] width:_laidOutDrawerWidth direction:_revealDirection];
}

- (CGFloat)progressForOffset:(CGFloat)offset width:(CGFloat)width direction:(NSInteger)direction
{
  if (width <= 0) return 0;
  CGFloat progress = direction > 0 ? 1 - offset / width : offset / width;
  return RNSideDrawerClamp(progress, 0, 1);
}

- (CGFloat)physicalOffsetForProgress:(CGFloat)progress
{
  CGFloat boundedProgress = RNSideDrawerClamp(progress, 0, 1);
  return _revealDirection > 0
      ? (1 - boundedProgress) * _laidOutDrawerWidth
      : boundedProgress * _laidOutDrawerWidth;
}

- (CGFloat)revealOffsetForPhysicalOffset:(CGFloat)offset
{
  return [self progressForOffset:offset width:_laidOutDrawerWidth direction:_revealDirection] * _laidOutDrawerWidth;
}

- (CGFloat)revealVelocityFromPhysicalVelocity:(CGFloat)velocity
{
  return _revealDirection > 0 ? -velocity : velocity;
}

- (CGFloat)currentPhysicalOffset
{
  return _scrollView.contentOffset.x;
}

- (CGFloat)presentationPhysicalOffset
{
  CALayer *presentationLayer = _scrollView.layer.presentationLayer;
  return presentationLayer == nil ? [self currentPhysicalOffset] : presentationLayer.bounds.origin.x;
}

- (void)setPhysicalOffset:(CGFloat)offset
{
  CGFloat boundedOffset = RNSideDrawerClamp(offset, 0, _laidOutDrawerWidth);
  _scrollView.contentOffset = CGPointMake(boundedOffset, 0);
}

- (void)setProgress:(CGFloat)progress
{
  [self setPhysicalOffset:[self physicalOffsetForProgress:progress]];
  [self applyProgress:RNSideDrawerClamp(progress, 0, 1)];
}

- (void)applyProgress:(CGFloat)progress
{
  [_contentView setDrawerProgress:progress];
  _panelView.userInteractionEnabled = progress > 0.001;
  if (progress <= 0.001) {
    _panelView.accessibilityElementsHidden = YES;
    _contentView.accessibilityElementsHidden = NO;
  } else if (progress >= 0.999) {
    _panelView.accessibilityElementsHidden = NO;
    _contentView.accessibilityElementsHidden = YES;
  } else {
    _panelView.accessibilityElementsHidden = NO;
    _contentView.accessibilityElementsHidden = NO;
  }
}

- (void)recordVelocitySample
{
  CFTimeInterval now = CACurrentMediaTime();
  CGFloat offset = [self currentPhysicalOffset];
  if (_hasVelocitySample && now > _lastOffsetSampleTime) {
    _physicalVelocity = (offset - _lastOffsetSample) / (now - _lastOffsetSampleTime);
  }
  _lastOffsetSample = offset;
  _lastOffsetSampleTime = now;
  _hasVelocitySample = YES;
}

- (NSString *)phaseName
{
  switch (_phase) {
    case RNSideDrawerPhaseClosed:
      return @"closed";
    case RNSideDrawerPhaseOpen:
      return @"open";
    case RNSideDrawerPhaseDragging:
      return @"dragging";
    case RNSideDrawerPhaseSettling:
      return @"settling";
  }
}

- (NSString *)settlingSourceName
{
  if (_phase != RNSideDrawerPhaseSettling) return @"none";
  switch (_settlingSource) {
    case RNSideDrawerSettlingSourceProgrammatic:
      return @"programmatic";
    case RNSideDrawerSettlingSourceRelease:
      return @"release";
    case RNSideDrawerSettlingSourceNone:
      return @"none";
  }
}

- (void)publishProgress
{
  if (!_progressEventsEnabled) return;
  if (self.progressHandler == nil && self.onProgress == nil) return;
  NSDictionary *payload = @{
    @"phase" : [self phaseName],
    @"progress" : @([self progress]),
    @"settlingSource" : [self settlingSourceName],
    @"targetOpen" : @(_targetOpen),
  };
  if (self.progressHandler != nil) self.progressHandler(payload);
  if (self.onProgress != nil) self.onProgress(payload);
}

- (void)emitOpenChangeIfNeeded
{
  if (_lastEmittedOpen == _open) return;
  _lastEmittedOpen = _open;
  if (!_openChangeEventsEnabled) return;
  if (self.openChangeHandler == nil && self.onOpenChange == nil) return;
  NSDictionary *payload = @{ @"open" : @(_open) };
  if (self.openChangeHandler != nil) self.openChangeHandler(payload);
  if (self.onOpenChange != nil) self.onOpenChange(payload);
}

@end
