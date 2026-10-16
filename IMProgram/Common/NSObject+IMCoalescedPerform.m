//
//  NSObject+IMCoalescedPerform.m
//

#import "NSObject+IMCoalescedPerform.h"

const NSTimeInterval IMGroupEventCoalesceDelay = 0.25;

@implementation NSObject (IMCoalescedPerform)

- (void)im_coalescedPerform:(SEL)selector afterDelay:(NSTimeInterval)delay {
    [self im_cancelCoalescedPerform:selector];
    [self performSelector:selector withObject:nil afterDelay:delay];
}

- (void)im_cancelCoalescedPerform:(SEL)selector {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:selector object:nil];
}

@end
