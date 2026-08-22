#import <React/RCTComponent.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RNPagerOrientation) {
  RNPagerOrientationHorizontal,
  RNPagerOrientationVertical,
};

@interface RNPagerView : UIView
@property (nonatomic, assign) NSInteger initialPage;
@property (nonatomic, assign) RNPagerOrientation orientation;
@property (nonatomic, assign) CGFloat pageInset;
@property (nonatomic, assign) BOOL pageChangeEventsEnabled;
@property (nonatomic, assign) BOOL pageScrollEventsEnabled;
@property (nonatomic, assign) CGFloat pageSpacing;
@property (nonatomic, assign) BOOL scrollEnabled;
@property (nonatomic, assign) BOOL stateEventsEnabled;
@property (nonatomic, copy, nullable) void (^pageChangeHandler)(NSDictionary *payload);
@property (nonatomic, copy, nullable) void (^pageScrollHandler)(NSDictionary *payload);
@property (nonatomic, copy, nullable) void (^stateChangeHandler)(NSDictionary *payload);
@property (nonatomic, copy, nullable) RCTDirectEventBlock onPageChange;
@property (nonatomic, copy, nullable) RCTDirectEventBlock onPageScroll;
@property (nonatomic, copy, nullable) RCTDirectEventBlock onStateChange;

- (void)mountPage:(UIView *)page atIndex:(NSInteger)index;
- (void)unmountPage:(UIView *)page;
- (void)insertReactSubview:(UIView *)subview atIndex:(NSInteger)atIndex;
- (void)removeReactSubview:(UIView *)subview;
- (void)setPage:(NSInteger)page animated:(BOOL)animated;
- (void)flushPendingPageScrollSnapshot;
- (void)prepareForRemoval;
@end

NS_ASSUME_NONNULL_END
