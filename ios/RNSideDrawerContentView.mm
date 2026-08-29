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

- (void)setDrawerScrimEnabled:(BOOL)enabled
{
  if (_scrimView.userInteractionEnabled != enabled) _scrimView.userInteractionEnabled = enabled;
}

- (void)setDrawerOverlayColor:(UIColor *)color
{
  _scrimView.backgroundColor = color;
}

- (void)setDrawerOverlayOpacity:(CGFloat)opacity
{
  CGFloat boundedOpacity = MIN(1, MAX(0, opacity));
  if (_scrimView.alpha != boundedOpacity) _scrimView.alpha = boundedOpacity;
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
