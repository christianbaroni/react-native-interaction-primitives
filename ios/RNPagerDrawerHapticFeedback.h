#import <Foundation/Foundation.h>
#import <CoreGraphics/CGGeometry.h>

@class UIView;

NS_ASSUME_NONNULL_BEGIN

@interface RNPagerDrawerHapticFeedback : NSObject
@property (nonatomic, copy) NSString *type;

- (instancetype)initWithView:(UIView *)view NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (void)prepare;
- (void)triggerAtLocation:(CGPoint)location;
@end

NS_ASSUME_NONNULL_END
