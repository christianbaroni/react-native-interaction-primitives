#import "RNSideDrawerView.h"

#import "RNSideDrawerContentView.h"
#import "RNSideDrawerPanelView.h"
#import "RNSideDrawerSlots.h"
#import "RNPagerDrawerHapticFeedback.h"

#import <React/UIView+React.h>
#import <QuartzCore/QuartzCore.h>
#include <array>
#import <math.h>
#include <vector>

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

typedef NS_ENUM(NSUInteger, RNSideDrawerMotionChannel) {
  RNSideDrawerMotionDrawerOpacity,
  RNSideDrawerMotionDrawerScale,
  RNSideDrawerMotionDrawerTranslateX,
  RNSideDrawerMotionDrawerTranslateY,
  RNSideDrawerMotionContentOpacity,
  RNSideDrawerMotionContentScale,
  RNSideDrawerMotionContentTranslateX,
  RNSideDrawerMotionContentTranslateY,
  RNSideDrawerMotionOverlayOpacity,
  RNSideDrawerMotionChannelCount,
};

struct RNSideDrawerMotionSegment {
  CGFloat upperInput;
  CGFloat slope;
  CGFloat intercept;
};

struct RNSideDrawerInterpolation {
  bool enabled{false};
  CGFloat firstInput{0};
  CGFloat firstOutput{0};
  CGFloat lastInput{0};
  CGFloat lastOutput{0};
  std::vector<RNSideDrawerMotionSegment> segments;

  CGFloat evaluate(CGFloat progress, CGFloat fallback) const
  {
    if (!enabled) return fallback;
    if (progress <= firstInput) return firstOutput;
    if (progress >= lastInput) return lastOutput;
    for (const auto &segment : segments) {
      if (progress <= segment.upperInput) return segment.slope * progress + segment.intercept;
    }
    return lastOutput;
  }
};

using RNSideDrawerMotion = std::array<RNSideDrawerInterpolation, RNSideDrawerMotionChannelCount>;

@interface RNSideDrawerScrollView : UIScrollView
@property (nonatomic, copy, nullable) dispatch_block_t didBeginContact;
@property (nonatomic, copy, nullable) BOOL (^shouldBeginPan)(CGPoint velocity);
@end

@implementation RNSideDrawerScrollView

- (BOOL)touchesShouldBegin:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event inContentView:(UIView *)view
{
  if (self.didBeginContact != nil) self.didBeginContact();
  return [super touchesShouldBegin:touches withEvent:event inContentView:view];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
  if (gestureRecognizer == self.panGestureRecognizer && self.shouldBeginPan != nil) {
    return self.shouldBeginPan([self.panGestureRecognizer velocityInView:self]);
  }
  return [super gestureRecognizerShouldBegin:gestureRecognizer];
}

@end

@interface RNSideDrawerView () <UIScrollViewDelegate>
- (void)applyProgress:(CGFloat)progress;
- (void)applyContentCorners;
- (void)advanceSettleToTime:(CFTimeInterval)time;
- (void)finishAtOpen:(BOOL)open;
- (CGFloat)physicalOffsetForRawReveal:(CGFloat)reveal;
- (void)pauseActiveSettle;
- (BOOL)prepareSettleToOpen:(BOOL)open reveal:(CGFloat)reveal velocity:(CGFloat)velocity;
- (CGFloat)progress;
- (CGFloat)rawRevealForPhysicalOffset:(CGFloat)offset;
- (void)setPhysicalOffset:(CGFloat)offset allowingBounce:(BOOL)allowingBounce;
- (void)setOpen:(BOOL)open animated:(BOOL)animated source:(RNSideDrawerSettlingSource)source;
- (BOOL)shouldBeginPanWithVelocity:(CGPoint)velocity;
- (void)startSettleToOpen:(BOOL)open revealVelocity:(CGFloat)revealVelocity;
- (void)startSettleDisplayLink;
- (void)stopScrollMotionAtOffset:(CGFloat)offset;
- (CGFloat)stopSettleAtCurrentPosition;
- (void)stopSettleDisplayLink;
- (void)updateCountertrackedFramesForOffset:(CGFloat)offset;
@end

@implementation RNSideDrawerView {
  RNSideDrawerScrollView *_scrollView;
  UIView *_contactBackingView;
  NSMutableArray<UIView *> *_slots;
  UIView<RNSideDrawerPanelSlot> *_panelView;
  UIView<RNSideDrawerContentSlot> *_contentView;
  RNSideDrawerPhase _phase;
  RNSideDrawerSettlingSource _settlingSource;
  CADisplayLink *_settleDisplayLink;
  RNPagerDrawerHapticFeedback *_hapticFeedback;
  BOOL _settleActive;
  BOOL _settlePausedForTracking;
  BOOL _hasLaidOut;
  BOOL _open;
  BOOL _targetOpen;
  BOOL _lastEmittedOpen;
  NSInteger _revealDirection;
  CGFloat _laidOutDrawerWidth;
  CGFloat _releaseRevealVelocity;
  CGFloat _settleReveal;
  CGFloat _settleVelocity;
  CFTimeInterval _lastSettleTime;
  RNSideDrawerMotion _motion;
}

static const CGFloat RNSideDrawerMillisecondsPerSecond = 1000.0;
static const CGFloat RNSideDrawerSettleAngularFrequency = 4 * M_PI;
static const CGFloat RNSideDrawerSettleVelocityTolerance = 5;

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

static CGFloat RNSideDrawerScreenCornerRadius(UIScreen *screen)
{
  static NSString *cornerRadiusKey;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSArray<NSString *> *components = @[ @"Radius", @"Corner", @"display", @"_" ];
    cornerRadiusKey = [[[components reverseObjectEnumerator] allObjects] componentsJoinedByString:@""];
  });

  @try {
    id value = [screen valueForKey:cornerRadiusKey];
    return [value respondsToSelector:@selector(doubleValue)] ? MAX(0, [value doubleValue]) : 0;
  } @catch (__unused NSException *exception) {
    return 0;
  }
}

static RNSideDrawerMotion RNSideDrawerCompileMotion(NSArray<NSNumber *> *config)
{
  RNSideDrawerMotion motion{};
  if (config.count < RNSideDrawerMotionChannelCount) return motion;

  NSUInteger cursor = RNSideDrawerMotionChannelCount;
  for (NSUInteger channelIndex = 0; channelIndex < RNSideDrawerMotionChannelCount; channelIndex += 1) {
    double rawPointCount = config[channelIndex].doubleValue;
    NSUInteger pointCount = rawPointCount >= 0 ? (NSUInteger)rawPointCount : NSNotFound;
    if (!isfinite(rawPointCount) || rawPointCount != pointCount || pointCount == 1 || cursor + pointCount * 2 > config.count) {
      return RNSideDrawerMotion{};
    }
    if (pointCount == 0) continue;

    RNSideDrawerInterpolation &interpolation = motion[channelIndex];
    interpolation.enabled = true;
    interpolation.firstInput = config[cursor].doubleValue;
    interpolation.firstOutput = config[cursor + 1].doubleValue;
    interpolation.lastInput = interpolation.firstInput;
    interpolation.lastOutput = interpolation.firstOutput;
    if (!isfinite(interpolation.firstInput) || !isfinite(interpolation.firstOutput) || interpolation.firstInput < 0 ||
        interpolation.firstInput > 1) {
      return RNSideDrawerMotion{};
    }

    CGFloat previousInput = interpolation.firstInput;
    CGFloat previousOutput = interpolation.firstOutput;
    cursor += 2;
    interpolation.segments.reserve(pointCount - 1);
    for (NSUInteger pointIndex = 1; pointIndex < pointCount; pointIndex += 1) {
      CGFloat input = config[cursor].doubleValue;
      CGFloat output = config[cursor + 1].doubleValue;
      if (!isfinite(input) || !isfinite(output) || input <= previousInput || input > 1) return RNSideDrawerMotion{};
      CGFloat slope = (output - previousOutput) / (input - previousInput);
      interpolation.segments.push_back({input, slope, previousOutput - slope * previousInput});
      interpolation.lastInput = input;
      interpolation.lastOutput = output;
      previousInput = input;
      previousOutput = output;
      cursor += 2;
    }
  }
  return cursor == config.count ? motion : RNSideDrawerMotion{};
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if ((self = [super initWithFrame:frame])) {
    self.clipsToBounds = YES;
    _contentCornerRadius = -1;
    _motionConfig = @[];
    _overlayColor = UIColor.clearColor;
    _drawerWidth = 0;
    _gestureEnabled = YES;
    _side = RNSideDrawerSideStart;
    _phase = RNSideDrawerPhaseClosed;
    _settlingSource = RNSideDrawerSettlingSourceNone;
    _revealDirection = 1;
    _slots = [NSMutableArray arrayWithCapacity:2];

    _scrollView = [[RNSideDrawerScrollView alloc] initWithFrame:self.bounds];
    _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scrollView.backgroundColor = UIColor.clearColor;
    _scrollView.alwaysBounceHorizontal = YES;
    _scrollView.bounces = YES;
    _scrollView.canCancelContentTouches = YES;
    _scrollView.decelerationRate = UIScrollViewDecelerationRateFast;
    _scrollView.delaysContentTouches = NO;
    _scrollView.directionalLockEnabled = YES;
    _scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    _scrollView.delegate = self;
    _scrollView.showsHorizontalScrollIndicator = NO;
    _scrollView.showsVerticalScrollIndicator = NO;

    __weak RNSideDrawerView *weakSelf = self;
    _scrollView.didBeginContact = ^{
      [weakSelf pauseActiveSettle];
    };
    _scrollView.shouldBeginPan = ^BOOL(CGPoint velocity) {
      RNSideDrawerView *strongSelf = weakSelf;
      return strongSelf != nil && [strongSelf shouldBeginPanWithVelocity:velocity];
    };
    [super addSubview:_scrollView];

    _contactBackingView = [[UIView alloc] initWithFrame:self.bounds];
    _contactBackingView.backgroundColor = UIColor.clearColor;
    _contactBackingView.isAccessibilityElement = NO;
    [_scrollView addSubview:_contactBackingView];
  }
  return self;
}

- (void)dealloc
{
  [self stopSettleDisplayLink];
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  BOOL firstLayout = !_hasLaidOut;
  BOOL resumeSettling = _phase == RNSideDrawerPhaseSettling;
  BOOL targetOpen = _targetOpen;
  CGFloat resumeVelocity = resumeSettling ? [self stopSettleAtCurrentPosition] : 0;
  CGFloat preservedProgress = firstLayout
      ? (_initialOpen ? 1 : 0)
      : [self rawProgressForOffset:[self currentPhysicalOffset] width:_laidOutDrawerWidth direction:_revealDirection];

  _revealDirection = [self resolvedRevealDirection];
  _laidOutDrawerWidth = MAX(0, _drawerWidth);
  _scrollView.frame = self.bounds;

  CGFloat width = self.bounds.size.width;
  CGFloat height = self.bounds.size.height;
  _contactBackingView.bounds = CGRectMake(0, 0, width, height);
  _panelView.bounds = CGRectMake(0, 0, width, height);
  _contentView.bounds = CGRectMake(0, 0, width, height);
  if (_revealDirection > 0) {
    _contentView.center = CGPointMake(_laidOutDrawerWidth + width * 0.5, height * 0.5);
  } else {
    _contentView.center = CGPointMake(width * 0.5, height * 0.5);
  }
  _scrollView.contentSize = CGSizeMake(width + _laidOutDrawerWidth, height);
  _hasLaidOut = YES;
  CGFloat preservedOffset = _revealDirection > 0
      ? (1 - preservedProgress) * _laidOutDrawerWidth
      : preservedProgress * _laidOutDrawerWidth;
  [self setPhysicalOffset:preservedOffset allowingBounce:YES];
  [self applyProgress:RNSideDrawerClamp(preservedProgress, 0, 1)];
  [self applyContentCorners];

  if (resumeSettling) {
    [self startSettleToOpen:targetOpen revealVelocity:resumeVelocity];
  } else if (firstLayout) {
    _open = preservedProgress >= 1;
    _targetOpen = _open;
    _phase = _open ? RNSideDrawerPhaseOpen : RNSideDrawerPhaseClosed;
    _lastEmittedOpen = _open;
  }
}

- (void)didMoveToWindow
{
  [super didMoveToWindow];
  [self applyContentCorners];
}

- (void)setContentCornerRadius:(CGFloat)contentCornerRadius
{
  if (_contentCornerRadius == contentCornerRadius) return;
  _contentCornerRadius = contentCornerRadius;
  [self applyContentCorners];
}

- (void)setDrawerWidth:(CGFloat)drawerWidth
{
  CGFloat value = MAX(0, drawerWidth);
  if (_drawerWidth == value) return;
  _drawerWidth = value;
  [self setNeedsLayout];
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

- (void)setGestureReleaseHaptic:(NSString *)gestureReleaseHaptic
{
  if (gestureReleaseHaptic.length == 0 || [gestureReleaseHaptic isEqualToString:@"none"]) {
    _hapticFeedback = nil;
    return;
  }
  if (_hapticFeedback == nil) _hapticFeedback = [RNPagerDrawerHapticFeedback new];
  _hapticFeedback.type = gestureReleaseHaptic;
}

- (NSString *)gestureReleaseHaptic
{
  return _hapticFeedback.type ?: @"none";
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

- (void)setMotionConfig:(NSArray<NSNumber *> *)motionConfig
{
  _motionConfig = [motionConfig copy];
  _motion = RNSideDrawerCompileMotion(_motionConfig);
  if (_hasLaidOut) [self applyProgress:[self progress]];
}

- (void)setOverlayColor:(UIColor *)overlayColor
{
  _overlayColor = overlayColor ?: UIColor.clearColor;
  [_contentView setDrawerOverlayColor:_overlayColor];
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
    [_scrollView insertSubview:slot aboveSubview:_contactBackingView];
  } else if ([slot conformsToProtocol:@protocol(RNSideDrawerContentSlot)]) {
    _contentView = (UIView<RNSideDrawerContentSlot> *)slot;
    __weak RNSideDrawerView *weakSelf = self;
    _contentView.onScrimPress = ^{
      [weakSelf closeAnimated:YES];
    };
    [_scrollView addSubview:slot];
    [_contentView setDrawerOverlayColor:_overlayColor];
    [self applyContentCorners];
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
  CGFloat revealVelocity = _phase == RNSideDrawerPhaseSettling ? [self stopSettleAtCurrentPosition] : 0;
  _targetOpen = open;
  _settlingSource = source;
  _phase = RNSideDrawerPhaseSettling;
  [self publishProgress];
  if (!animated) {
    [self finishAtOpen:open];
    return;
  }
  [self startSettleToOpen:open revealVelocity:revealVelocity];
}

- (void)startSettleToOpen:(BOOL)open revealVelocity:(CGFloat)revealVelocity
{
  CGFloat currentReveal = [self rawRevealForPhysicalOffset:[self currentPhysicalOffset]];
  if (![self prepareSettleToOpen:open reveal:currentReveal velocity:revealVelocity]) {
    [self finishAtOpen:open];
    return;
  }
  [self startSettleDisplayLink];
}

- (BOOL)prepareSettleToOpen:(BOOL)open reveal:(CGFloat)reveal velocity:(CGFloat)velocity
{
  CGFloat targetReveal = open ? _laidOutDrawerWidth : 0;
  UIScreen *screen = self.window.screen ?: UIScreen.mainScreen;
  CGFloat pixelTolerance = 1.0 / MAX(screen.scale, 1.0);
  CGFloat resolvedVelocity = isfinite(velocity) ? velocity : 0;
  _settleReveal = reveal;
  _settleVelocity = resolvedVelocity;
  _lastSettleTime = CACurrentMediaTime();
  _settlePausedForTracking = NO;
  _settleActive = YES;
  return fabs(reveal - targetReveal) > pixelTolerance ||
      fabs(resolvedVelocity) > RNSideDrawerSettleVelocityTolerance;
}

- (CGFloat)stopSettleAtCurrentPosition
{
  if (!_settleActive) return 0;
  if (!_scrollView.tracking && !_settlePausedForTracking) [self advanceSettleToTime:CACurrentMediaTime()];
  CGFloat reveal = _settleReveal;
  CGFloat velocity = _settleVelocity;
  _settleActive = NO;
  _settlePausedForTracking = NO;
  [self stopSettleDisplayLink];
  CGFloat offset = [self physicalOffsetForRawReveal:reveal];
  [self setPhysicalOffset:offset allowingBounce:YES];
  return velocity;
}

- (void)pauseActiveSettle
{
  if (!_settleActive || _settlePausedForTracking) return;
  _settleVelocity = 0;
  _settlePausedForTracking = YES;
  _lastSettleTime = MAX(_lastSettleTime, CACurrentMediaTime());
}

- (void)finishAtOpen:(BOOL)open
{
  _settleActive = NO;
  _settlePausedForTracking = NO;
  [self stopSettleDisplayLink];
  _settleVelocity = 0;
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
  [self stopSettleAtCurrentPosition];
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

- (BOOL)shouldBeginPanWithVelocity:(CGPoint)velocity
{
  if (!_gestureEnabled || _laidOutDrawerWidth <= 0) return NO;
  if (fabs(velocity.x) <= fabs(velocity.y)) return NO;
  CGFloat rawProgress = [self rawProgressForOffset:[self currentPhysicalOffset]
                                             width:_laidOutDrawerWidth
                                         direction:_revealDirection];
  if (_phase == RNSideDrawerPhaseSettling || rawProgress < 0 || rawProgress > 1) return YES;
  CGFloat revealVelocity = velocity.x * _revealDirection;
  if (rawProgress <= 0.001) return revealVelocity > 0;
  if (rawProgress >= 0.999) return revealVelocity < 0;
  return YES;
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
  (void)scrollView;
  BOOL interruptedTargetOpen = _phase == RNSideDrawerPhaseSettling ? _targetOpen : _open;
  if (_settleActive) [self stopSettleAtCurrentPosition];
  _targetOpen = interruptedTargetOpen;
  _releaseRevealVelocity = 0;
  _settlingSource = RNSideDrawerSettlingSourceNone;
  _phase = RNSideDrawerPhaseDragging;
  [_hapticFeedback prepare];
  [self publishProgress];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
  (void)scrollView;
  if (_settleActive) return;
  CGFloat offset = [self currentPhysicalOffset];
  [self updateCountertrackedFramesForOffset:offset];
  [self applyProgress:[self progress]];
  [self publishProgress];
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView
                      withVelocity:(CGPoint)velocity
               targetContentOffset:(inout CGPoint *)targetContentOffset
{
  (void)scrollView;
  CGFloat naturalReveal = [self revealOffsetForPhysicalOffset:targetContentOffset->x];
  BOOL targetOpen = naturalReveal >= _laidOutDrawerWidth * 0.5;
  CGFloat currentOffset = [self currentPhysicalOffset];
  CGFloat physicalVelocity = velocity.x * RNSideDrawerMillisecondsPerSecond;
  _releaseRevealVelocity = [self revealVelocityFromPhysicalVelocity:physicalVelocity];
  _targetOpen = targetOpen;
  _settlingSource = RNSideDrawerSettlingSourceRelease;
  _phase = RNSideDrawerPhaseSettling;
  [_hapticFeedback trigger];
  targetContentOffset->x = currentOffset;
  targetContentOffset->y = 0;
  [self publishProgress];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
  (void)scrollView;
  (void)decelerate;
  if (_phase == RNSideDrawerPhaseDragging) {
    CGFloat revealVelocity = [_scrollView.panGestureRecognizer velocityInView:self].x * _revealDirection;
    CGFloat reveal = [self rawRevealForPhysicalOffset:[self currentPhysicalOffset]];
    CGFloat naturalReveal = RNSideDrawerProjectOffset(
        reveal,
        revealVelocity / RNSideDrawerMillisecondsPerSecond,
        _scrollView.decelerationRate);
    _targetOpen = naturalReveal >= _laidOutDrawerWidth * 0.5;
    _releaseRevealVelocity = revealVelocity;
    _settlingSource = RNSideDrawerSettlingSourceRelease;
    _phase = RNSideDrawerPhaseSettling;
    if (_scrollView.panGestureRecognizer.state == UIGestureRecognizerStateEnded) {
      [_hapticFeedback trigger];
    }
  }
  if (_phase != RNSideDrawerPhaseSettling) return;
  CGFloat offset = [self currentPhysicalOffset];
  CGFloat reveal = [self rawRevealForPhysicalOffset:offset];
  BOOL shouldAnimate = [self prepareSettleToOpen:_targetOpen reveal:reveal velocity:_releaseRevealVelocity];
  [self stopScrollMotionAtOffset:offset];
  if (shouldAnimate) {
    [self startSettleDisplayLink];
  } else {
    [self finishAtOpen:_targetOpen];
  }
}

- (void)scrollViewWillBeginDecelerating:(UIScrollView *)scrollView
{
  (void)scrollView;
  if (!_settleActive) return;
  [self stopScrollMotionAtOffset:[self physicalOffsetForRawReveal:_settleReveal]];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
  (void)scrollView;
}

- (NSInteger)resolvedRevealDirection
{
  BOOL isRTL = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
  BOOL revealsLeft = (_side == RNSideDrawerSideStart) != isRTL;
  return revealsLeft ? 1 : -1;
}

- (CGFloat)progress
{
  return RNSideDrawerClamp(
      [self rawRevealForPhysicalOffset:[self currentPhysicalOffset]] / MAX(_laidOutDrawerWidth, 1), 0, 1);
}

- (CGFloat)rawProgressForOffset:(CGFloat)offset width:(CGFloat)width direction:(NSInteger)direction
{
  if (width <= 0) return 0;
  return direction > 0 ? 1 - offset / width : offset / width;
}

- (CGFloat)physicalOffsetForProgress:(CGFloat)progress
{
  CGFloat boundedProgress = RNSideDrawerClamp(progress, 0, 1);
  return [self physicalOffsetForRawReveal:boundedProgress * _laidOutDrawerWidth];
}

- (CGFloat)physicalOffsetForRawReveal:(CGFloat)reveal
{
  return _revealDirection > 0 ? _laidOutDrawerWidth - reveal : reveal;
}

- (CGFloat)revealOffsetForPhysicalOffset:(CGFloat)offset
{
  return RNSideDrawerClamp([self rawRevealForPhysicalOffset:offset], 0, _laidOutDrawerWidth);
}

- (CGFloat)rawRevealForPhysicalOffset:(CGFloat)offset
{
  return _revealDirection > 0 ? _laidOutDrawerWidth - offset : offset;
}

- (CGFloat)revealVelocityFromPhysicalVelocity:(CGFloat)velocity
{
  return _revealDirection > 0 ? -velocity : velocity;
}

- (CGFloat)currentPhysicalOffset
{
  return _scrollView.contentOffset.x;
}

- (void)setPhysicalOffset:(CGFloat)offset
{
  [self setPhysicalOffset:offset allowingBounce:NO];
}

- (void)setPhysicalOffset:(CGFloat)offset allowingBounce:(BOOL)allowingBounce
{
  CGFloat resolvedOffset = allowingBounce ? offset : RNSideDrawerClamp(offset, 0, _laidOutDrawerWidth);
  _scrollView.contentOffset = CGPointMake(resolvedOffset, 0);
  [self updateCountertrackedFramesForOffset:resolvedOffset];
}

- (void)stopScrollMotionAtOffset:(CGFloat)offset
{
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  if (@available(iOS 17.4, *)) {
    [_scrollView stopScrollingAndZooming];
  } else {
    _scrollView.scrollEnabled = NO;
    _scrollView.scrollEnabled = _gestureEnabled;
  }
  [self setPhysicalOffset:offset allowingBounce:YES];
  [CATransaction commit];
}

- (void)updateCountertrackedFramesForOffset:(CGFloat)offset
{
  CGPoint center = CGPointMake(offset + self.bounds.size.width * 0.5, self.bounds.size.height * 0.5);
  _contactBackingView.center = center;
  if (_panelView != nil) _panelView.center = center;
}

- (void)setProgress:(CGFloat)progress
{
  [self setPhysicalOffset:[self physicalOffsetForProgress:progress]];
  [self applyProgress:RNSideDrawerClamp(progress, 0, 1)];
}

- (void)applyProgress:(CGFloat)progress
{
  [CATransaction begin];
  [CATransaction setDisableActions:YES];

  CGFloat drawerOpacity = _motion[RNSideDrawerMotionDrawerOpacity].evaluate(progress, 1);
  CGFloat drawerScale = _motion[RNSideDrawerMotionDrawerScale].evaluate(progress, 1);
  CGFloat drawerTranslateX = _motion[RNSideDrawerMotionDrawerTranslateX].evaluate(progress, 0);
  CGFloat drawerTranslateY = _motion[RNSideDrawerMotionDrawerTranslateY].evaluate(progress, 0);
  CGFloat boundedDrawerOpacity = RNSideDrawerClamp(drawerOpacity, 0, 1);
  CGAffineTransform drawerTransform =
      CGAffineTransformMake(drawerScale, 0, 0, drawerScale, drawerTranslateX, drawerTranslateY);
  if (_panelView.alpha != boundedDrawerOpacity) _panelView.alpha = boundedDrawerOpacity;
  if (!CGAffineTransformEqualToTransform(_panelView.transform, drawerTransform)) _panelView.transform = drawerTransform;

  CGFloat contentOpacity = _motion[RNSideDrawerMotionContentOpacity].evaluate(progress, 1);
  CGFloat contentScale = _motion[RNSideDrawerMotionContentScale].evaluate(progress, 1);
  CGFloat contentTranslateX = _motion[RNSideDrawerMotionContentTranslateX].evaluate(progress, 0);
  CGFloat contentTranslateY = _motion[RNSideDrawerMotionContentTranslateY].evaluate(progress, 0);
  CGFloat boundedContentOpacity = RNSideDrawerClamp(contentOpacity, 0, 1);
  CGAffineTransform contentTransform =
      CGAffineTransformMake(contentScale, 0, 0, contentScale, contentTranslateX, contentTranslateY);
  if (_contentView.alpha != boundedContentOpacity) _contentView.alpha = boundedContentOpacity;
  if (!CGAffineTransformEqualToTransform(_contentView.transform, contentTransform)) {
    _contentView.transform = contentTransform;
  }
  [_contentView setDrawerOverlayOpacity:_motion[RNSideDrawerMotionOverlayOpacity].evaluate(progress, 0)];

  [CATransaction commit];
  [_contentView setDrawerProgress:progress];
  BOOL panelEnabled = _phase != RNSideDrawerPhaseClosed;
  if (_panelView.userInteractionEnabled != panelEnabled) _panelView.userInteractionEnabled = panelEnabled;
  if (progress <= 0.001) {
    if (!_panelView.accessibilityElementsHidden) _panelView.accessibilityElementsHidden = YES;
    if (_contentView.accessibilityElementsHidden) _contentView.accessibilityElementsHidden = NO;
  } else if (progress >= 0.999) {
    if (_panelView.accessibilityElementsHidden) _panelView.accessibilityElementsHidden = NO;
    if (!_contentView.accessibilityElementsHidden) _contentView.accessibilityElementsHidden = YES;
  } else {
    if (_panelView.accessibilityElementsHidden) _panelView.accessibilityElementsHidden = NO;
    if (_contentView.accessibilityElementsHidden) _contentView.accessibilityElementsHidden = NO;
  }
}

- (void)applyContentCorners
{
  if (_contentView == nil) return;
  UIScreen *screen = self.window.screen ?: UIScreen.mainScreen;
  CGFloat radius = _contentCornerRadius >= 0 ? _contentCornerRadius : RNSideDrawerScreenCornerRadius(screen);
  _contentView.layer.cornerCurve = kCACornerCurveContinuous;
  _contentView.layer.cornerRadius = radius;
  _contentView.layer.masksToBounds = radius > 0;
}

- (void)advanceSettleToTime:(CFTimeInterval)time
{
  if (!_settleActive || time <= _lastSettleTime) return;
  CFTimeInterval elapsed = time - _lastSettleTime;
  CGFloat target = _targetOpen ? _laidOutDrawerWidth : 0;
  CGFloat displacement = _settleReveal - target;
  CGFloat coefficient = _settleVelocity + RNSideDrawerSettleAngularFrequency * displacement;
  CGFloat decay = exp(-RNSideDrawerSettleAngularFrequency * elapsed);
  _settleReveal = target + (displacement + coefficient * elapsed) * decay;
  _settleVelocity = (_settleVelocity - RNSideDrawerSettleAngularFrequency * coefficient * elapsed) * decay;
  _lastSettleTime = time;
}

- (void)startSettleDisplayLink
{
  [self stopSettleDisplayLink];
  _settleDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(stepSettleDisplayLink:)];
  [_settleDisplayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stopSettleDisplayLink
{
  [_settleDisplayLink invalidate];
  _settleDisplayLink = nil;
}

- (void)stepSettleDisplayLink:(CADisplayLink *)displayLink
{
  if (!_settleActive || _phase != RNSideDrawerPhaseSettling) {
    [self stopSettleDisplayLink];
    return;
  }
  if (_scrollView.tracking) {
    [self pauseActiveSettle];
    _lastSettleTime = displayLink.targetTimestamp;
    return;
  }
  _settlePausedForTracking = NO;
  [self advanceSettleToTime:displayLink.targetTimestamp];
  [self setPhysicalOffset:[self physicalOffsetForRawReveal:_settleReveal] allowingBounce:YES];
  CGFloat progress = RNSideDrawerClamp(_settleReveal / MAX(_laidOutDrawerWidth, 1), 0, 1);
  [self applyProgress:progress];
  [self publishProgress];
  UIScreen *screen = self.window.screen ?: UIScreen.mainScreen;
  CGFloat pixelTolerance = 1.0 / MAX(screen.scale, 1.0);
  CGFloat target = _targetOpen ? _laidOutDrawerWidth : 0;
  if (fabs(_settleReveal - target) <= pixelTolerance &&
      fabs(_settleVelocity) <= RNSideDrawerSettleVelocityTolerance) {
    [self finishAtOpen:_targetOpen];
  }
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
