//  IMAnimator.m

#import "IMAnimator.h"

@implementation IMAnimator

+ (void)springPopIn:(UIView *)view {
    view.transform = CGAffineTransformMakeScale(0.8, 0.8);
    view.alpha = 0;
    [UIView animateWithDuration:0.42 delay:0
         usingSpringWithDamping:0.7 initialSpringVelocity:0.6
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        view.transform = CGAffineTransformIdentity;
        view.alpha = 1;
    } completion:nil];
}

+ (void)tapBounce:(UIView *)view {
    [UIView animateWithDuration:0.08 animations:^{
        view.transform = CGAffineTransformMakeScale(0.95, 0.95);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.3 delay:0
             usingSpringWithDamping:0.5 initialSpringVelocity:0.8
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            view.transform = CGAffineTransformIdentity;
        } completion:nil];
    }];
}

+ (void)lightImpact {
    UIImpactFeedbackGenerator *gen =
        [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [gen prepare];
    [gen impactOccurred];
}

+ (void)selectionChanged {
    UISelectionFeedbackGenerator *gen = [UISelectionFeedbackGenerator new];
    [gen prepare];
    [gen selectionChanged];
}

@end
