#import "RNSideDrawerPanelView.h"

#import <React/UIView+React.h>

@implementation RNSideDrawerPanelView {
  NSMutableArray<UIView *> *_reactSubviews;
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if ((self = [super initWithFrame:frame])) {
    _reactSubviews = [NSMutableArray arrayWithCapacity:1];
    self.clipsToBounds = NO;
  }
  return self;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-missing-super-calls"
- (void)reactSetFrame:(CGRect)frame
{
  (void)frame;
}

- (NSArray<UIView *> *)reactSubviews
{
  return [_reactSubviews copy];
}

- (void)insertReactSubview:(UIView *)subview atIndex:(NSInteger)atIndex
{
  NSUInteger index = MIN((NSUInteger)MAX(atIndex, 0), _reactSubviews.count);
  [_reactSubviews insertObject:subview atIndex:index];
  [super insertSubview:subview atIndex:index];
}

- (void)removeReactSubview:(UIView *)subview
{
  [_reactSubviews removeObjectIdenticalTo:subview];
  [subview removeFromSuperview];
}

- (void)didUpdateReactSubviews
{
}
#pragma clang diagnostic pop

@end
