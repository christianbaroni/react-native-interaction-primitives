#import <React/RCTComponent.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RNSideDrawerSide) {
  RNSideDrawerSideStart,
  RNSideDrawerSideEnd,
};

@interface RNSideDrawerView : UIView
@property (nonatomic, strong) UIColor *contentBorderColor;
@property (nonatomic, assign) CGFloat contentBorderWidth;
@property (nonatomic, assign) CGFloat contentCornerRadius;
@property (nonatomic, strong) UIColor *contentShadowColor;
@property (nonatomic, assign) CGFloat contentShadowOffsetX;
@property (nonatomic, assign) CGFloat contentShadowOffsetY;
@property (nonatomic, assign) CGFloat contentShadowRadius;
@property (nonatomic, assign) CGFloat drawerWidth;
@property (nonatomic, assign) BOOL gestureEnabled;
@property (nonatomic, copy) NSString *gestureReleaseHaptic;
@property (nonatomic, assign) BOOL initialOpen;
@property (nonatomic, copy) NSArray<NSNumber *> *motionConfig;
@property (nonatomic, assign) CGFloat overdrag;
@property (nonatomic, strong) UIColor *overlayColor;
@property (nonatomic, assign) BOOL progressEventsEnabled;
@property (nonatomic, assign) CGFloat releaseOpenThreshold;
@property (nonatomic, assign) CGFloat releaseVelocitySensitivity;
@property (nonatomic, assign) CGFloat releaseVelocityTransfer;
@property (nonatomic, assign) RNSideDrawerSide side;
@property (nonatomic, assign) CGFloat springDamping;
@property (nonatomic, assign) CGFloat springMass;
@property (nonatomic, assign) CGFloat springStiffness;
@property (nonatomic, assign) BOOL transitionEndEventsEnabled;
@property (nonatomic, assign) BOOL transitionStartEventsEnabled;
@property (nonatomic, copy, nullable) void (^progressHandler)(NSDictionary *payload);
@property (nonatomic, copy, nullable) void (^transitionEndHandler)(NSDictionary *payload);
@property (nonatomic, copy, nullable) void (^transitionStartHandler)(NSDictionary *payload);
@property (nonatomic, copy, nullable) RCTDirectEventBlock onProgress;
@property (nonatomic, copy, nullable) RCTDirectEventBlock onTransitionEnd;
@property (nonatomic, copy, nullable) RCTDirectEventBlock onTransitionStart;

- (void)closeAnimated:(BOOL)animated;
- (void)flushPendingProgressSnapshot;
- (void)insertReactSubview:(UIView *)subview atIndex:(NSInteger)atIndex;
- (void)mountSlot:(UIView *)slot atIndex:(NSInteger)index;
- (void)openAnimated:(BOOL)animated;
- (void)prepareForRemoval;
- (void)removeReactSubview:(UIView *)subview;
- (void)toggleAnimated:(BOOL)animated;
- (void)unmountSlot:(UIView *)slot;
@end

NS_ASSUME_NONNULL_END
