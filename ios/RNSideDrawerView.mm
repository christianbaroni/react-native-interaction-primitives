#import "RNSideDrawerView.h"

#import "RNSideDrawerContentView.h"
#import "RNSideDrawerPanelView.h"
#import "RNSideDrawerSlots.h"
#import "RNPagerDrawerHapticFeedback.h"

#import <React/UIView+React.h>
#import <QuartzCore/QuartzCore.h>
#include <algorithm>
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
  RNSideDrawerMotionContentBorderOpacity,
  RNSideDrawerMotionContentShadowOpacity,
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
    auto segment = std::lower_bound(
        segments.begin(),
        segments.end(),
        progress,
        [](const RNSideDrawerMotionSegment &candidate, CGFloat value) {
          return candidate.upperInput < value;
        });
    return segment->slope * progress + segment->intercept;
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

@interface RNSideDrawerContentPresentationView : UIView
@end

@implementation RNSideDrawerContentPresentationView

- (nullable UIView *)hitTest:(CGPoint)point withEvent:(nullable UIEvent *)event
{
  UIView *view = [super hitTest:point withEvent:event];
  return view == self ? nil : view;
}

@end

@interface RNSideDrawerBorderLayer : CALayer
@end

@implementation RNSideDrawerBorderLayer

- (nullable id<CAAction>)actionForKey:(NSString *)event
{
  (void)event;
  return nil;
}

@end

@interface RNSideDrawerView () <UIScrollViewDelegate>
- (void)applyContentReveal:(CGFloat)reveal;
- (void)applyMotionProgress:(CGFloat)progress;
- (void)applyProgress:(CGFloat)progress;
- (void)applyContentCorners;
- (void)applySettlingInteractionState;
- (void)advanceSettleToTime:(CFTimeInterval)time;
- (void)cancelActiveDragAtOffset:(CGFloat)offset;
- (void)commitReleaseWithRevealVelocity:(CGFloat)revealVelocity targetOpen:(BOOL)targetOpen;
- (CGFloat)directRawRevealForPresentation:(CGFloat)reveal;
- (CGFloat)directRevealForRawReveal:(CGFloat)reveal;
- (void)finishAtOpen:(BOOL)open;
- (void)handlePanGesture:(UIPanGestureRecognizer *)panGestureRecognizer;
- (void)handleContactBegin;
- (void)pauseActiveSettle;
- (BOOL)prepareSettleToOpen:(BOOL)open
                    reveal:(CGFloat)reveal
                  velocity:(CGFloat)velocity;
- (CGFloat)presentationReveal;
- (CGFloat)progress;
- (void)publishProgressForReveal:(CGFloat)reveal;
- (CGFloat)releaseRevealVelocity;
- (CGFloat)revealFromContentCenter;
- (void)setOpen:(BOOL)open animated:(BOOL)animated source:(RNSideDrawerSettlingSource)source;
- (BOOL)shouldBeginPanWithVelocity:(CGPoint)velocity;
- (void)startSettleToOpen:(BOOL)open
           revealVelocity:(CGFloat)revealVelocity;
- (void)startPreparedSettleAnimatorToOpen:(BOOL)open;
- (void)startSettleDisplayLink;
- (void)stopScrollMotionAtOffset:(CGFloat)offset;
- (CGFloat)stopSettleAtCurrentPosition;
- (void)stopSettleDisplayLink;
- (void)updateSettleDisplayLink;
- (void)updateContentBorderColor;
- (void)updateContentShadowColor;
- (void)updateCountertrackedFramesForOffset:(CGFloat)offset;
- (void)updateRevealFromPanGesture;
@end

@implementation RNSideDrawerView {
  RNSideDrawerScrollView *_scrollView;
  UIView *_contactBackingView;
  RNSideDrawerContentPresentationView *_contentPresentationView;
  UIView *_contentHostView;
  RNSideDrawerBorderLayer *_contentBorderLayer;
  NSMutableArray<UIView *> *_slots;
  UIView<RNSideDrawerPanelSlot> *_panelView;
  UIView<RNSideDrawerContentSlot> *_contentView;
  RNSideDrawerPhase _phase;
  RNSideDrawerSettlingSource _settlingSource;
  UIViewPropertyAnimator *_settleAnimator;
  CADisplayLink *_settleDisplayLink;
  RNPagerDrawerHapticFeedback *_hapticFeedback;
  BOOL _settleActive;
  BOOL _settlePausedForTracking;
  BOOL _hasLaidOut;
  BOOL _gestureHapticTriggered;
  BOOL _gestureOriginOpen;
  BOOL _progressSnapshotPending;
  BOOL _suppressCurrentDragRelease;
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
  CGFloat _settleVelocity;
  CFTimeInterval _lastSettleTime;
  RNSideDrawerMotion _motion;
}

static const CGFloat RNSideDrawerSettleAngularFrequency = 7 * M_PI;
static const CGFloat RNSideDrawerOvertravelLimit = 4;
static const CGFloat RNSideDrawerMillisecondsPerSecond = 1000;

static CGFloat RNSideDrawerClamp(CGFloat value, CGFloat minimum, CGFloat maximum)
{
  return MIN(maximum, MAX(minimum, value));
}

static CGFloat RNSideDrawerPresentedReleaseVelocity(CGFloat rawReveal, CGFloat upperBound, CGFloat velocity)
{
  if (!isfinite(velocity)) return 0;
  if (rawReveal >= 0 && rawReveal <= upperBound) return velocity;
  CGFloat boundary = rawReveal < 0 ? 0 : upperBound;
  CGFloat normalized = tanh((rawReveal - boundary) / RNSideDrawerOvertravelLimit);
  return velocity * (1 - normalized * normalized);
}

static CGFloat RNSideDrawerProjectedReveal(
    CGFloat reveal, CGFloat velocityPointsPerSecond, CGFloat upperBound, CGFloat decelerationRate)
{
  CGFloat rate = isfinite(decelerationRate)
      ? RNSideDrawerClamp(decelerationRate, 0, 0.999999)
      : UIScrollViewDecelerationRateNormal;
  CGFloat boundedReveal = RNSideDrawerClamp(reveal, 0, upperBound);
  if (!isfinite(velocityPointsPerSecond)) return boundedReveal;
  CGFloat velocityPointsPerMillisecond = velocityPointsPerSecond / RNSideDrawerMillisecondsPerSecond;
  return boundedReveal + velocityPointsPerMillisecond * rate / (1 - rate);
}

static BOOL RNSideDrawerReleaseTargetsOpen(
    CGFloat reveal, CGFloat velocityPointsPerSecond, CGFloat upperBound, CGFloat decelerationRate)
{
  return RNSideDrawerProjectedReveal(reveal, velocityPointsPerSecond, upperBound, decelerationRate) >=
      upperBound * 0.5;
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

static CGFloat RNSideDrawerBoundedSettleVelocity(
    CGFloat reveal, CGFloat velocity, CGFloat target, CGFloat allowedExcursion)
{
  CGFloat outwardDirection = target > 0 ? 1 : -1;
  CGFloat currentExcursion = MAX(0, outwardDirection * (reveal - target));
  allowedExcursion = MAX(allowedExcursion, currentExcursion);
  if (RNSideDrawerOutwardExcursion(reveal, velocity, target, RNSideDrawerSettleAngularFrequency) <= allowedExcursion) {
    return velocity;
  }

  CGFloat lowerScale = 0;
  CGFloat upperScale = 1;
  for (NSUInteger iteration = 0; iteration < 32; iteration += 1) {
    CGFloat candidateScale = (lowerScale + upperScale) * 0.5;
    CGFloat candidateVelocity = velocity * candidateScale;
    if (RNSideDrawerOutwardExcursion(
            reveal, candidateVelocity, target, RNSideDrawerSettleAngularFrequency) > allowedExcursion) {
      upperScale = candidateScale;
    } else {
      lowerScale = candidateScale;
    }
  }
  return velocity * lowerScale;
}

static bool RNSideDrawerHasMotion(const RNSideDrawerMotion &motion)
{
  for (const auto &interpolation : motion) {
    if (interpolation.enabled) return true;
  }
  return false;
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
    _contentBorderColor = UIColor.clearColor;
    _contentBorderWidth = 0;
    _contentShadowColor = UIColor.clearColor;
    _contentShadowOffsetX = 0;
    _contentShadowOffsetY = 0;
    _contentShadowRadius = 0;
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
    _scrollView.alwaysBounceHorizontal = NO;
    _scrollView.bounces = NO;
    _scrollView.canCancelContentTouches = YES;
    _scrollView.decelerationRate = UIScrollViewDecelerationRateNormal;
    _scrollView.delaysContentTouches = NO;
    _scrollView.directionalLockEnabled = YES;
    _scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    _scrollView.delegate = self;
    _scrollView.showsHorizontalScrollIndicator = NO;
    _scrollView.showsVerticalScrollIndicator = NO;
    [_scrollView.panGestureRecognizer addTarget:self action:@selector(handlePanGesture:)];

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

    _contentPresentationView = [[RNSideDrawerContentPresentationView alloc] initWithFrame:self.bounds];
    _contentPresentationView.backgroundColor = UIColor.clearColor;
    _contentPresentationView.clipsToBounds = NO;
    _contentPresentationView.isAccessibilityElement = NO;
    _contentPresentationView.layer.masksToBounds = NO;
    _contentPresentationView.layer.shadowOffset = CGSizeZero;
    _contentPresentationView.layer.shadowOpacity = 1;
    _contentPresentationView.layer.shadowRadius = 0;
    [_scrollView addSubview:_contentPresentationView];

    _contentHostView = [[UIView alloc] initWithFrame:_contentPresentationView.bounds];
    _contentHostView.backgroundColor = UIColor.clearColor;
    _contentHostView.clipsToBounds = YES;
    _contentHostView.isAccessibilityElement = NO;
    [_contentPresentationView addSubview:_contentHostView];

    _contentBorderLayer = [RNSideDrawerBorderLayer layer];
    _contentBorderLayer.borderWidth = _contentBorderWidth;
    [_contentHostView.layer addSublayer:_contentBorderLayer];
    [self updateContentBorderColor];
    [self updateContentShadowColor];
  }
  return self;
}

- (void)dealloc
{
  [_settleAnimator stopAnimation:YES];
  [self stopSettleDisplayLink];
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  BOOL firstLayout = !_hasLaidOut;
  BOOL resumeSettling = _phase == RNSideDrawerPhaseSettling;
  BOOL resumePaused = _settlePausedForTracking;
  BOOL targetOpen = _targetOpen;
  CGFloat resumeVelocity = resumeSettling ? [self stopSettleAtCurrentPosition] : 0;
  CGFloat previousDrawerWidth = _laidOutDrawerWidth;
  CGFloat previousReveal = _reveal;
  CGFloat previousRawReveal = _dragRawReveal;

  _revealDirection = [self resolvedRevealDirection];
  _laidOutDrawerWidth = MAX(0, _drawerWidth);
  _scrollView.frame = self.bounds;

  CGFloat width = self.bounds.size.width;
  CGFloat height = self.bounds.size.height;
  _contactBackingView.bounds = CGRectMake(0, 0, width, height);
  _panelView.bounds = CGRectMake(0, 0, width, height);
  _contentPresentationView.bounds = CGRectMake(0, 0, width, height);
  _contentHostView.frame = _contentPresentationView.bounds;
  _contentBorderLayer.frame = _contentHostView.bounds;
  _contentView.frame = _contentHostView.bounds;
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
    if (previousRawReveal < 0) {
      _dragRawReveal = previousRawReveal;
    } else if (previousRawReveal > previousDrawerWidth) {
      _dragRawReveal = _laidOutDrawerWidth + previousRawReveal - previousDrawerWidth;
    } else if (previousDrawerWidth > 0) {
      _dragRawReveal = previousRawReveal / previousDrawerWidth * _laidOutDrawerWidth;
    } else {
      _dragRawReveal = [self directRawRevealForPresentation:_reveal];
    }
    _reveal = [self directRevealForRawReveal:_dragRawReveal];
    _dragStartRawReveal = _dragRawReveal;
    _dragStartTranslation = [_scrollView.panGestureRecognizer translationInView:self].x * _revealDirection;
  }
  [self setPhysicalOffset:[self physicalOffsetForProgress:[self progress]]];
  [self applyProgress:[self progress]];
  [self applyContentCorners];

  if (resumeSettling) {
    if (resumePaused) {
      _settleActive = YES;
      _settlePausedForTracking = YES;
      _settleVelocity = 0;
      [self startSettleDisplayLink];
    } else {
      [self startSettleToOpen:targetOpen revealVelocity:resumeVelocity];
    }
  } else if (firstLayout) {
    _open = _initialOpen;
    _targetOpen = _open;
    _phase = _open ? RNSideDrawerPhaseOpen : RNSideDrawerPhaseClosed;
    _lastEmittedOpen = _open;
  }
  [self flushPendingProgressSnapshot];
}

- (void)didMoveToWindow
{
  [super didMoveToWindow];
  [self applyContentCorners];
  [self updateContentBorderColor];
  [self updateContentShadowColor];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
  [super traitCollectionDidChange:previousTraitCollection];
  if (previousTraitCollection == nil ||
      [self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
    [self updateContentBorderColor];
    [self updateContentShadowColor];
  }
}

- (void)setContentBorderColor:(UIColor *)contentBorderColor
{
  _contentBorderColor = contentBorderColor ?: UIColor.clearColor;
  [self updateContentBorderColor];
}

- (void)setContentBorderWidth:(CGFloat)contentBorderWidth
{
  _contentBorderWidth = isfinite(contentBorderWidth) ? MAX(0, contentBorderWidth) : 0;
  _contentBorderLayer.borderWidth = _contentBorderWidth;
}

- (void)setContentCornerRadius:(CGFloat)contentCornerRadius
{
  if (_contentCornerRadius == contentCornerRadius) return;
  _contentCornerRadius = contentCornerRadius;
  [self applyContentCorners];
}

- (void)setContentShadowColor:(UIColor *)contentShadowColor
{
  _contentShadowColor = contentShadowColor ?: UIColor.clearColor;
  [self updateContentShadowColor];
}

- (void)setContentShadowOffsetX:(CGFloat)contentShadowOffsetX
{
  CGFloat value = isfinite(contentShadowOffsetX) ? contentShadowOffsetX : 0;
  if (_contentShadowOffsetX == value) return;
  _contentShadowOffsetX = value;
  _contentPresentationView.layer.shadowOffset = CGSizeMake(value, _contentShadowOffsetY);
}

- (void)setContentShadowOffsetY:(CGFloat)contentShadowOffsetY
{
  CGFloat value = isfinite(contentShadowOffsetY) ? contentShadowOffsetY : 0;
  if (_contentShadowOffsetY == value) return;
  _contentShadowOffsetY = value;
  _contentPresentationView.layer.shadowOffset = CGSizeMake(_contentShadowOffsetX, value);
}

- (void)setContentShadowRadius:(CGFloat)contentShadowRadius
{
  CGFloat value = isfinite(contentShadowRadius) ? MAX(0, contentShadowRadius) : 0;
  if (_contentShadowRadius == value) return;
  _contentShadowRadius = value;
  _contentPresentationView.layer.shadowRadius = value;
  [self updateContentShadowColor];
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
  if (!gestureEnabled && _phase == RNSideDrawerPhaseDragging) {
    [self setOpen:[self progress] >= 0.5 animated:YES source:RNSideDrawerSettlingSourceRelease];
  } else {
    _scrollView.scrollEnabled = gestureEnabled;
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
  if (!_hasLaidOut) return;
  if (_phase == RNSideDrawerPhaseSettling) {
    CGFloat reveal = [self presentationReveal];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self applyMotionProgress:RNSideDrawerClamp(reveal / MAX(_laidOutDrawerWidth, 1), 0, 1)];
    [CATransaction commit];
  } else {
    [self applyProgress:[self progress]];
  }
  [self updateSettleDisplayLink];
}

- (void)setProgressEventsEnabled:(BOOL)progressEventsEnabled
{
  if (_progressEventsEnabled == progressEventsEnabled) return;
  _progressEventsEnabled = progressEventsEnabled;
  _progressSnapshotPending = progressEventsEnabled;
  [self updateSettleDisplayLink];
}

- (void)didSetProps:(NSArray<NSString *> *)changedProps
{
  (void)changedProps;
  [self flushPendingProgressSnapshot];
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
    slot.frame = _contentHostView.bounds;
    [_contentHostView addSubview:slot];
    [_contentHostView.layer addSublayer:_contentBorderLayer];
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
  if ((_phase == RNSideDrawerPhaseOpen && open) || (_phase == RNSideDrawerPhaseClosed && !open)) return;
  if (animated && _phase == RNSideDrawerPhaseSettling && _targetOpen == open) return;
  CGFloat revealVelocity = _phase == RNSideDrawerPhaseSettling ? [self stopSettleAtCurrentPosition] : 0;
  BOOL cancelActiveDrag = _phase == RNSideDrawerPhaseDragging;
  if (cancelActiveDrag) {
    [self updateRevealFromPanGesture];
    [self applyProgress:[self progress]];
    _suppressCurrentDragRelease = YES;
  }
  _targetOpen = open;
  _settlingSource = source;
  _phase = RNSideDrawerPhaseSettling;
  if (cancelActiveDrag) {
    [self cancelActiveDragAtOffset:[self physicalOffsetForProgress:[self progress]]];
    [self applyProgress:[self progress]];
  }
  [self publishProgress];
  if (!animated) {
    [self finishAtOpen:open];
    return;
  }
  [self startSettleToOpen:open revealVelocity:revealVelocity];
}

- (void)startSettleToOpen:(BOOL)open
           revealVelocity:(CGFloat)revealVelocity
{
  if (![self prepareSettleToOpen:open reveal:_reveal velocity:revealVelocity]) {
    [self finishAtOpen:open];
    return;
  }
  [self startPreparedSettleAnimatorToOpen:open];
}

- (void)startPreparedSettleAnimatorToOpen:(BOOL)open
{
  [self applySettlingInteractionState];
  CGFloat targetReveal = open ? _laidOutDrawerWidth : 0;
  CGFloat distance = targetReveal - _reveal;
  CGFloat normalizedVelocity = fabs(distance) > DBL_EPSILON ? _settleVelocity / distance : 0;
  UISpringTimingParameters *timing = [[UISpringTimingParameters alloc]
      initWithMass:1
         stiffness:RNSideDrawerSettleAngularFrequency * RNSideDrawerSettleAngularFrequency
           damping:2 * RNSideDrawerSettleAngularFrequency
   initialVelocity:CGVectorMake(normalizedVelocity, 0)];
  UIViewPropertyAnimator *animator = [[UIViewPropertyAnimator alloc] initWithDuration:0 timingParameters:timing];
  animator.interruptible = YES;
  animator.userInteractionEnabled = YES;
  animator.manualHitTestingEnabled = NO;
  if (@available(iOS 26.0, *)) animator.flushUpdates = YES;

  __weak RNSideDrawerView *weakSelf = self;
  __weak UIViewPropertyAnimator *weakAnimator = animator;
  [animator addAnimations:^{
    RNSideDrawerView *strongSelf = weakSelf;
    if (strongSelf == nil) return;
    [strongSelf applyContentReveal:targetReveal];
  }];
  [animator addCompletion:^(__unused UIViewAnimatingPosition finalPosition) {
    RNSideDrawerView *strongSelf = weakSelf;
    UIViewPropertyAnimator *strongAnimator = weakAnimator;
    if (strongSelf == nil || strongSelf->_settleAnimator != strongAnimator) return;
    strongSelf->_settleAnimator = nil;
    [strongSelf finishAtOpen:open];
  }];
  _settleAnimator = animator;
  [self updateSettleDisplayLink];
  [animator startAnimation];
  _lastSettleTime = CACurrentMediaTime();
}

- (BOOL)prepareSettleToOpen:(BOOL)open
                    reveal:(CGFloat)reveal
                  velocity:(CGFloat)velocity
{
  CGFloat targetReveal = open ? _laidOutDrawerWidth : 0;
  UIScreen *screen = self.window.screen ?: UIScreen.mainScreen;
  CGFloat pixelTolerance = 1.0 / MAX(screen.scale, 1.0);
  CGFloat resolvedVelocity = isfinite(velocity) ? velocity : 0;
  _reveal = reveal;
  if (fabs(reveal - targetReveal) <= pixelTolerance) {
    _settleVelocity = 0;
    _settlePausedForTracking = NO;
    _settleActive = NO;
    return NO;
  }
  _settleVelocity =
      RNSideDrawerBoundedSettleVelocity(reveal, resolvedVelocity, targetReveal, RNSideDrawerOvertravelLimit);
  _lastSettleTime = CACurrentMediaTime();
  _settlePausedForTracking = NO;
  _settleActive = YES;
  return YES;
}

- (CGFloat)stopSettleAtCurrentPosition
{
  if (!_settleActive) return 0;
  if (!_scrollView.tracking && !_settlePausedForTracking) [self advanceSettleToTime:CACurrentMediaTime()];
  CGFloat velocity = _settleVelocity;
  [_settleAnimator stopAnimation:YES];
  _settleAnimator = nil;
  _reveal = [self revealFromContentCenter];
  _settleActive = NO;
  _settlePausedForTracking = NO;
  [self stopSettleDisplayLink];
  [self applyProgress:[self progress]];
  return velocity;
}

- (void)pauseActiveSettle
{
  if (!_settleActive || _settlePausedForTracking) return;
  (void)[self stopSettleAtCurrentPosition];
  _settleVelocity = 0;
  _settlePausedForTracking = YES;
  _settleActive = YES;
  _lastSettleTime = CACurrentMediaTime();
  [self startSettleDisplayLink];
}

- (void)handleContactBegin
{
  [_hapticFeedback prepare];
  [self pauseActiveSettle];
}

- (void)finishAtOpen:(BOOL)open
{
  [_settleAnimator stopAnimation:YES];
  _settleAnimator = nil;
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
  _reveal = 0;
  _open = NO;
  _targetOpen = NO;
  _phase = RNSideDrawerPhaseClosed;
  _settlingSource = RNSideDrawerSettlingSourceNone;
  _progressSnapshotPending = NO;
  _suppressCurrentDragRelease = NO;
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
  _suppressCurrentDragRelease = NO;
  BOOL interruptedTargetOpen = _phase == RNSideDrawerPhaseSettling ? _targetOpen : _open;
  _gestureOriginOpen = interruptedTargetOpen;
  _gestureHapticTriggered = NO;
  if (_settleActive) [self stopSettleAtCurrentPosition];
  _dragStartRawReveal = [self directRawRevealForPresentation:_reveal];
  _dragRawReveal = _dragStartRawReveal;
  _dragStartTranslation = [_scrollView.panGestureRecognizer translationInView:self].x * _revealDirection;
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
  CGFloat previousReveal = _reveal;
  [self updateRevealFromPanGesture];
  if (_reveal != previousReveal) {
    [self applyProgress:[self progress]];
    [self publishProgress];
  } else {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self applyContentReveal:_reveal];
    [CATransaction commit];
  }
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView
                      withVelocity:(CGPoint)velocity
               targetContentOffset:(inout CGPoint *)targetContentOffset
{
  (void)scrollView;
  (void)velocity;
  if (_suppressCurrentDragRelease) {
    targetContentOffset->x = [self currentPhysicalOffset];
    targetContentOffset->y = 0;
    return;
  }
  [self updateRevealFromPanGesture];
  [self applyProgress:[self progress]];
  CGFloat revealVelocity = [self releaseRevealVelocity];
  BOOL targetOpen = RNSideDrawerReleaseTargetsOpen(
      _reveal, revealVelocity, _laidOutDrawerWidth, _scrollView.decelerationRate);
  CGFloat currentOffset = [self currentPhysicalOffset];
  [self commitReleaseWithRevealVelocity:revealVelocity targetOpen:targetOpen];
  targetContentOffset->x = currentOffset;
  targetContentOffset->y = 0;
  [self publishProgress];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
  (void)scrollView;
  (void)decelerate;
  if (_suppressCurrentDragRelease) return;
  if (_phase == RNSideDrawerPhaseDragging) {
    [self updateRevealFromPanGesture];
    [self applyProgress:[self progress]];
    if (_scrollView.panGestureRecognizer.state == UIGestureRecognizerStateEnded) {
      CGFloat revealVelocity = [self releaseRevealVelocity];
      BOOL targetOpen = RNSideDrawerReleaseTargetsOpen(
          _reveal, revealVelocity, _laidOutDrawerWidth, _scrollView.decelerationRate);
      [self commitReleaseWithRevealVelocity:revealVelocity targetOpen:targetOpen];
    } else {
      _targetOpen = [self progress] >= 0.5;
      _releaseRevealVelocity = 0;
      _settlingSource = RNSideDrawerSettlingSourceRelease;
      _phase = RNSideDrawerPhaseSettling;
    }
    [self publishProgress];
  }
  if (_phase != RNSideDrawerPhaseSettling) return;
  CGFloat offset = [self currentPhysicalOffset];
  BOOL shouldAnimate = [self prepareSettleToOpen:_targetOpen
                                         reveal:_reveal
                                       velocity:_releaseRevealVelocity];
  [self stopScrollMotionAtOffset:offset];
  if (shouldAnimate) {
    [self startPreparedSettleAnimatorToOpen:_targetOpen];
  } else {
    [self finishAtOpen:_targetOpen];
  }
}

- (void)scrollViewWillBeginDecelerating:(UIScrollView *)scrollView
{
  (void)scrollView;
  if (_suppressCurrentDragRelease) {
    [self stopScrollMotionAtOffset:[self currentPhysicalOffset]];
    return;
  }
  if (!_settleActive) return;
  [self stopScrollMotionAtOffset:[self currentPhysicalOffset]];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
  (void)scrollView;
}

- (void)commitReleaseWithRevealVelocity:(CGFloat)revealVelocity targetOpen:(BOOL)targetOpen
{
  if (targetOpen != _gestureOriginOpen && !_gestureHapticTriggered) {
    _gestureHapticTriggered = YES;
    [_hapticFeedback trigger];
  }
  _releaseRevealVelocity = revealVelocity;
  _targetOpen = targetOpen;
  _settlingSource = RNSideDrawerSettlingSourceRelease;
  _phase = RNSideDrawerPhaseSettling;
}

- (void)handlePanGesture:(UIPanGestureRecognizer *)panGestureRecognizer
{
  if (_phase != RNSideDrawerPhaseDragging || panGestureRecognizer.state != UIGestureRecognizerStateChanged) return;
  CGFloat previousReveal = _reveal;
  [self updateRevealFromPanGesture];
  if (_reveal == previousReveal) return;
  [self applyProgress:[self progress]];
  [self publishProgress];
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

- (CGFloat)presentationReveal
{
  CALayer *layer = _contentPresentationView.layer.presentationLayer ?: _contentPresentationView.layer;
  CGFloat viewportCenter = [self currentPhysicalOffset] + self.bounds.size.width * 0.5;
  return (layer.position.x - viewportCenter) * _revealDirection;
}

- (CGFloat)physicalOffsetForProgress:(CGFloat)progress
{
  CGFloat boundedProgress = RNSideDrawerClamp(progress, 0, 1);
  CGFloat reveal = boundedProgress * _laidOutDrawerWidth;
  return _revealDirection > 0 ? _laidOutDrawerWidth - reveal : reveal;
}

- (CGFloat)directRevealForRawReveal:(CGFloat)reveal
{
  if (reveal < 0) return RNSideDrawerOvertravelLimit * tanh(reveal / RNSideDrawerOvertravelLimit);
  if (reveal <= _laidOutDrawerWidth) return reveal;
  CGFloat overtravel = reveal - _laidOutDrawerWidth;
  return _laidOutDrawerWidth + RNSideDrawerOvertravelLimit * tanh(overtravel / RNSideDrawerOvertravelLimit);
}

- (CGFloat)directRawRevealForPresentation:(CGFloat)reveal
{
  if (reveal < 0) {
    CGFloat normalized = RNSideDrawerClamp(reveal / RNSideDrawerOvertravelLimit, -1 + 1e-6, 0);
    return RNSideDrawerOvertravelLimit * atanh(normalized);
  }
  if (reveal <= _laidOutDrawerWidth) return reveal;
  CGFloat normalized = RNSideDrawerClamp(
      (reveal - _laidOutDrawerWidth) / RNSideDrawerOvertravelLimit, 0, 1 - 1e-6);
  return _laidOutDrawerWidth + RNSideDrawerOvertravelLimit * atanh(normalized);
}

- (CGFloat)releaseRevealVelocity
{
  CGFloat velocity = [_scrollView.panGestureRecognizer velocityInView:self].x * _revealDirection;
  return RNSideDrawerPresentedReleaseVelocity(_dragRawReveal, _laidOutDrawerWidth, velocity);
}

- (void)updateRevealFromPanGesture
{
  CGFloat translation = [_scrollView.panGestureRecognizer translationInView:self].x * _revealDirection;
  CGFloat rawReveal = _dragStartRawReveal + translation - _dragStartTranslation;
  _dragRawReveal = rawReveal;
  _reveal = [self directRevealForRawReveal:rawReveal];
}

- (CGFloat)currentPhysicalOffset
{
  return _scrollView.contentOffset.x;
}

- (void)setPhysicalOffset:(CGFloat)offset
{
  CGFloat resolvedOffset = RNSideDrawerClamp(offset, 0, _laidOutDrawerWidth);
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
  [self setPhysicalOffset:offset];
  [CATransaction commit];
}

- (void)cancelActiveDragAtOffset:(CGFloat)offset
{
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  _scrollView.scrollEnabled = NO;
  _scrollView.scrollEnabled = _gestureEnabled;
  [self setPhysicalOffset:offset];
  [CATransaction commit];
}

- (void)updateCountertrackedFramesForOffset:(CGFloat)offset
{
  CGPoint center = CGPointMake(offset + self.bounds.size.width * 0.5, self.bounds.size.height * 0.5);
  _contactBackingView.center = center;
  if (_panelView != nil) _panelView.center = center;
}

- (CGFloat)revealFromContentCenter
{
  CGFloat viewportCenter = [self currentPhysicalOffset] + self.bounds.size.width * 0.5;
  return (_contentPresentationView.center.x - viewportCenter) * _revealDirection;
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
  [self applyContentReveal:_reveal];
  [self applyMotionProgress:progress];
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

- (void)applyContentReveal:(CGFloat)reveal
{
  CGFloat offset = [self currentPhysicalOffset];
  [self updateCountertrackedFramesForOffset:offset];
  CGPoint center = CGPointMake(
      offset + self.bounds.size.width * 0.5,
      self.bounds.size.height * 0.5);
  _contentPresentationView.center = CGPointMake(center.x + _revealDirection * reveal, center.y);
}

- (void)applyMotionProgress:(CGFloat)progress
{
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
  if (_contentHostView.alpha != boundedContentOpacity) _contentHostView.alpha = boundedContentOpacity;
  if (!CGAffineTransformEqualToTransform(_contentPresentationView.transform, contentTransform)) {
    _contentPresentationView.transform = contentTransform;
  }
  [_contentView setDrawerOverlayOpacity:_motion[RNSideDrawerMotionOverlayOpacity].evaluate(progress, 0)];
  CGFloat borderOpacity = _motion[RNSideDrawerMotionContentBorderOpacity].evaluate(progress, 1);
  CGFloat boundedBorderOpacity = RNSideDrawerClamp(borderOpacity, 0, 1);
  if (_contentBorderLayer.opacity != boundedBorderOpacity) _contentBorderLayer.opacity = boundedBorderOpacity;
  CGFloat shadowOpacity = _motion[RNSideDrawerMotionContentShadowOpacity].evaluate(progress, 1);
  CGFloat boundedShadowOpacity = RNSideDrawerClamp(shadowOpacity, 0, 1);
  if (_contentPresentationView.layer.shadowOpacity != boundedShadowOpacity) {
    _contentPresentationView.layer.shadowOpacity = boundedShadowOpacity;
  }
}

- (void)applySettlingInteractionState
{
  _panelView.userInteractionEnabled = YES;
  [_contentView setDrawerProgress:MAX([self progress], 0.0011)];
  _panelView.accessibilityElementsHidden = NO;
  _contentView.accessibilityElementsHidden = NO;
}

- (void)applyContentCorners
{
  UIScreen *screen = self.window.screen ?: UIScreen.mainScreen;
  CGFloat radius = _contentCornerRadius >= 0 ? _contentCornerRadius : RNSideDrawerScreenCornerRadius(screen);
  _contentHostView.layer.cornerCurve = kCACornerCurveContinuous;
  _contentHostView.layer.cornerRadius = radius;
  _contentHostView.layer.masksToBounds = radius > 0;
  _contentBorderLayer.contentsScale = screen.scale;
  _contentBorderLayer.cornerCurve = kCACornerCurveContinuous;
  _contentBorderLayer.cornerRadius = radius;
  _contentPresentationView.layer.shadowPath =
      [UIBezierPath bezierPathWithRoundedRect:_contentPresentationView.bounds cornerRadius:radius].CGPath;
}

- (void)updateContentBorderColor
{
  UIColor *resolvedColor = [_contentBorderColor resolvedColorWithTraitCollection:self.traitCollection];
  _contentBorderLayer.borderColor = resolvedColor.CGColor;
}

- (void)updateContentShadowColor
{
  UIColor *resolvedColor = [_contentShadowColor resolvedColorWithTraitCollection:self.traitCollection];
  _contentPresentationView.layer.shadowColor = (_contentShadowRadius > 0 ? resolvedColor : UIColor.clearColor).CGColor;
}

- (void)advanceSettleToTime:(CFTimeInterval)time
{
  if (!_settleActive || time <= _lastSettleTime) return;
  CFTimeInterval elapsed = time - _lastSettleTime;
  CGFloat target = _targetOpen ? _laidOutDrawerWidth : 0;
  CGFloat displacement = _reveal - target;
  CGFloat coefficient = _settleVelocity + RNSideDrawerSettleAngularFrequency * displacement;
  CGFloat decay = exp(-RNSideDrawerSettleAngularFrequency * elapsed);
  _reveal = target + (displacement + coefficient * elapsed) * decay;
  _settleVelocity = (_settleVelocity - RNSideDrawerSettleAngularFrequency * coefficient * elapsed) * decay;
  _lastSettleTime = time;
}

- (void)startSettleDisplayLink
{
  if (_settleDisplayLink != nil) return;
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

- (void)updateSettleDisplayLink
{
  BOOL active = _settleActive && _phase == RNSideDrawerPhaseSettling;
  BOOL needed = _settlePausedForTracking || _progressEventsEnabled || RNSideDrawerHasMotion(_motion);
  if (active && needed) {
    [self startSettleDisplayLink];
  } else {
    [self stopSettleDisplayLink];
  }
}

- (void)stepSettleDisplayLink:(CADisplayLink *)displayLink
{
  (void)displayLink;
  if (!_settleActive || _phase != RNSideDrawerPhaseSettling) {
    [self stopSettleDisplayLink];
    return;
  }
  if (_settlePausedForTracking) {
    if (_scrollView.tracking) return;
    BOOL targetOpen = _targetOpen;
    _settleActive = NO;
    _settlePausedForTracking = NO;
    [self stopSettleDisplayLink];
    [self startSettleToOpen:targetOpen revealVelocity:0];
    return;
  }
  if (_settleAnimator == nil) {
    [self stopSettleDisplayLink];
    return;
  }
  CGFloat reveal = [self presentationReveal];
  if (RNSideDrawerHasMotion(_motion)) {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self applyMotionProgress:RNSideDrawerClamp(reveal / MAX(_laidOutDrawerWidth, 1), 0, 1)];
    [CATransaction commit];
  }
  [self publishProgressForReveal:reveal];
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
  [self publishProgressForReveal:_reveal];
}

- (void)flushPendingProgressSnapshot
{
  if (!_progressSnapshotPending || !_progressEventsEnabled || !_hasLaidOut) return;
  _progressSnapshotPending = NO;
  CGFloat reveal = _phase == RNSideDrawerPhaseSettling && _settleAnimator != nil
      ? [self presentationReveal]
      : _reveal;
  [self publishProgressForReveal:reveal];
}

- (void)publishProgressForReveal:(CGFloat)reveal
{
  if (!_progressEventsEnabled) return;
  if (self.progressHandler == nil && self.onProgress == nil) return;
  NSDictionary *payload = @{
    @"phase" : [self phaseName],
    @"progress" : @(RNSideDrawerClamp(reveal / MAX(_laidOutDrawerWidth, 1), 0, 1)),
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
