//  IMSocketManager+AutoDelete.m

#import "IMSocketManager+AutoDelete.h"
#import "IMDatabase+AutoDelete.h"
#import "IMAutoDelete.h"
#import "IMAutoDeleteScheduler.h"

@implementation IMSocketManager (AutoDelete)

- (void)applyAutoDeleteFromConvUpdate:(NSDictionary *)data convID:(NSString *)convID database:(IMDatabase *)database {
    if (convID.length == 0 || ![data[@"auto_delete_sec"] isKindOfClass:NSNumber.class]) { return; }
    int64_t sec = IMAutoDeleteSecFromJSON(data[@"auto_delete_sec"]);
    [database setAutoDeleteSec:sec forConv:convID];
    if (sec <= 0) { return; }
    dispatch_async(dispatch_get_main_queue(), ^{ [IMAutoDeleteScheduler.shared requestSweepForConv:convID]; });
}

@end
