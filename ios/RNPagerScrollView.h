#import "RNPagerView.h"

NS_ASSUME_NONNULL_BEGIN

@interface RNPagerScrollView : UIScrollView
@property (nonatomic, weak, nullable) UIView *interactionBoundsView;
@property (nonatomic, assign) RNPagerOrientation pagerOrientation;
@property (nonatomic, assign) BOOL pagerScrollEnabled;

- (void)prepareForPagerMotion;
- (void)willRemoveContentView:(UIView *)view;
@end

NS_ASSUME_NONNULL_END
