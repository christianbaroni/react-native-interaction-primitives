#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RNPagerPageView : UIView
- (void)insertReactSubview:(UIView *)subview atIndex:(NSInteger)atIndex;
- (void)removeReactSubview:(UIView *)subview;
@end

NS_ASSUME_NONNULL_END
