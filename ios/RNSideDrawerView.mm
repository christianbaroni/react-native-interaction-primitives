#import "RNSideDrawerView.h"

#import "RNSideDrawerContentView.h"
#import "RNSideDrawerGestureScrollView.h"
#import "RNSideDrawerInteraction.h"
#import "RNSideDrawerMotion.h"
#import "RNSideDrawerPanelView.h"
#import "RNSideDrawerSlots.h"
#import "RNPagerDrawerHapticFeedback.h"

#import <React/UIView+React.h>
#import <QuartzCore/QuartzCore.h>
#include <float.h>
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
- (void)setOpen:(BOOL)open animated:(BOOL)animated source:(RNSideDrawerSettlingSource)source;
- (void)startSettleToOpen:(BOOL)open
           revealVelocity:(CGFloat)revealVelocity
              interaction:(rnsidedrawer::Interaction)interaction;
- (BOOL)prepareSettleToOpen:(BOOL)open
                    reveal:(CGFloat)reveal
                  velocity:(CGFloat)velocity;
- (void)startPreparedSettleAnimatorToOpen:(BOOL)open;
- (CGFloat)stopSettleAtCurrentPosition;
- (void)pauseActiveSettle;
- (void)finishAtOpen:(BOOL)open;
- (void)advanceSettleToTime:(CFTimeInterval)time;

- (BOOL)canBeginPanWithVelocity:(CGPoint)velocity;
- (void)handleContactBegin;
- (void)handlePanGesture:(UIPanGestureRecognizer *)panGestureRecognizer;
- (void)updateDragFromPanGesture;
- (CGFloat)releaseRevealVelocity;
- (void)commitReleaseWithRevealVelocity:(CGFloat)revealVelocity targetOpen:(BOOL)targetOpen;
- (void)cancelActiveDragAtScrollOffset:(CGFloat)offset;
- (void)stopScrollMotionAtOffset:(CGFloat)offset;

- (CGFloat)revealProgress;
- (CGFloat)presentedReveal;
- (CGFloat)revealFromContentPosition;
- (void)alignFixedViewsToScrollOffset:(CGFloat)offset;
- (void)positionContentForReveal:(CGFloat)reveal;
- (void)applyPresentationAtProgress:(CGFloat)progress;
- (void)applyMotionAtProgress:(CGFloat)progress;
- (void)applySettlingInteractionState;
- (void)applyContentCorners;
- (void)updateContentBorderColor;
- (void)updateContentShadowColor;

- (void)startSettleDisplayLink;
- (void)stopSettleDisplayLink;
- (void)updateSettleDisplayLink;
- (void)publishProgressForReveal:(CGFloat)reveal;
@end

@implementation RNSideDrawerView {
  RNSideDrawerGestureScrollView *_scrollView;
  UIView *_contactBackingView;
  RNSideDrawerContentPresentationView *_contentPresentationView;
  UIView *_contentHostView;
  RNSideDrawerBorderLayer *_contentBorderLayer;
  UIView<RNSideDrawerPanelSlot> *_panelView;
  UIView<RNSideDrawerContentSlot> *_contentView;
  NSMutableArray<UIView *> *_slots;

  RNSideDrawerPhase _phase;
  RNSideDrawerSettlingSource _settlingSource;
  BOOL _open;
  BOOL _targetOpen;
  BOOL _lastEmittedOpen;
  BOOL _hasLaidOut;
  BOOL _progressSnapshotPending;
  NSInteger _openingDirection;
  CGFloat _laidOutDrawerWidth;
  CGFloat _reveal;

  RNPagerDrawerHapticFeedback *_hapticFeedback;
  BOOL _gestureOriginOpen;
  BOOL _gestureHapticTriggered;
  BOOL _suppressCurrentDragRelease;
  CGFloat _releaseRevealVelocity;
  CGFloat _unconstrainedDragPosition;
  CGFloat _dragStartPosition;
  CGFloat _dragStartTranslation;
  CGFloat _dragLowerBound;
  CGFloat _dragUpperBound;

  UIViewPropertyAnimator *_settleAnimator;
  CADisplayLink *_settleDisplayLink;
  BOOL _settleActive;
  BOOL _settlePausedForTracking;
  CGFloat _settleVelocity;
  CFTimeInterval _lastSettleTime;

  rnsidedrawer::InteractionConfiguration _configuredInteraction;
  rnsidedrawer::Interaction _activeInteraction;
  rnsidedrawer::Motion _motion;
}

static const rnsidedrawer::InteractionConfiguration kDefaultInteractionConfiguration =
    rnsidedrawer::defaultInteractionConfiguration();

static CGFloat RNSideDrawerClamp(CGFloat value, CGFloat minimum, CGFloat maximum)
{
  return MIN(maximum, MAX(minimum, value));
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

#pragma mark - Lifecycle

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
    _configuredInteraction = kDefaultInteractionConfiguration;
    _activeInteraction = rnsidedrawer::resolveInteraction(_configuredInteraction);
    _drawerWidth = 0;
    _gestureEnabled = YES;
    _side = RNSideDrawerSideStart;
    _phase = RNSideDrawerPhaseClosed;
    _settlingSource = RNSideDrawerSettlingSourceNone;
    _openingDirection = 1;
    _slots = [NSMutableArray arrayWithCapacity:2];

    _scrollView = [[RNSideDrawerGestureScrollView alloc] initWithFrame:self.bounds];
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
    _scrollView.canBeginDrawerPan = ^BOOL(CGPoint velocity) {
      RNSideDrawerView *strongSelf = weakSelf;
      return strongSelf != nil && [strongSelf canBeginPanWithVelocity:velocity];
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
  CGFloat previousDragPosition = _unconstrainedDragPosition;
  CGFloat previousDragLowerBound = _dragLowerBound;
  CGFloat previousDragUpperBound = _dragUpperBound;

  _openingDirection = [self resolvedOpeningDirection];
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
    _unconstrainedDragPosition =
        rnsidedrawer::remapPositionForWidthChange(previousDragPosition, previousDrawerWidth, _laidOutDrawerWidth);
    _dragLowerBound =
        rnsidedrawer::remapPositionForWidthChange(previousDragLowerBound, previousDrawerWidth, _laidOutDrawerWidth);
    _dragUpperBound =
        rnsidedrawer::remapPositionForWidthChange(previousDragUpperBound, previousDrawerWidth, _laidOutDrawerWidth);
    _reveal = rnsidedrawer::resistedPosition(
        _unconstrainedDragPosition, _dragLowerBound, _dragUpperBound, _activeInteraction.overdrag);
    _dragStartPosition = _unconstrainedDragPosition;
    _dragStartTranslation = [_scrollView.panGestureRecognizer translationInView:self].x * _openingDirection;
  }
  [self setScrollOffset:[self scrollOffsetForProgress:[self revealProgress]]];
  [self applyPresentationAtProgress:[self revealProgress]];
  [self applyContentCorners];

  if (resumeSettling) {
    if (resumePaused) {
      _settleActive = YES;
      _settlePausedForTracking = YES;
      _settleVelocity = 0;
      [self startSettleDisplayLink];
    } else {
      if ([self prepareSettleToOpen:targetOpen reveal:_reveal velocity:resumeVelocity]) {
        [self startPreparedSettleAnimatorToOpen:targetOpen];
      } else {
        [self finishAtOpen:targetOpen];
      }
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

#pragma mark - Properties

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

- (void)setOverdrag:(CGFloat)overdrag
{
  _configuredInteraction.overdrag =
      isfinite(overdrag) && overdrag >= 0 ? overdrag : kDefaultInteractionConfiguration.overdrag;
}

- (CGFloat)overdrag
{
  return _configuredInteraction.overdrag;
}

- (void)setReleaseOpenThreshold:(CGFloat)releaseOpenThreshold
{
  _configuredInteraction.releaseOpenThreshold =
      isfinite(releaseOpenThreshold) && releaseOpenThreshold >= 0 && releaseOpenThreshold <= 1
      ? releaseOpenThreshold
      : kDefaultInteractionConfiguration.releaseOpenThreshold;
}

- (CGFloat)releaseOpenThreshold
{
  return _configuredInteraction.releaseOpenThreshold;
}

- (void)setReleaseVelocitySensitivity:(CGFloat)releaseVelocitySensitivity
{
  _configuredInteraction.releaseVelocitySensitivity =
      isfinite(releaseVelocitySensitivity) && releaseVelocitySensitivity >= 0
      ? releaseVelocitySensitivity
      : kDefaultInteractionConfiguration.releaseVelocitySensitivity;
}

- (CGFloat)releaseVelocitySensitivity
{
  return _configuredInteraction.releaseVelocitySensitivity;
}

- (void)setReleaseVelocityTransfer:(CGFloat)releaseVelocityTransfer
{
  _configuredInteraction.releaseVelocityTransfer =
      isfinite(releaseVelocityTransfer) && releaseVelocityTransfer >= 0
      ? releaseVelocityTransfer
      : kDefaultInteractionConfiguration.releaseVelocityTransfer;
}

- (CGFloat)releaseVelocityTransfer
{
  return _configuredInteraction.releaseVelocityTransfer;
}

- (void)setSpringDamping:(CGFloat)springDamping
{
  _configuredInteraction.springDamping =
      isfinite(springDamping) && springDamping > 0
      ? springDamping
      : kDefaultInteractionConfiguration.springDamping;
}

- (CGFloat)springDamping
{
  return _configuredInteraction.springDamping;
}

- (void)setSpringMass:(CGFloat)springMass
{
  _configuredInteraction.springMass =
      isfinite(springMass) && springMass > 0 ? springMass : kDefaultInteractionConfiguration.springMass;
}

- (CGFloat)springMass
{
  return _configuredInteraction.springMass;
}

- (void)setSpringStiffness:(CGFloat)springStiffness
{
  _configuredInteraction.springStiffness = isfinite(springStiffness) && springStiffness > 0
      ? springStiffness
      : kDefaultInteractionConfiguration.springStiffness;
}

- (CGFloat)springStiffness
{
  return _configuredInteraction.springStiffness;
}

- (void)setGestureEnabled:(BOOL)gestureEnabled
{
  if (_gestureEnabled == gestureEnabled) return;
  _gestureEnabled = gestureEnabled;
  if (!gestureEnabled && _phase == RNSideDrawerPhaseDragging) {
    [self setOpen:[self revealProgress] >= _activeInteraction.releaseOpenThreshold
         animated:YES
           source:RNSideDrawerSettlingSourceRelease];
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
  _motion = rnsidedrawer::compileMotion(_motionConfig);
  if (!_hasLaidOut) return;
  if (_phase == RNSideDrawerPhaseSettling) {
    CGFloat reveal = [self presentedReveal];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self applyMotionAtProgress:RNSideDrawerClamp(reveal / MAX(_laidOutDrawerWidth, 1), 0, 1)];
    [CATransaction commit];
  } else {
    [self applyPresentationAtProgress:[self revealProgress]];
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

#pragma mark - Slots

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

#pragma mark - Commands and settling

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
  BOOL open = _phase == RNSideDrawerPhaseSettling ? !_targetOpen : [self revealProgress] < 0.5;
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
    [self updateDragFromPanGesture];
    [self applyPresentationAtProgress:[self revealProgress]];
    _suppressCurrentDragRelease = YES;
  }
  _targetOpen = open;
  _settlingSource = source;
  _phase = RNSideDrawerPhaseSettling;
  if (cancelActiveDrag) {
    [self cancelActiveDragAtScrollOffset:[self scrollOffsetForProgress:[self revealProgress]]];
    [self applyPresentationAtProgress:[self revealProgress]];
  }
  [self publishProgress];
  if (!animated) {
    [self finishAtOpen:open];
    return;
  }
  rnsidedrawer::Interaction interaction =
      cancelActiveDrag && source == RNSideDrawerSettlingSourceRelease
      ? _activeInteraction
      : rnsidedrawer::resolveInteraction(_configuredInteraction);
  [self startSettleToOpen:open revealVelocity:revealVelocity interaction:interaction];
}

- (void)startSettleToOpen:(BOOL)open
           revealVelocity:(CGFloat)revealVelocity
              interaction:(rnsidedrawer::Interaction)interaction
{
  _activeInteraction = interaction;
  if (![self prepareSettleToOpen:open reveal:_reveal velocity:revealVelocity]) {
    [self finishAtOpen:open];
    return;
  }
  [self startPreparedSettleAnimatorToOpen:open];
}

- (void)startPreparedSettleAnimatorToOpen:(BOOL)open
{
  [self applySettlingInteractionState];
  CGFloat targetPosition = open ? _laidOutDrawerWidth : 0;
  CGFloat distance = targetPosition - _reveal;
  CGFloat normalizedVelocity = fabs(distance) > DBL_EPSILON ? _settleVelocity / distance : 0;
  const rnsidedrawer::Spring &spring = _activeInteraction.spring;
  UISpringTimingParameters *timing = [[UISpringTimingParameters alloc]
      initWithMass:spring.mass
         stiffness:spring.stiffness
           damping:spring.damping
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
    [strongSelf positionContentForReveal:targetPosition];
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
  CGFloat targetPosition = open ? _laidOutDrawerWidth : 0;
  UIScreen *screen = self.window.screen ?: UIScreen.mainScreen;
  CGFloat pixelTolerance = 1.0 / MAX(screen.scale, 1.0);
  CGFloat resolvedVelocity = isfinite(velocity) ? velocity : 0;
  _reveal = reveal;
  if (fabs(reveal - targetPosition) <= pixelTolerance) {
    _settleVelocity = 0;
    _settlePausedForTracking = NO;
    _settleActive = NO;
    return NO;
  }
  _settleVelocity = resolvedVelocity;
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
  _reveal = [self revealFromContentPosition];
  _settleActive = NO;
  _settlePausedForTracking = NO;
  [self stopSettleDisplayLink];
  [self applyPresentationAtProgress:[self revealProgress]];
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
  [self setRevealProgress:(open ? 1 : 0)];
  [self publishProgress];
  [self emitOpenChangeIfNeeded];
}

#pragma mark - Removal

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

#pragma mark - Gesture ownership

- (BOOL)canBeginPanWithVelocity:(CGPoint)velocity
{
  if (!_gestureEnabled || _laidOutDrawerWidth <= 0 || fabs(velocity.x) <= fabs(velocity.y)) return NO;

  CGFloat revealVelocity = velocity.x * _openingDirection;
  if (_reveal <= 0) return revealVelocity > 0;
  if (_reveal >= _laidOutDrawerWidth) return revealVelocity < 0;
  return YES;
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
  (void)scrollView;
  [_scrollView cancelReactTouchesForActivePan];
  _suppressCurrentDragRelease = NO;
  BOOL interruptedTargetOpen = _phase == RNSideDrawerPhaseSettling ? _targetOpen : _open;
  _gestureOriginOpen = interruptedTargetOpen;
  _gestureHapticTriggered = NO;
  if (_settleActive) [self stopSettleAtCurrentPosition];
  _activeInteraction = rnsidedrawer::resolveInteraction(_configuredInteraction);
  _dragStartPosition = _reveal;
  _unconstrainedDragPosition = _dragStartPosition;
  _dragLowerBound = MIN(0, _reveal);
  _dragUpperBound = MAX(_laidOutDrawerWidth, _reveal);
  _dragStartTranslation = [_scrollView.panGestureRecognizer translationInView:self].x * _openingDirection;
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
  CGFloat offset = [self currentScrollOffset];
  if (_phase != RNSideDrawerPhaseDragging) {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self alignFixedViewsToScrollOffset:offset];
    [CATransaction commit];
    return;
  }
  CGFloat previousReveal = _reveal;
  [self updateDragFromPanGesture];
  if (_reveal != previousReveal) {
    [self applyPresentationAtProgress:[self revealProgress]];
    [self publishProgress];
  } else {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self positionContentForReveal:_reveal];
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
    targetContentOffset->x = [self currentScrollOffset];
    targetContentOffset->y = 0;
    return;
  }
  [self updateDragFromPanGesture];
  [self applyPresentationAtProgress:[self revealProgress]];
  CGFloat revealVelocity = [self releaseRevealVelocity];
  BOOL targetOpen = rnsidedrawer::releaseShouldOpen(
      _reveal,
      revealVelocity,
      _laidOutDrawerWidth,
      _scrollView.decelerationRate,
      _activeInteraction.releaseVelocitySensitivity,
      _activeInteraction.releaseOpenThreshold);
  CGFloat currentOffset = [self currentScrollOffset];
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
    [self updateDragFromPanGesture];
    [self applyPresentationAtProgress:[self revealProgress]];
    if (_scrollView.panGestureRecognizer.state == UIGestureRecognizerStateEnded) {
      CGFloat revealVelocity = [self releaseRevealVelocity];
      BOOL targetOpen = rnsidedrawer::releaseShouldOpen(
          _reveal,
          revealVelocity,
          _laidOutDrawerWidth,
          _scrollView.decelerationRate,
          _activeInteraction.releaseVelocitySensitivity,
          _activeInteraction.releaseOpenThreshold);
      [self commitReleaseWithRevealVelocity:revealVelocity targetOpen:targetOpen];
    } else {
      _targetOpen = [self revealProgress] >= _activeInteraction.releaseOpenThreshold;
      _releaseRevealVelocity = 0;
      _settlingSource = RNSideDrawerSettlingSourceRelease;
      _phase = RNSideDrawerPhaseSettling;
    }
    [self publishProgress];
  }
  if (_phase != RNSideDrawerPhaseSettling) return;
  CGFloat offset = [self currentScrollOffset];
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
    [self stopScrollMotionAtOffset:[self currentScrollOffset]];
    return;
  }
  if (!_settleActive) return;
  [self stopScrollMotionAtOffset:[self currentScrollOffset]];
}

- (void)commitReleaseWithRevealVelocity:(CGFloat)revealVelocity targetOpen:(BOOL)targetOpen
{
  if (targetOpen != _gestureOriginOpen && !_gestureHapticTriggered) {
    _gestureHapticTriggered = YES;
    [_hapticFeedback trigger];
  }
  CGFloat targetPosition = targetOpen ? _laidOutDrawerWidth : 0;
  CGFloat transferredVelocity = revealVelocity * _activeInteraction.releaseVelocityTransfer;
  _releaseRevealVelocity = rnsidedrawer::limitReleaseVelocity(
      _reveal, transferredVelocity, targetPosition, _activeInteraction.spring, _activeInteraction.overdrag);
  _targetOpen = targetOpen;
  _settlingSource = RNSideDrawerSettlingSourceRelease;
  _phase = RNSideDrawerPhaseSettling;
}

- (void)handlePanGesture:(UIPanGestureRecognizer *)panGestureRecognizer
{
  if (_phase != RNSideDrawerPhaseDragging || panGestureRecognizer.state != UIGestureRecognizerStateChanged) return;
  CGFloat previousReveal = _reveal;
  [self updateDragFromPanGesture];
  if (_reveal == previousReveal) return;
  [self applyPresentationAtProgress:[self revealProgress]];
  [self publishProgress];
}

#pragma mark - Presentation

- (NSInteger)resolvedOpeningDirection
{
  BOOL isRTL = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
  BOOL revealsLeft = (_side == RNSideDrawerSideStart) != isRTL;
  return revealsLeft ? 1 : -1;
}

- (CGFloat)revealProgress
{
  return RNSideDrawerClamp(_reveal / MAX(_laidOutDrawerWidth, 1), 0, 1);
}

- (CGFloat)presentedReveal
{
  CALayer *layer = _contentPresentationView.layer.presentationLayer ?: _contentPresentationView.layer;
  CGFloat viewportCenter = [self currentScrollOffset] + self.bounds.size.width * 0.5;
  return (layer.position.x - viewportCenter) * _openingDirection;
}

- (CGFloat)scrollOffsetForProgress:(CGFloat)progress
{
  CGFloat boundedProgress = RNSideDrawerClamp(progress, 0, 1);
  CGFloat reveal = boundedProgress * _laidOutDrawerWidth;
  return _openingDirection > 0 ? _laidOutDrawerWidth - reveal : reveal;
}

- (CGFloat)releaseRevealVelocity
{
  CGFloat velocity = [_scrollView.panGestureRecognizer velocityInView:self].x * _openingDirection;
  return rnsidedrawer::resistedVelocity(
      _unconstrainedDragPosition, _dragLowerBound, _dragUpperBound, _activeInteraction.overdrag, velocity);
}

- (void)updateDragFromPanGesture
{
  CGFloat translation = [_scrollView.panGestureRecognizer translationInView:self].x * _openingDirection;
  CGFloat dragPosition = _dragStartPosition + translation - _dragStartTranslation;
  if (_activeInteraction.overdrag <= 0) {
    CGFloat boundedPosition = RNSideDrawerClamp(dragPosition, _dragLowerBound, _dragUpperBound);
    if (boundedPosition != dragPosition) {
      _dragStartPosition = boundedPosition;
      _dragStartTranslation = translation;
      dragPosition = boundedPosition;
    }
  }
  _unconstrainedDragPosition = dragPosition;
  _reveal = rnsidedrawer::resistedPosition(
      dragPosition, _dragLowerBound, _dragUpperBound, _activeInteraction.overdrag);
}

- (CGFloat)currentScrollOffset
{
  return _scrollView.contentOffset.x;
}

- (void)setScrollOffset:(CGFloat)offset
{
  CGFloat resolvedOffset = RNSideDrawerClamp(offset, 0, _laidOutDrawerWidth);
  _scrollView.contentOffset = CGPointMake(resolvedOffset, 0);
  [self alignFixedViewsToScrollOffset:resolvedOffset];
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
  [self setScrollOffset:offset];
  [CATransaction commit];
}

- (void)cancelActiveDragAtScrollOffset:(CGFloat)offset
{
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  _scrollView.scrollEnabled = NO;
  _scrollView.scrollEnabled = _gestureEnabled;
  [self setScrollOffset:offset];
  [CATransaction commit];
}

- (void)alignFixedViewsToScrollOffset:(CGFloat)offset
{
  CGPoint center = CGPointMake(offset + self.bounds.size.width * 0.5, self.bounds.size.height * 0.5);
  _contactBackingView.center = center;
  if (_panelView != nil) _panelView.center = center;
}

- (CGFloat)revealFromContentPosition
{
  CGFloat viewportCenter = [self currentScrollOffset] + self.bounds.size.width * 0.5;
  return (_contentPresentationView.center.x - viewportCenter) * _openingDirection;
}

- (void)setRevealProgress:(CGFloat)progress
{
  CGFloat boundedProgress = RNSideDrawerClamp(progress, 0, 1);
  _reveal = boundedProgress * _laidOutDrawerWidth;
  [self setScrollOffset:[self scrollOffsetForProgress:boundedProgress]];
  [self applyPresentationAtProgress:boundedProgress];
}

- (void)applyPresentationAtProgress:(CGFloat)progress
{
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  [self positionContentForReveal:_reveal];
  [self applyMotionAtProgress:progress];
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

- (void)positionContentForReveal:(CGFloat)reveal
{
  CGFloat offset = [self currentScrollOffset];
  [self alignFixedViewsToScrollOffset:offset];
  CGPoint center = CGPointMake(
      offset + self.bounds.size.width * 0.5,
      self.bounds.size.height * 0.5);
  _contentPresentationView.center = CGPointMake(center.x + _openingDirection * reveal, center.y);
}

- (void)applyMotionAtProgress:(CGFloat)progress
{
  CGFloat drawerOpacity = _motion.evaluate(rnsidedrawer::MotionChannel::DrawerOpacity, progress, 1);
  CGFloat drawerScale = _motion.evaluate(rnsidedrawer::MotionChannel::DrawerScale, progress, 1);
  CGFloat drawerTranslateX = _motion.evaluate(rnsidedrawer::MotionChannel::DrawerTranslationX, progress, 0);
  CGFloat drawerTranslateY = _motion.evaluate(rnsidedrawer::MotionChannel::DrawerTranslationY, progress, 0);
  CGFloat boundedDrawerOpacity = RNSideDrawerClamp(drawerOpacity, 0, 1);
  CGAffineTransform drawerTransform =
      CGAffineTransformMake(drawerScale, 0, 0, drawerScale, drawerTranslateX, drawerTranslateY);
  if (_panelView.alpha != boundedDrawerOpacity) _panelView.alpha = boundedDrawerOpacity;
  if (!CGAffineTransformEqualToTransform(_panelView.transform, drawerTransform)) _panelView.transform = drawerTransform;

  CGFloat contentOpacity = _motion.evaluate(rnsidedrawer::MotionChannel::ContentOpacity, progress, 1);
  CGFloat contentScale = _motion.evaluate(rnsidedrawer::MotionChannel::ContentScale, progress, 1);
  CGFloat contentTranslateX = _motion.evaluate(rnsidedrawer::MotionChannel::ContentTranslationX, progress, 0);
  CGFloat contentTranslateY = _motion.evaluate(rnsidedrawer::MotionChannel::ContentTranslationY, progress, 0);
  CGFloat boundedContentOpacity = RNSideDrawerClamp(contentOpacity, 0, 1);
  CGAffineTransform contentTransform =
      CGAffineTransformMake(contentScale, 0, 0, contentScale, contentTranslateX, contentTranslateY);
  if (_contentHostView.alpha != boundedContentOpacity) _contentHostView.alpha = boundedContentOpacity;
  if (!CGAffineTransformEqualToTransform(_contentPresentationView.transform, contentTransform)) {
    _contentPresentationView.transform = contentTransform;
  }
  [_contentView setDrawerOverlayOpacity:_motion.evaluate(rnsidedrawer::MotionChannel::OverlayOpacity, progress, 0)];
  CGFloat borderOpacity = _motion.evaluate(rnsidedrawer::MotionChannel::ContentBorderOpacity, progress, 1);
  CGFloat boundedBorderOpacity = RNSideDrawerClamp(borderOpacity, 0, 1);
  if (_contentBorderLayer.opacity != boundedBorderOpacity) _contentBorderLayer.opacity = boundedBorderOpacity;
  CGFloat shadowOpacity = _motion.evaluate(rnsidedrawer::MotionChannel::ContentShadowOpacity, progress, 1);
  CGFloat boundedShadowOpacity = RNSideDrawerClamp(shadowOpacity, 0, 1);
  if (_contentPresentationView.layer.shadowOpacity != boundedShadowOpacity) {
    _contentPresentationView.layer.shadowOpacity = boundedShadowOpacity;
  }
}

- (void)applySettlingInteractionState
{
  _panelView.userInteractionEnabled = YES;
  [_contentView setDrawerProgress:MAX([self revealProgress], 0.0011)];
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

#pragma mark - Settling observation

- (void)advanceSettleToTime:(CFTimeInterval)time
{
  if (!_settleActive || time <= _lastSettleTime) return;
  CFTimeInterval elapsed = time - _lastSettleTime;
  CGFloat target = _targetOpen ? _laidOutDrawerWidth : 0;
  rnsidedrawer::SpringState state =
      rnsidedrawer::evaluateSpring(_activeInteraction.spring, _reveal - target, _settleVelocity, elapsed);
  _reveal = target + state.displacement;
  _settleVelocity = state.velocity;
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
  BOOL needed = _settlePausedForTracking || _progressEventsEnabled || _motion.hasInterpolations();
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
    if ([self prepareSettleToOpen:targetOpen reveal:_reveal velocity:0]) {
      [self startPreparedSettleAnimatorToOpen:targetOpen];
    } else {
      [self finishAtOpen:targetOpen];
    }
    return;
  }
  if (_settleAnimator == nil) {
    [self stopSettleDisplayLink];
    return;
  }
  CGFloat reveal = [self presentedReveal];
  if (_motion.hasInterpolations()) {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self applyMotionAtProgress:RNSideDrawerClamp(reveal / MAX(_laidOutDrawerWidth, 1), 0, 1)];
    [CATransaction commit];
  }
  [self publishProgressForReveal:reveal];
}

#pragma mark - Events

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
      ? [self presentedReveal]
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
