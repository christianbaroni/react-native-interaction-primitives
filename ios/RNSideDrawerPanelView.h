#import <UIKit/UIKit.h>

#import "RNSideDrawerSlots.h"

NS_ASSUME_NONNULL_BEGIN

@interface RNSideDrawerPanelView : UIView <RNSideDrawerPanelSlot>
- (void)insertReactSubview:(UIView *)subview atIndex:(NSInteger)atIndex;
- (void)removeReactSubview:(UIView *)subview;
@end

NS_ASSUME_NONNULL_END
