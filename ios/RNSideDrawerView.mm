#import "RNSideDrawerView.h"

#import "RNSideDrawerContentView.h"
#import "RNSideDrawerPanelView.h"
#import "RNSideDrawerSlots.h"
#import "RNPagerDrawerHapticFeedback.h"

#import <React/UIView+React.h>
#import <QuartzCore/QuartzCore.h>
#include <array>
#include <float.h>
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
- (void)commitReleaseWithRevealVelocity:(CGFloat)revealVelocity;
- (CGFloat)directRawRevealForPresentation:(CGFloat)reveal;
- (CGFloat)directRevealForRawReveal:(CGFloat)reveal;
- (CGFloat)directVelocityScaleForRawReveal:(CGFloat)reveal;
- (void)finishAtOpen:(BOOL)open;
- (void)handleContactBegin;
- (void)pauseActiveSettle;
- (BOOL)prepareSettleToOpen:(BOOL)open
                    reveal:(CGFloat)reveal
                  velocity:(CGFloat)velocity
          allowsOvertravel:(BOOL)allowsOvertravel;
- (CGFloat)progress;
- (void)setPhysicalOffset:(CGFloat)offset allowingBounce:(BOOL)allowingBounce;
- (void)setOpen:(BOOL)open animated:(BOOL)animated source:(RNSideDrawerSettlingSource)source;
- (BOOL)shouldBeginPanWithVelocity:(CGPoint)velocity;
- (void)startSettleToOpen:(BOOL)open
           revealVelocity:(CGFloat)revealVelocity
         allowsOvertravel:(BOOL)allowsOvertravel;
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
  BOOL _gestureHapticTriggered;
  BOOL _gestureOriginOpen;
  BOOL _gestureReachedPositiveReveal;
  BOOL _dragHasReachedNonnegative;
  BOOL _settleAllowsOvertravel;
  BOOL _open;
  BOOL _targetOpen;
  BOOL _lastEmittedOpen;
  NSInteger _revealDirection;
  CGFloat _laidOutDrawerWidth;
  CGFloat _reveal;
  CGFloat _releaseRevealVelocity;
  CGFloat _dragRawReveal;
  CGFloat _dragStartRawReveal;
  CGFloat _dragStartTranslation;
  CGFloat _dragLowerBound;
  CGFloat _settleAngularFrequency;
  CGFloat _settleVelocity;
  CFTimeInterval _lastSettleTime;
  RNSideDrawerMotion _motion;
}

static const CGFloat RNSideDrawerMillisecondsPerSecond = 1000.0;
static const CGFloat RNSideDrawerSettleAngularFrequency = 4 * M_PI;
static const CGFloat RNSideDrawerSettleVelocityTolerance = 5;
static const CGFloat RNSideDrawerOvertravelLimit = 4;
// A release earns bounce only if its unrestricted critical trajectory carries six times the visible budget.
static const CGFloat RNSideDrawerOvertravelAdmissionExcursion = 24;

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

static CGFloat RNSideDrawerOutwardExcursion(
    CGFloat reveal, CGFloat velocity, CGFloat target, CGFloat angularFrequency)
{
  CGFloat outwardDirection = target > 0 ? 1 : -1;
  CGFloat displacement = reveal - target;
  CGFloat maximumExcursion = MAX(0, outwardDirection * displacement);
  CGFloat coefficient = velocity + angularFrequency * displacement;
  if (fabs(coefficient) <= DBL_EPSILON) return maximumExcursion;

  CGFloat extremumTime = velocity / (angularFrequency * coefficient);
  if (extremumTime <= 0 || !isfinite(extremumTime)) return maximumExcursion;
  CGFloat extremumDisplacement =
      (displacement + coefficient * extremumTime) * exp(-angularFrequency * extremumTime);
  return MAX(maximumExcursion, outwardDirection * extremumDisplacement);
}

static CGFloat RNSideDrawerSettleFrequency(
    CGFloat reveal, CGFloat velocity, CGFloat target, CGFloat allowedExcursion)
{
  CGFloat baseFrequency = RNSideDrawerSettleAngularFrequency;
  CGFloat outwardDirection = target > 0 ? 1 : -1;
  CGFloat currentExcursion = MAX(0, outwardDirection * (reveal - target));
  allowedExcursion = MAX(allowedExcursion, currentExcursion);
  CGFloat baseExcursion = RNSideDrawerOutwardExcursion(reveal, velocity, target, baseFrequency);
  if (baseExcursion <= allowedExcursion) return baseFrequency;

  CGFloat lowerFrequency = baseFrequency;
  CGFloat upperFrequency = baseFrequency * 2;
  while (RNSideDrawerOutwardExcursion(reveal, velocity, target, upperFrequency) > allowedExcursion &&
         upperFrequency < 1e6) {
    lowerFrequency = upperFrequency;
    upperFrequency *= 2;
  }
  for (NSUInteger iteration = 0; iteration < 32; iteration += 1) {
    CGFloat candidate = (lowerFrequency + upperFrequency) * 0.5;
    if (RNSideDrawerOutwardExcursion(reveal, velocity, target, candidate) > allowedExcursion) {
      lowerFrequency = candidate;
    } else {
      upperFrequency = candidate;
    }
  }
  return upperFrequency;
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
    _settleAngularFrequency = RNSideDrawerSettleAngularFrequency;
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
      [weakSelf handleContactBegin];
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
  BOOL resumeAllowsOvertravel = _settleAllowsOvertravel;
  CGFloat resumeVelocity = resumeSettling ? [self stopSettleAtCurrentPosition] : 0;
  CGFloat previousDrawerWidth = _laidOutDrawerWidth;
  CGFloat previousReveal = _reveal;

  _revealDirection = [self resolvedRevealDirection];
  _laidOutDrawerWidth = MAX(0, _drawerWidth);
  _scrollView.frame = self.bounds;

  CGFloat width = self.bounds.size.width;
  CGFloat height = self.bounds.size.height;
  _contactBackingView.bounds = CGRectMake(0, 0, width, height);
  _panelView.bounds = CGRectMake(0, 0, width, height);
  _contentView.bounds = CGRectMake(0, 0, width, height);
  if (firstLayout) {
    _reveal = _initialOpen ? _laidOutDrawerWidth : 0;
  } else if (previousReveal < 0) {
    _reveal = previousReveal;
  } else if (previousReveal > previousDrawerWidth) {
    _reveal = _laidOutDrawerWidth + previousReveal - previousDrawerWidth;
  } else if (previousDrawerWidth > 0) {
    _reveal = previousReveal / previousDrawerWidth * _laidOutDrawerWidth;
  } else {
    _reveal = _open ? _laidOutDrawerWidth : 0;
  }
  _scrollView.contentSize = CGSizeMake(width + _laidOutDrawerWidth, height);
  _hasLaidOut = YES;
  if (_phase == RNSideDrawerPhaseDragging) {
    _dragStartRawReveal = [self directRawRevealForPresentation:_reveal];
    _dragRawReveal = _dragStartRawReveal;
    _dragStartTranslation = [_scrollView.panGestureRecognizer translationInView:self].x * _revealDirection;
  }
  [self setPhysicalOffset:[self physicalOffsetForProgress:[self progress]] allowingBounce:NO];
  [self applyProgress:[self progress]];
  [self applyContentCorners];

  if (resumeSettling) {
    [self startSettleToOpen:targetOpen
             revealVelocity:resumeVelocity
           allowsOvertravel:resumeAllowsOvertravel];
  } else if (firstLayout) {
    _open = _initialOpen;
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
  [self startSettleToOpen:open revealVelocity:revealVelocity allowsOvertravel:NO];
}

- (void)startSettleToOpen:(BOOL)open
           revealVelocity:(CGFloat)revealVelocity
         allowsOvertravel:(BOOL)allowsOvertravel
{
  if (![self prepareSettleToOpen:open
                          reveal:_reveal
                        velocity:revealVelocity
                allowsOvertravel:allowsOvertravel]) {
    [self finishAtOpen:open];
    return;
  }
  [self startSettleDisplayLink];
}

- (BOOL)prepareSettleToOpen:(BOOL)open
                    reveal:(CGFloat)reveal
                  velocity:(CGFloat)velocity
          allowsOvertravel:(BOOL)allowsOvertravel
{
  CGFloat targetReveal = open ? _laidOutDrawerWidth : 0;
  UIScreen *screen = self.window.screen ?: UIScreen.mainScreen;
  CGFloat pixelTolerance = 1.0 / MAX(screen.scale, 1.0);
  CGFloat resolvedVelocity = isfinite(velocity) ? velocity : 0;
  _reveal = reveal;
  _settleVelocity = resolvedVelocity;
  _settleAllowsOvertravel = allowsOvertravel;
  CGFloat allowedExcursion = allowsOvertravel ? RNSideDrawerOvertravelLimit : pixelTolerance * 0.5;
  _settleAngularFrequency = RNSideDrawerSettleFrequency(reveal, resolvedVelocity, targetReveal, allowedExcursion);
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
  CGFloat velocity = _settleVelocity;
  _settleActive = NO;
  _settlePausedForTracking = NO;
  _settleAllowsOvertravel = NO;
  [self stopSettleDisplayLink];
  [self applyProgress:[self progress]];
  return velocity;
}

- (void)pauseActiveSettle
{
  if (!_settleActive || _settlePausedForTracking) return;
  [self advanceSettleToTime:CACurrentMediaTime()];
  [self applyProgress:[self progress]];
  _settleVelocity = 0;
  _settlePausedForTracking = YES;
  _lastSettleTime = MAX(_lastSettleTime, CACurrentMediaTime());
}

- (void)handleContactBegin
{
  [_hapticFeedback prepare];
  [self pauseActiveSettle];
}

- (void)finishAtOpen:(BOOL)open
{
  _settleActive = NO;
  _settlePausedForTracking = NO;
  _settleAllowsOvertravel = NO;
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
  _reveal = 0;
  _open = NO;
  _targetOpen = NO;
  _phase = RNSideDrawerPhaseClosed;
  _settlingSource = RNSideDrawerSettlingSourceNone;
}

- (BOOL)shouldBeginPanWithVelocity:(CGPoint)velocity
{
  if (!_gestureEnabled || _laidOutDrawerWidth <= 0) return NO;
  if (fabs(velocity.x) <= fabs(velocity.y)) return NO;
  CGFloat revealVelocity = velocity.x * _revealDirection;
  if (_reveal <= 0) return revealVelocity > 0;
  if (_reveal >= _laidOutDrawerWidth) return revealVelocity < 0;
  return YES;
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
  (void)scrollView;
  BOOL interruptedTargetOpen = _phase == RNSideDrawerPhaseSettling ? _targetOpen : _open;
  _gestureOriginOpen = interruptedTargetOpen;
  _gestureHapticTriggered = NO;
  if (_settleActive) [self stopSettleAtCurrentPosition];
  UIScreen *screen = self.window.screen ?: UIScreen.mainScreen;
  CGFloat pixelTolerance = 1.0 / MAX(screen.scale, 1.0);
  _gestureReachedPositiveReveal = _reveal > pixelTolerance;
  _dragStartRawReveal = [self directRawRevealForPresentation:_reveal];
  _dragRawReveal = _dragStartRawReveal;
  _dragStartTranslation = [_scrollView.panGestureRecognizer translationInView:self].x * _revealDirection;
  _dragLowerBound = MIN(_reveal, 0);
  _dragHasReachedNonnegative = _reveal >= 0;
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
  CGFloat offset = [self currentPhysicalOffset];
  if (_phase != RNSideDrawerPhaseDragging) {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self updateCountertrackedFramesForOffset:offset];
    [CATransaction commit];
    return;
  }
  CGFloat translation = [_scrollView.panGestureRecognizer translationInView:self].x * _revealDirection;
  CGFloat rawReveal = _dragStartRawReveal + translation - _dragStartTranslation;
  if (!_dragHasReachedNonnegative) {
    rawReveal = MAX(_dragLowerBound, rawReveal);
    if (rawReveal >= 0) _dragHasReachedNonnegative = YES;
  }
  if (_dragHasReachedNonnegative) rawReveal = MAX(0, rawReveal);
  _dragRawReveal = rawReveal;
  _reveal = rawReveal < 0 ? rawReveal : [self directRevealForRawReveal:rawReveal];
  if (_reveal > 0) _gestureReachedPositiveReveal = YES;
  [self applyProgress:[self progress]];
  [self publishProgress];
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView
                      withVelocity:(CGPoint)velocity
               targetContentOffset:(inout CGPoint *)targetContentOffset
{
  (void)scrollView;
  (void)velocity;
  CGFloat currentOffset = [self currentPhysicalOffset];
  CGFloat revealVelocity = [_scrollView.panGestureRecognizer velocityInView:self].x * _revealDirection;
  revealVelocity *= [self directVelocityScaleForRawReveal:_dragRawReveal];
  [self commitReleaseWithRevealVelocity:revealVelocity];
  targetContentOffset->x = currentOffset;
  targetContentOffset->y = 0;
  [self publishProgress];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
  (void)scrollView;
  (void)decelerate;
  if (_phase == RNSideDrawerPhaseDragging) {
    if (_scrollView.panGestureRecognizer.state == UIGestureRecognizerStateEnded) {
      CGFloat revealVelocity = [_scrollView.panGestureRecognizer velocityInView:self].x * _revealDirection;
      revealVelocity *= [self directVelocityScaleForRawReveal:_dragRawReveal];
      [self commitReleaseWithRevealVelocity:revealVelocity];
    } else {
      _targetOpen = [self progress] >= 0.5;
      _releaseRevealVelocity = 0;
      _settleAllowsOvertravel = NO;
      _settlingSource = RNSideDrawerSettlingSourceRelease;
      _phase = RNSideDrawerPhaseSettling;
    }
  }
  if (_phase != RNSideDrawerPhaseSettling) return;
  CGFloat offset = [self currentPhysicalOffset];
  BOOL shouldAnimate = [self prepareSettleToOpen:_targetOpen
                                         reveal:_reveal
                                       velocity:_releaseRevealVelocity
                               allowsOvertravel:_settleAllowsOvertravel];
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
  [self stopScrollMotionAtOffset:[self currentPhysicalOffset]];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
  (void)scrollView;
}

- (void)commitReleaseWithRevealVelocity:(CGFloat)revealVelocity
{
  CGFloat projectedReveal = RNSideDrawerProjectOffset(
      RNSideDrawerClamp(_reveal, 0, _laidOutDrawerWidth),
      revealVelocity / RNSideDrawerMillisecondsPerSecond,
      _scrollView.decelerationRate);
  BOOL targetOpen = projectedReveal >= _laidOutDrawerWidth * 0.5;
  if (targetOpen != _gestureOriginOpen && !_gestureHapticTriggered) {
    _gestureHapticTriggered = YES;
    [_hapticFeedback trigger];
  }
  CGFloat targetReveal = targetOpen ? _laidOutDrawerWidth : 0;
  CGFloat baseExcursion = RNSideDrawerOutwardExcursion(
      _reveal, revealVelocity, targetReveal, RNSideDrawerSettleAngularFrequency);
  _settleAllowsOvertravel = baseExcursion >= RNSideDrawerOvertravelAdmissionExcursion &&
      (targetOpen || _gestureReachedPositiveReveal);
  _releaseRevealVelocity = revealVelocity;
  _targetOpen = targetOpen;
  _settlingSource = RNSideDrawerSettlingSourceRelease;
  _phase = RNSideDrawerPhaseSettling;
}

- (NSInteger)resolvedRevealDirection
{
  BOOL isRTL = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
  BOOL revealsLeft = (_side == RNSideDrawerSideStart) != isRTL;
  return revealsLeft ? 1 : -1;
}

- (CGFloat)progress
{
  return RNSideDrawerClamp(_reveal / MAX(_laidOutDrawerWidth, 1), 0, 1);
}

- (CGFloat)physicalOffsetForProgress:(CGFloat)progress
{
  CGFloat boundedProgress = RNSideDrawerClamp(progress, 0, 1);
  CGFloat reveal = boundedProgress * _laidOutDrawerWidth;
  return _revealDirection > 0 ? _laidOutDrawerWidth - reveal : reveal;
}

- (CGFloat)directRevealForRawReveal:(CGFloat)reveal
{
  if (reveal <= _laidOutDrawerWidth) return MAX(0, reveal);
  CGFloat overtravel = reveal - _laidOutDrawerWidth;
  return _laidOutDrawerWidth + RNSideDrawerOvertravelLimit * tanh(overtravel / RNSideDrawerOvertravelLimit);
}

- (CGFloat)directRawRevealForPresentation:(CGFloat)reveal
{
  if (reveal <= _laidOutDrawerWidth) return reveal;
  CGFloat normalized = RNSideDrawerClamp(
      (reveal - _laidOutDrawerWidth) / RNSideDrawerOvertravelLimit, 0, 1 - 1e-6);
  return _laidOutDrawerWidth + RNSideDrawerOvertravelLimit * atanh(normalized);
}

- (CGFloat)directVelocityScaleForRawReveal:(CGFloat)reveal
{
  if (reveal <= _laidOutDrawerWidth) return 1;
  CGFloat normalized = tanh((reveal - _laidOutDrawerWidth) / RNSideDrawerOvertravelLimit);
  return 1 - normalized * normalized;
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
  if (_contentView != nil) {
    _contentView.center = CGPointMake(center.x + _revealDirection * _reveal, center.y);
  }
}

- (void)setProgress:(CGFloat)progress
{
  CGFloat boundedProgress = RNSideDrawerClamp(progress, 0, 1);
  _reveal = boundedProgress * _laidOutDrawerWidth;
  [self setPhysicalOffset:[self physicalOffsetForProgress:boundedProgress]];
  [self applyProgress:boundedProgress];
}

- (void)applyProgress:(CGFloat)progress
{
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  [self updateCountertrackedFramesForOffset:[self currentPhysicalOffset]];

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
  CGFloat displacement = _reveal - target;
  CGFloat coefficient = _settleVelocity + _settleAngularFrequency * displacement;
  CGFloat decay = exp(-_settleAngularFrequency * elapsed);
  _reveal = target + (displacement + coefficient * elapsed) * decay;
  _settleVelocity = (_settleVelocity - _settleAngularFrequency * coefficient * elapsed) * decay;
  _lastSettleTime = time;
}

- (void)startSettleDisplayLink
{
  [self stopSettleDisplayLink];
  _settleDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(stepSettleDisplayLink:)];
  if (@available(iOS 15.0, *)) {
    NSInteger maximumFramesPerSecond = (self.window.screen ?: UIScreen.mainScreen).maximumFramesPerSecond;
    Float64 preferred = MIN(120, maximumFramesPerSecond);
    Float64 minimum = MIN(80, preferred);
    _settleDisplayLink.preferredFrameRateRange = CAFrameRateRangeMake(minimum, preferred, preferred);
  }
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
  [self applyProgress:[self progress]];
  [self publishProgress];
  UIScreen *screen = self.window.screen ?: UIScreen.mainScreen;
  CGFloat pixelTolerance = 1.0 / MAX(screen.scale, 1.0);
  CGFloat target = _targetOpen ? _laidOutDrawerWidth : 0;
  if (fabs(_reveal - target) <= pixelTolerance &&
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
