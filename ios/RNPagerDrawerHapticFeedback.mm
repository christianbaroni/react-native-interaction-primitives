#import "RNPagerDrawerHapticFeedback.h"

#import <UIKit/UIImpactFeedbackGenerator.h>
#import <UIKit/UINotificationFeedbackGenerator.h>
#import <UIKit/UISelectionFeedbackGenerator.h>

@interface RNPagerDrawerHapticFeedback ()
- (nullable UIFeedbackGenerator *)generator;
@end

@implementation RNPagerDrawerHapticFeedback {
  UIFeedbackGenerator *_generator;
}

- (instancetype)init
{
  if ((self = [super init])) {
    _type = @"none";
  }
  return self;
}

- (void)setType:(NSString *)type
{
  NSString *nextType = type ?: @"none";
  if ([_type isEqualToString:nextType]) return;
  _type = [nextType copy];
  _generator = nil;
}

- (void)prepare
{
  [[self generator] prepare];
}

- (void)trigger
{
  UIFeedbackGenerator *generator = [self generator];
  if (generator == nil) return;
  if ([generator isKindOfClass:UISelectionFeedbackGenerator.class]) {
    [(UISelectionFeedbackGenerator *)generator selectionChanged];
    return;
  }
  if ([generator isKindOfClass:UINotificationFeedbackGenerator.class]) {
    UINotificationFeedbackType notificationType = UINotificationFeedbackTypeSuccess;
    if ([_type isEqualToString:@"warning"]) notificationType = UINotificationFeedbackTypeWarning;
    if ([_type isEqualToString:@"error"]) notificationType = UINotificationFeedbackTypeError;
    [(UINotificationFeedbackGenerator *)generator notificationOccurred:notificationType];
    return;
  }
  [(UIImpactFeedbackGenerator *)generator impactOccurred];
}

- (nullable UIFeedbackGenerator *)generator
{
  if (_generator != nil) return _generator;
  if ([_type isEqualToString:@"selection"]) {
    _generator = [UISelectionFeedbackGenerator new];
  } else if ([_type isEqualToString:@"success"] || [_type isEqualToString:@"warning"] ||
             [_type isEqualToString:@"error"]) {
    _generator = [UINotificationFeedbackGenerator new];
  } else {
    UIImpactFeedbackStyle style;
    if ([_type isEqualToString:@"light"]) style = UIImpactFeedbackStyleLight;
    else if ([_type isEqualToString:@"medium"]) style = UIImpactFeedbackStyleMedium;
    else if ([_type isEqualToString:@"heavy"]) style = UIImpactFeedbackStyleHeavy;
    else if ([_type isEqualToString:@"soft"]) style = UIImpactFeedbackStyleSoft;
    else if ([_type isEqualToString:@"rigid"]) style = UIImpactFeedbackStyleRigid;
    else return nil;
    _generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:style];
  }
  return _generator;
}

@end
