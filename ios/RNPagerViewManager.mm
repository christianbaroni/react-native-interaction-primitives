#import "RNPagerPageView.h"
#import "RNPagerView.h"

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

static int RNPagerInt(NSDictionary *payload, NSString *key)
{
  return [payload[key] intValue];
}

static Float RNPagerFloat(NSDictionary *payload, NSString *key)
{
  return (Float)[payload[key] doubleValue];
}

template <typename Phase>
static Phase RNPagerPhase(NSDictionary *payload)
{
  NSString *value = payload[@"phase"];
  if ([value isEqualToString:@"idle"]) return Phase::Idle;
  if ([value isEqualToString:@"dragging"]) return Phase::Dragging;
  if ([value isEqualToString:@"settling"]) return Phase::Settling;
  return Phase::Empty;
}

template <typename Source>
static Source RNPagerSettlingSource(NSDictionary *payload)
{
  NSString *value = payload[@"settlingSource"];
  if ([value isEqualToString:@"programmatic"]) return Source::Programmatic;
  if ([value isEqualToString:@"release"]) return Source::Release;
  return Source::None;
}

template <typename Event>
static Event RNPagerStateEvent(NSDictionary *payload)
{
  Event event{};
  event.anchorOffset = RNPagerFloat(payload, @"anchorOffset");
  event.anchorPage = RNPagerInt(payload, @"anchorPage");
  event.offset = RNPagerFloat(payload, @"offset");
  event.page = RNPagerInt(payload, @"page");
  event.pageCount = RNPagerInt(payload, @"pageCount");
  event.pageExtent = RNPagerFloat(payload, @"pageExtent");
  event.phase = RNPagerPhase<decltype(event.phase)>(payload);
  event.position = RNPagerFloat(payload, @"position");
  event.settlingSource = RNPagerSettlingSource<decltype(event.settlingSource)>(payload);
  event.targetPage = RNPagerInt(payload, @"targetPage");
  return event;
}

@interface RNPagerPageViewComponentView : RCTViewComponentView <RCTRNPagerPageViewViewProtocol>
@end

@implementation RNPagerPageViewComponentView

+ (ComponentDescriptorProvider)componentDescriptorProvider
{
  return concreteComponentDescriptorProvider<RNPagerPageViewComponentDescriptor>();
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if ((self = [super initWithFrame:frame])) {
    static const auto defaultProps = std::make_shared<const RNPagerPageViewProps>();
    _props = defaultProps;
    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    self.clipsToBounds = YES;
  }
  return self;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-missing-super-calls"
- (void)updateLayoutMetrics:(const LayoutMetrics &)layoutMetrics
           oldLayoutMetrics:(const LayoutMetrics &)oldLayoutMetrics
{
  // The pager owns the page host's frame; Fabric still owns its visibility and direction.
  bool forceUpdate = oldLayoutMetrics == EmptyLayoutMetrics;
  if (forceUpdate || layoutMetrics.layoutDirection != oldLayoutMetrics.layoutDirection) {
    self.semanticContentAttribute = layoutMetrics.layoutDirection == LayoutDirection::RightToLeft
        ? UISemanticContentAttributeForceRightToLeft
        : UISemanticContentAttributeForceLeftToRight;
  }
  if (forceUpdate || layoutMetrics.displayType != oldLayoutMetrics.displayType) {
    self.hidden = layoutMetrics.displayType == DisplayType::None;
  }
}
#pragma clang diagnostic pop

@end


@interface RNPagerViewComponentView : RCTViewComponentView <RCTRNPagerViewViewProtocol>
@end

@implementation RNPagerViewComponentView {
  RNPagerView *_pagerView;
}

+ (ComponentDescriptorProvider)componentDescriptorProvider
{
  return concreteComponentDescriptorProvider<RNPagerViewComponentDescriptor>();
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if ((self = [super initWithFrame:frame])) {
    static const auto defaultProps = std::make_shared<const RNPagerViewProps>();
    _props = defaultProps;
    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    self.clipsToBounds = NO;

    _pagerView = [[RNPagerView alloc] initWithFrame:self.bounds];
    _pagerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    __weak RNPagerViewComponentView *weakSelf = self;
    _pagerView.stateChangeHandler = ^(NSDictionary *payload) {
      RNPagerViewComponentView *strongSelf = weakSelf;
      if (strongSelf == nil) return;
      auto emitter = std::static_pointer_cast<const RNPagerViewEventEmitter>(strongSelf->_eventEmitter);
      if (emitter != nullptr) {
        emitter->onStateChange(RNPagerStateEvent<RNPagerViewEventEmitter::OnStateChange>(payload));
      }
    };
    _pagerView.pageChangeHandler = ^(NSDictionary *payload) {
      RNPagerViewComponentView *strongSelf = weakSelf;
      if (strongSelf == nil) return;
      auto emitter = std::static_pointer_cast<const RNPagerViewEventEmitter>(strongSelf->_eventEmitter);
      if (emitter != nullptr) {
        RNPagerViewEventEmitter::OnPageChange event{};
        event.page = RNPagerInt(payload, @"page");
        emitter->onPageChange(event);
      }
    };
    _pagerView.pageScrollHandler = ^(NSDictionary *payload) {
      RNPagerViewComponentView *strongSelf = weakSelf;
      if (strongSelf == nil) return;
      auto emitter = std::static_pointer_cast<const RNPagerViewEventEmitter>(strongSelf->_eventEmitter);
      if (emitter != nullptr) {
        emitter->onPageScroll(RNPagerStateEvent<RNPagerViewEventEmitter::OnPageScroll>(payload));
      }
    };
    [super addSubview:_pagerView];
  }
  return self;
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  _pagerView.frame = self.bounds;
}

- (void)updateProps:(const Props::Shared &)props oldProps:(const Props::Shared &)oldProps
{
  const auto &oldViewProps = static_cast<const RNPagerViewProps &>(*_props);
  const auto &newViewProps = static_cast<const RNPagerViewProps &>(*props);

  if (oldViewProps.initialPage != newViewProps.initialPage) {
    _pagerView.initialPage = newViewProps.initialPage;
  }
  if (oldViewProps.orientation != newViewProps.orientation) {
    _pagerView.orientation = newViewProps.orientation == RNPagerViewOrientation::Vertical
        ? RNPagerOrientationVertical
        : RNPagerOrientationHorizontal;
  }
  if (oldViewProps.pageInset != newViewProps.pageInset) {
    _pagerView.pageInset = newViewProps.pageInset;
  }
  if (oldViewProps.pageChangeEventsEnabled != newViewProps.pageChangeEventsEnabled) {
    _pagerView.pageChangeEventsEnabled = newViewProps.pageChangeEventsEnabled;
  }
  if (oldViewProps.pageScrollEventsEnabled != newViewProps.pageScrollEventsEnabled) {
    _pagerView.pageScrollEventsEnabled = newViewProps.pageScrollEventsEnabled;
  }
  if (oldViewProps.pageSpacing != newViewProps.pageSpacing) {
    _pagerView.pageSpacing = newViewProps.pageSpacing;
  }
  if (oldViewProps.scrollEnabled != newViewProps.scrollEnabled) {
    _pagerView.scrollEnabled = newViewProps.scrollEnabled;
  }
  if (oldViewProps.stateEventsEnabled != newViewProps.stateEventsEnabled) {
    _pagerView.stateEventsEnabled = newViewProps.stateEventsEnabled;
  }

  [super updateProps:props oldProps:oldProps];
}

- (void)mountChildComponentView:(UIView<RCTComponentViewProtocol> *)childComponentView index:(NSInteger)index
{
  if (![childComponentView isKindOfClass:RNPagerPageViewComponentView.class]) return;
  [_pagerView mountPage:childComponentView atIndex:index];
}

- (void)unmountChildComponentView:(UIView<RCTComponentViewProtocol> *)childComponentView index:(NSInteger)index
{
  (void)index;
  if (![childComponentView isKindOfClass:RNPagerPageViewComponentView.class]) return;
  [_pagerView unmountPage:childComponentView];
}

- (void)handleCommand:(const NSString *)commandName args:(const NSArray *)args
{
  RCTRNPagerViewHandleCommand(self, commandName, args);
}

- (void)setPage:(NSInteger)page animated:(BOOL)animated
{
  [_pagerView setPage:page animated:animated];
}

- (void)prepareForRecycle
{
  [_pagerView prepareForRemoval];
  const Props::Shared oldProps = _props;
  static const auto defaultProps = std::make_shared<const RNPagerViewProps>();
  [self updateProps:defaultProps oldProps:oldProps];
  [super prepareForRecycle];
}

@end

#endif


@interface RNPagerPageViewManager : RCTViewManager
@end


@implementation RNPagerPageViewManager

RCT_EXPORT_MODULE(RNPagerPageView)

- (UIView *)view
{
  return [[RNPagerPageView alloc] initWithFrame:CGRectZero];
}

@end


@interface RNPagerViewManager : RCTViewManager
@end


@implementation RNPagerViewManager

RCT_EXPORT_MODULE(RNPagerView)

- (UIView *)view
{
  return [[RNPagerView alloc] initWithFrame:CGRectZero];
}

- (void)onDropViewInstance:(RNPagerView *)view
{
  [view prepareForRemoval];
}

RCT_EXPORT_VIEW_PROPERTY(initialPage, NSInteger)
RCT_EXPORT_VIEW_PROPERTY(pageInset, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(pageChangeEventsEnabled, BOOL)
RCT_EXPORT_VIEW_PROPERTY(pageScrollEventsEnabled, BOOL)
RCT_EXPORT_VIEW_PROPERTY(pageSpacing, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(scrollEnabled, BOOL)
RCT_EXPORT_VIEW_PROPERTY(stateEventsEnabled, BOOL)
RCT_EXPORT_VIEW_PROPERTY(onPageChange, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onPageScroll, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onStateChange, RCTDirectEventBlock)

RCT_CUSTOM_VIEW_PROPERTY(orientation, NSString, RNPagerView)
{
  NSString *orientation = [RCTConvert NSString:json] ?: @"horizontal";
  view.orientation = [orientation isEqualToString:@"vertical"] ? RNPagerOrientationVertical : RNPagerOrientationHorizontal;
}

RCT_EXPORT_METHOD(setPage:(nonnull NSNumber *)reactTag page:(NSInteger)page animated:(BOOL)animated)
{
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, UIView *> *viewRegistry) {
    UIView *view = viewRegistry[reactTag];
    if ([view isKindOfClass:RNPagerView.class]) {
      [(RNPagerView *)view setPage:page animated:animated];
    }
  }];
}

@end
