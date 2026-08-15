#import <UIKit/UIKit.h>

#import "RNSideDrawerSlots.h"

NS_ASSUME_NONNULL_BEGIN

@interface RNSideDrawerContentView : UIView <RNSideDrawerContentSlot>
@property (nonatomic, copy, nullable) dispatch_block_t onScrimPress;

- (void)insertReactSubview:(UIView *)subview atIndex:(NSInteger)atIndex;
- (void)removeReactSubview:(UIView *)subview;
- (void)setDrawerProgress:(CGFloat)progress;
@end

NS_ASSUME_NONNULL_END
