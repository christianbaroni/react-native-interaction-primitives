#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RNPagerDrawerHapticFeedback : NSObject
@property (nonatomic, copy) NSString *type;

- (void)prepare;
- (void)trigger;
@end

NS_ASSUME_NONNULL_END
