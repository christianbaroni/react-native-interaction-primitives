#import "RNInteractionHapticFeedback.h"

#import <UIKit/UIImpactFeedbackGenerator.h>
#import <UIKit/UINotificationFeedbackGenerator.h>
#import <UIKit/UISelectionFeedbackGenerator.h>

@interface RNInteractionHapticFeedback ()
- (void)clearGenerator;
- (nullable UIFeedbackGenerator *)generator;
@end

@implementation RNInteractionHapticFeedback {
  __weak UIView *_view;
  UIFeedbackGenerator *_generator;
}

- (instancetype)initWithView:(UIView *)view
{
  if ((self = [super init])) {
    _view = view;
    _type = @"none";
  }
  return self;
}

- (void)dealloc
{
  [self clearGenerator];
}

- (void)setType:(NSString *)type
{
  NSString *nextType = type ?: @"none";
  if ([_type isEqualToString:nextType]) return;
  _type = [nextType copy];
  [self clearGenerator];
}

- (void)prepare
{
  [[self generator] prepare];
}

- (void)triggerAtLocation:(CGPoint)location
{
  UIFeedbackGenerator *generator = [self generator];
  if (generator == nil) return;
  if ([generator isKindOfClass:UISelectionFeedbackGenerator.class]) {
    UISelectionFeedbackGenerator *selectionGenerator = (UISelectionFeedbackGenerator *)generator;
    if (@available(iOS 17.5, *)) {
      [selectionGenerator selectionChangedAtLocation:location];
    } else {
      [selectionGenerator selectionChanged];
    }
    return;
  }
  if ([generator isKindOfClass:UINotificationFeedbackGenerator.class]) {
    UINotificationFeedbackType notificationType = UINotificationFeedbackTypeSuccess;
    if ([_type isEqualToString:@"warning"]) notificationType = UINotificationFeedbackTypeWarning;
    if ([_type isEqualToString:@"error"]) notificationType = UINotificationFeedbackTypeError;
    UINotificationFeedbackGenerator *notificationGenerator = (UINotificationFeedbackGenerator *)generator;
    if (@available(iOS 17.5, *)) {
      [notificationGenerator notificationOccurred:notificationType atLocation:location];
    } else {
      [notificationGenerator notificationOccurred:notificationType];
    }
    return;
  }
  UIImpactFeedbackGenerator *impactGenerator = (UIImpactFeedbackGenerator *)generator;
  if (@available(iOS 17.5, *)) {
    [impactGenerator impactOccurredAtLocation:location];
  } else {
    [impactGenerator impactOccurred];
  }
}

- (void)clearGenerator
{
  if (_generator == nil) return;
  if (@available(iOS 17.5, *)) {
    id<UIInteraction> interaction = (id<UIInteraction>)_generator;
    [interaction.view removeInteraction:interaction];
  }
  _generator = nil;
}

- (nullable UIFeedbackGenerator *)generator
{
  if (_generator != nil) return _generator;
  UIView *view = _view;
  if (view == nil) return nil;

  if ([_type isEqualToString:@"selection"]) {
    if (@available(iOS 17.5, *)) {
      _generator = [UISelectionFeedbackGenerator feedbackGeneratorForView:view];
    } else {
      _generator = [UISelectionFeedbackGenerator new];
    }
  } else if ([_type isEqualToString:@"success"] || [_type isEqualToString:@"warning"] ||
             [_type isEqualToString:@"error"]) {
    if (@available(iOS 17.5, *)) {
      _generator = [UINotificationFeedbackGenerator feedbackGeneratorForView:view];
    } else {
      _generator = [UINotificationFeedbackGenerator new];
    }
  } else {
    UIImpactFeedbackStyle style;
    if ([_type isEqualToString:@"light"]) style = UIImpactFeedbackStyleLight;
    else if ([_type isEqualToString:@"medium"]) style = UIImpactFeedbackStyleMedium;
    else if ([_type isEqualToString:@"heavy"]) style = UIImpactFeedbackStyleHeavy;
    else if ([_type isEqualToString:@"soft"]) style = UIImpactFeedbackStyleSoft;
    else if ([_type isEqualToString:@"rigid"]) style = UIImpactFeedbackStyleRigid;
    else return nil;
    if (@available(iOS 17.5, *)) {
      _generator = [UIImpactFeedbackGenerator feedbackGeneratorWithStyle:style forView:view];
    } else {
      _generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:style];
    }
  }
  return _generator;
}

@end
