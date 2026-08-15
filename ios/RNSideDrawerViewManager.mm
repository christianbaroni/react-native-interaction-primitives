#import "RNSideDrawerContentView.h"
#import "RNSideDrawerPanelView.h"
#import "RNSideDrawerSlots.h"
#import "RNSideDrawerView.h"

#import <React/RCTConvert.h>
#import <React/RCTUIManager.h>
#import <React/RCTViewManager.h>

#ifdef RCT_NEW_ARCH_ENABLED
#import <React/RCTConversions.h>
#import <React/RCTViewComponentView.h>
#import <react/renderer/components/RNPagerDrawerSpec/ComponentDescriptors.h>
#import <react/renderer/components/RNPagerDrawerSpec/EventEmitters.h>
#import <react/renderer/components/RNPagerDrawerSpec/Props.h>
#import <react/renderer/components/RNPagerDrawerSpec/RCTComponentViewHelpers.h>
#endif

#ifdef RCT_NEW_ARCH_ENABLED

using namespace facebook::react;

template <typename Phase>
static Phase RNSideDrawerPhaseValue(NSDictionary *payload)
{
  NSString *value = payload[@"phase"];
  if ([value isEqualToString:@"open"]) return Phase::Open;
  if ([value isEqualToString:@"dragging"]) return Phase::Dragging;
  if ([value isEqualToString:@"settling"]) return Phase::Settling;
  return Phase::Closed;
}

template <typename Source>
static Source RNSideDrawerSourceValue(NSDictionary *payload)
{
  NSString *value = payload[@"settlingSource"];
  if ([value isEqualToString:@"programmatic"]) return Source::Programmatic;
  if ([value isEqualToString:@"release"]) return Source::Release;
  return Source::None;
}

@interface RNSideDrawerPanelViewComponentView : RCTViewComponentView <RCTRNSideDrawerPanelViewViewProtocol, RNSideDrawerPanelSlot>
@end

@implementation RNSideDrawerPanelViewComponentView

+ (ComponentDescriptorProvider)componentDescriptorProvider
{
  return concreteComponentDescriptorProvider<RNSideDrawerPanelViewComponentDescriptor>();
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if ((self = [super initWithFrame:frame])) {
    static const auto defaultProps = std::make_shared<const RNSideDrawerPanelViewProps>();
    _props = defaultProps;
    self.clipsToBounds = YES;
  }
  return self;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-missing-super-calls"
- (void)updateLayoutMetrics:(const LayoutMetrics &)layoutMetrics
           oldLayoutMetrics:(const LayoutMetrics &)oldLayoutMetrics
{
  bool firstUpdate = oldLayoutMetrics == EmptyLayoutMetrics;
  if (firstUpdate || layoutMetrics.layoutDirection != oldLayoutMetrics.layoutDirection) {
    self.semanticContentAttribute = layoutMetrics.layoutDirection == LayoutDirection::RightToLeft
        ? UISemanticContentAttributeForceRightToLeft
        : UISemanticContentAttributeForceLeftToRight;
  }
  if (firstUpdate || layoutMetrics.displayType != oldLayoutMetrics.displayType) {
    self.hidden = layoutMetrics.displayType == DisplayType::None;
  }
}
#pragma clang diagnostic pop

@end


@interface RNSideDrawerContentViewComponentView : RCTViewComponentView <RCTRNSideDrawerContentViewViewProtocol, RNSideDrawerContentSlot>
@property (nonatomic, copy, nullable) dispatch_block_t onScrimPress;
@end

@implementation RNSideDrawerContentViewComponentView {
  UIView *_scrimView;
}

@synthesize onScrimPress = _onScrimPress;

+ (ComponentDescriptorProvider)componentDescriptorProvider
{
  return concreteComponentDescriptorProvider<RNSideDrawerContentViewComponentDescriptor>();
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if ((self = [super initWithFrame:frame])) {
    static const auto defaultProps = std::make_shared<const RNSideDrawerContentViewProps>();
    _props = defaultProps;
    self.clipsToBounds = YES;

    _scrimView = [[UIView alloc] initWithFrame:self.bounds];
    _scrimView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scrimView.backgroundColor = UIColor.clearColor;
    _scrimView.userInteractionEnabled = NO;
    [_scrimView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleScrimPress)]];
    [super addSubview:_scrimView];
  }
  return self;
}

- (void)handleScrimPress
{
  if (self.onScrimPress != nil) self.onScrimPress();
}

- (void)setDrawerProgress:(CGFloat)progress
{
  BOOL enabled = progress > 0.001;
  if (_scrimView.userInteractionEnabled != enabled) _scrimView.userInteractionEnabled = enabled;
}

- (void)setDrawerOverlayColor:(UIColor *)color
{
  _scrimView.backgroundColor = color;
}

- (void)setDrawerOverlayOpacity:(CGFloat)opacity
{
  CGFloat boundedOpacity = MIN(1, MAX(0, opacity));
  if (_scrimView.alpha != boundedOpacity) _scrimView.alpha = boundedOpacity;
}

- (void)mountChildComponentView:(UIView<RCTComponentViewProtocol> *)childComponentView index:(NSInteger)index
{
  [super mountChildComponentView:childComponentView index:index];
  [self bringSubviewToFront:_scrimView];
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-missing-super-calls"
- (void)updateLayoutMetrics:(const LayoutMetrics &)layoutMetrics
           oldLayoutMetrics:(const LayoutMetrics &)oldLayoutMetrics
{
  bool firstUpdate = oldLayoutMetrics == EmptyLayoutMetrics;
  if (firstUpdate || layoutMetrics.layoutDirection != oldLayoutMetrics.layoutDirection) {
    self.semanticContentAttribute = layoutMetrics.layoutDirection == LayoutDirection::RightToLeft
        ? UISemanticContentAttributeForceRightToLeft
        : UISemanticContentAttributeForceLeftToRight;
  }
  if (firstUpdate || layoutMetrics.displayType != oldLayoutMetrics.displayType) {
    self.hidden = layoutMetrics.displayType == DisplayType::None;
  }
}
#pragma clang diagnostic pop

@end


@interface RNSideDrawerViewComponentView : RCTViewComponentView <RCTRNSideDrawerViewViewProtocol>
@end

@implementation RNSideDrawerViewComponentView {
  RNSideDrawerView *_drawerView;
}

+ (ComponentDescriptorProvider)componentDescriptorProvider
{
  return concreteComponentDescriptorProvider<RNSideDrawerViewComponentDescriptor>();
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if ((self = [super initWithFrame:frame])) {
    static const auto defaultProps = std::make_shared<const RNSideDrawerViewProps>();
    _props = defaultProps;
    self.clipsToBounds = YES;

    _drawerView = [[RNSideDrawerView alloc] initWithFrame:self.bounds];
    _drawerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    __weak RNSideDrawerViewComponentView *weakSelf = self;
    _drawerView.openChangeHandler = ^(NSDictionary *payload) {
      RNSideDrawerViewComponentView *strongSelf = weakSelf;
      if (strongSelf == nil) return;
      auto emitter = std::static_pointer_cast<const RNSideDrawerViewEventEmitter>(strongSelf->_eventEmitter);
      if (emitter == nullptr) return;
      RNSideDrawerViewEventEmitter::OnOpenChange event{};
      event.open = [payload[@"open"] boolValue];
      emitter->onOpenChange(event);
    };
    _drawerView.progressHandler = ^(NSDictionary *payload) {
      RNSideDrawerViewComponentView *strongSelf = weakSelf;
      if (strongSelf == nil) return;
      auto emitter = std::static_pointer_cast<const RNSideDrawerViewEventEmitter>(strongSelf->_eventEmitter);
      if (emitter == nullptr) return;
      RNSideDrawerViewEventEmitter::OnProgress event{};
      event.phase = RNSideDrawerPhaseValue<decltype(event.phase)>(payload);
      event.progress = (Float)[payload[@"progress"] doubleValue];
      event.settlingSource = RNSideDrawerSourceValue<decltype(event.settlingSource)>(payload);
      event.targetOpen = [payload[@"targetOpen"] boolValue];
      emitter->onProgress(event);
    };
    [super addSubview:_drawerView];
  }
  return self;
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  _drawerView.frame = self.bounds;
}

- (void)updateProps:(const Props::Shared &)props oldProps:(const Props::Shared &)oldProps
{
  const auto &oldViewProps = static_cast<const RNSideDrawerViewProps &>(*_props);
  const auto &newViewProps = static_cast<const RNSideDrawerViewProps &>(*props);
  if (oldViewProps.contentCornerRadius != newViewProps.contentCornerRadius) {
    _drawerView.contentCornerRadius = newViewProps.contentCornerRadius;
  }
  if (oldViewProps.drawerWidth != newViewProps.drawerWidth) {
    _drawerView.drawerWidth = newViewProps.drawerWidth;
  }
  if (oldViewProps.gestureEnabled != newViewProps.gestureEnabled) {
    _drawerView.gestureEnabled = newViewProps.gestureEnabled;
  }
  if (oldViewProps.initialOpen != newViewProps.initialOpen) {
    _drawerView.initialOpen = newViewProps.initialOpen;
  }
  if (oldViewProps.motionConfig != newViewProps.motionConfig) {
    NSMutableArray<NSNumber *> *config = [NSMutableArray arrayWithCapacity:newViewProps.motionConfig.size()];
    for (Float value : newViewProps.motionConfig) [config addObject:@(value)];
    _drawerView.motionConfig = config;
  }
  if (oldViewProps.openChangeEventsEnabled != newViewProps.openChangeEventsEnabled) {
    _drawerView.openChangeEventsEnabled = newViewProps.openChangeEventsEnabled;
  }
  if (oldViewProps.overlayColor != newViewProps.overlayColor) {
    _drawerView.overlayColor = RCTUIColorFromSharedColor(newViewProps.overlayColor);
  }
  if (oldViewProps.progressEventsEnabled != newViewProps.progressEventsEnabled) {
    _drawerView.progressEventsEnabled = newViewProps.progressEventsEnabled;
  }
  if (oldViewProps.side != newViewProps.side) {
    _drawerView.side = newViewProps.side == RNSideDrawerViewSide::End
        ? RNSideDrawerSideEnd
        : RNSideDrawerSideStart;
  }
  [super updateProps:props oldProps:oldProps];
}

- (void)mountChildComponentView:(UIView<RCTComponentViewProtocol> *)childComponentView index:(NSInteger)index
{
  if (![childComponentView conformsToProtocol:@protocol(RNSideDrawerPanelSlot)] &&
      ![childComponentView conformsToProtocol:@protocol(RNSideDrawerContentSlot)]) return;
  [_drawerView mountSlot:childComponentView atIndex:index];
}

- (void)unmountChildComponentView:(UIView<RCTComponentViewProtocol> *)childComponentView index:(NSInteger)index
{
  (void)index;
  [_drawerView unmountSlot:childComponentView];
}

- (void)handleCommand:(const NSString *)commandName args:(const NSArray *)args
{
  RCTRNSideDrawerViewHandleCommand(self, commandName, args);
}

- (void)close:(BOOL)animated
{
  [_drawerView closeAnimated:animated];
}

- (void)open:(BOOL)animated
{
  [_drawerView openAnimated:animated];
}

- (void)toggle:(BOOL)animated
{
  [_drawerView toggleAnimated:animated];
}

- (void)prepareForRecycle
{
  [_drawerView prepareForRemoval];
  const Props::Shared oldProps = _props;
  static const auto defaultProps = std::make_shared<const RNSideDrawerViewProps>();
  [self updateProps:defaultProps oldProps:oldProps];
  [super prepareForRecycle];
}

@end

#endif


@interface RNSideDrawerPanelViewManager : RCTViewManager
@end

@implementation RNSideDrawerPanelViewManager

RCT_EXPORT_MODULE(RNSideDrawerPanelView)

- (UIView *)view
{
  return [[RNSideDrawerPanelView alloc] initWithFrame:CGRectZero];
}

@end


@interface RNSideDrawerContentViewManager : RCTViewManager
@end

@implementation RNSideDrawerContentViewManager

RCT_EXPORT_MODULE(RNSideDrawerContentView)

- (UIView *)view
{
  return [[RNSideDrawerContentView alloc] initWithFrame:CGRectZero];
}

@end


@interface RNSideDrawerViewManager : RCTViewManager
@end

@implementation RNSideDrawerViewManager

RCT_EXPORT_MODULE(RNSideDrawerView)

- (UIView *)view
{
  return [[RNSideDrawerView alloc] initWithFrame:CGRectZero];
}

- (void)onDropViewInstance:(RNSideDrawerView *)view
{
  [view prepareForRemoval];
}

RCT_EXPORT_VIEW_PROPERTY(drawerWidth, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(contentCornerRadius, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(gestureEnabled, BOOL)
RCT_EXPORT_VIEW_PROPERTY(initialOpen, BOOL)
RCT_EXPORT_VIEW_PROPERTY(motionConfig, NSArray)
RCT_EXPORT_VIEW_PROPERTY(openChangeEventsEnabled, BOOL)
RCT_EXPORT_VIEW_PROPERTY(overlayColor, UIColor)
RCT_EXPORT_VIEW_PROPERTY(progressEventsEnabled, BOOL)
RCT_EXPORT_VIEW_PROPERTY(onOpenChange, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onProgress, RCTDirectEventBlock)

RCT_CUSTOM_VIEW_PROPERTY(side, NSString, RNSideDrawerView)
{
  NSString *side = [RCTConvert NSString:json] ?: @"start";
  view.side = [side isEqualToString:@"end"] ? RNSideDrawerSideEnd : RNSideDrawerSideStart;
}

RCT_EXPORT_METHOD(close:(nonnull NSNumber *)reactTag animated:(BOOL)animated)
{
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, UIView *> *viewRegistry) {
    UIView *view = viewRegistry[reactTag];
    if ([view isKindOfClass:RNSideDrawerView.class]) [(RNSideDrawerView *)view closeAnimated:animated];
  }];
}

RCT_EXPORT_METHOD(open:(nonnull NSNumber *)reactTag animated:(BOOL)animated)
{
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, UIView *> *viewRegistry) {
    UIView *view = viewRegistry[reactTag];
    if ([view isKindOfClass:RNSideDrawerView.class]) [(RNSideDrawerView *)view openAnimated:animated];
  }];
}

RCT_EXPORT_METHOD(toggle:(nonnull NSNumber *)reactTag animated:(BOOL)animated)
{
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, UIView *> *viewRegistry) {
    UIView *view = viewRegistry[reactTag];
    if ([view isKindOfClass:RNSideDrawerView.class]) [(RNSideDrawerView *)view toggleAnimated:animated];
  }];
}

@end
