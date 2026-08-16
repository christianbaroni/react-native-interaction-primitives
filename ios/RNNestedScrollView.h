#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RNScrollAxis) {
  RNScrollAxisHorizontal,
  RNScrollAxisVertical,
};

@interface RNNestedScrollView : UIScrollView
@property (nonatomic, weak, nullable) UIView *interactionBoundsView;
@property (nonatomic, assign) RNScrollAxis scrollAxis;
@property (nonatomic, copy, nullable) dispatch_block_t didBeginContact;
@property (nonatomic, copy, nullable) BOOL (^canBeginPan)(CGPoint velocity);

- (void)cancelReactTouchesForActivePan;
@end

NS_ASSUME_NONNULL_END
