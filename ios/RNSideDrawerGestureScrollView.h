#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RNSideDrawerGestureScrollView : UIScrollView
@property (nonatomic, copy, nullable) dispatch_block_t didBeginContact;
@property (nonatomic, copy, nullable) BOOL (^canBeginDrawerPan)(CGPoint velocity);

// The drawer can pass shouldBegin before competing recognizers resolve.
// Cancel content touches only when scrollViewWillBeginDragging: confirms the drag.
- (void)cancelCompetingTouches;
@end

NS_ASSUME_NONNULL_END
