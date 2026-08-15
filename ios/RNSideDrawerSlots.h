#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol RNSideDrawerPanelSlot <NSObject>
@end

@protocol RNSideDrawerContentSlot <NSObject>
@property (nonatomic, copy, nullable) dispatch_block_t onScrimPress;
- (void)setDrawerOverlayColor:(UIColor *)color;
- (void)setDrawerOverlayOpacity:(CGFloat)opacity;
- (void)setDrawerProgress:(CGFloat)progress;
@end

NS_ASSUME_NONNULL_END
