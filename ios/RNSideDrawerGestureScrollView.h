#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RNSideDrawerGestureScrollView : UIScrollView
@property (nonatomic, copy, nullable) dispatch_block_t didBeginContact;
@property (nonatomic, copy, nullable) BOOL (^canBeginDrawerPan)(CGPoint velocity);

- (void)cancelReactTouchesForActivePan;
@end

NS_ASSUME_NONNULL_END
