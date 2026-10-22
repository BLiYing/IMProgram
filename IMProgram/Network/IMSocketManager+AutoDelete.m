//  IMSocketManager+AutoDelete.m

#import "IMSocketManager+AutoDelete.h"
#import "IMDatabase+AutoDelete.h"
#import "IMAutoDelete.h"
#import "IMAutoDeleteScheduler.h"

@implementation IMSocketManager (AutoDelete)

- (void)applyAutoDeleteFromConvUpdate:(NSDictionary *)data convID:(NSString *)convID database:(IMDatabase *)database {
    if (convID.length == 0 || ![data[@"auto_delete_sec"] isKindOfClass:NSNumber.class]) { return; }
    // sec 与 from 必须一起覆盖（缺 from 的 sec>0 视为老服务端个人档位，当关闭：from=0 会追溯清掉整段历史）。
    IMAutoDeleteConfig *cfg = IMAutoDeleteConfigFromJSON(data[@"auto_delete_sec"], data[@"auto_delete_from"]);
    BOOL changed = [database setAutoDeleteConfig:cfg forConv:convID];
    if (!changed || !cfg.active) { return; } // sec 或 from 变了且 sec>0 才扫（不再有「开启即清历史」：新 from 之前的消息不会被清）
    dispatch_async(dispatch_get_main_queue(), ^{ [IMAutoDeleteScheduler.shared requestSweepForConv:convID]; });
}

@end
