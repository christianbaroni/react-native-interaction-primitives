#import <React/RCTComponent.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RNSideDrawerSide) {
  RNSideDrawerSideStart,
  RNSideDrawerSideEnd,
};

@interface RNSideDrawerView : UIView
@property (nonatomic, assign) CGFloat contentCornerRadius;
@property (nonatomic, assign) CGFloat drawerWidth;
@property (nonatomic, assign) BOOL gestureEnabled;
@property (nonatomic, assign) BOOL initialOpen;
@property (nonatomic, copy) NSArray<NSNumber *> *motionConfig;
@property (nonatomic, assign) BOOL openChangeEventsEnabled;
@property (nonatomic, strong) UIColor *overlayColor;
@property (nonatomic, assign) BOOL progressEventsEnabled;
@property (nonatomic, assign) RNSideDrawerSide side;
@property (nonatomic, copy, nullable) void (^openChangeHandler)(NSDictionary *payload);
@property (nonatomic, copy, nullable) void (^progressHandler)(NSDictionary *payload);
@property (nonatomic, copy, nullable) RCTDirectEventBlock onOpenChange;
@property (nonatomic, copy, nullable) RCTDirectEventBlock onProgress;

- (void)closeAnimated:(BOOL)animated;
- (void)insertReactSubview:(UIView *)subview atIndex:(NSInteger)atIndex;
- (void)mountSlot:(UIView *)slot atIndex:(NSInteger)index;
- (void)openAnimated:(BOOL)animated;
- (void)prepareForRemoval;
- (void)removeReactSubview:(UIView *)subview;
- (void)toggleAnimated:(BOOL)animated;
- (void)unmountSlot:(UIView *)slot;
@end

NS_ASSUME_NONNULL_END
