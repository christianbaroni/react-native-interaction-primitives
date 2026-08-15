#import "RNSideDrawerContentView.h"

#import <React/UIView+React.h>

@implementation RNSideDrawerContentView {
  NSMutableArray<UIView *> *_reactSubviews;
  UIView *_scrimView;
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if ((self = [super initWithFrame:frame])) {
    _reactSubviews = [NSMutableArray arrayWithCapacity:1];
    self.clipsToBounds = YES;

    _scrimView = [[UIView alloc] initWithFrame:self.bounds];
    _scrimView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scrimView.backgroundColor = UIColor.clearColor;
    _scrimView.userInteractionEnabled = NO;
    [_scrimView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleScrimPress)]];
    [super addSubview:_scrimView];
  }
  return self;
}

- (void)handleScrimPress
{
  if (self.onScrimPress != nil) self.onScrimPress();
}

- (void)setDrawerProgress:(CGFloat)progress
{
  _scrimView.userInteractionEnabled = progress > 0.001;
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
  [self bringSubviewToFront:_scrimView];
}
#pragma clang diagnostic pop

@end
