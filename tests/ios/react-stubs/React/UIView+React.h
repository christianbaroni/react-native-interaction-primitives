#import <UIKit/UIKit.h>

@interface UIView (NativeTestDeclarations)
- (void)reactSetFrame:(CGRect)frame;
- (NSArray<UIView *> *)reactSubviews;
- (void)insertReactSubview:(UIView *)subview atIndex:(NSInteger)atIndex;
- (void)removeReactSubview:(UIView *)subview;
- (void)didUpdateReactSubviews;
@end
