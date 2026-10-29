//  IMClearAll.m

#import "IMClearAll.h"
#import "IMLocalization.h"
#import "IMLog.h"
#import "IMConversation.h"
#import "IMSessionTeardown.h"
#import "IMSocketManager.h"
#import "IMSocketManager+ClearAll.h"
#import "IMUnreadBadge.h"
#import "IMViewedMediaStore.h"
#import <UserNotifications/UserNotifications.h>

@implementation IMClearAllResult
- (instancetype)initWithCleared:(NSInteger)cleared items:(NSArray<IMClearAllItem *> *)items {
    self = [super init];
    if (self) { _cleared = cleared; _items = [items copy]; }
    return self;
}
@end

IMClearAllResult *IMClearAllParseResponse(id data) {
    if (![data isKindOfClass:NSDictionary.class]) { return nil; }
    NSMutableArray<IMClearAllItem *> *items = [NSMutableArray array];
    id raw = ((NSDictionary *)data)[@"items"];
    if ([raw isKindOfClass:NSArray.class]) {
        for (id one in (NSArray *)raw) {
            if (![one isKindOfClass:NSDictionary.class]) { continue; }
            id cid = ((NSDictionary *)one)[@"conv_id"];
            if (![cid isKindOfClass:NSString.class] || [(NSString *)cid length] == 0) { continue; }
            [items addObject:[[IMClearAllItem alloc] initWithConvID:cid clearedAt:IMClearedAtFromJSON(((NSDictionary *)one)[@"cleared_at"])]];
        }
    }
    id c = ((NSDictionary *)data)[@"cleared"];
    NSInteger cleared = [c isKindOfClass:NSNumber.class] ? [c integerValue] : (NSInteger)items.count;
    return [[IMClearAllResult alloc] initWithCleared:MAX(cleared, 0) items:items];
}

NSString *IMClearAllToastText(NSInteger n) {
    return n > 0 ? IMLocalizedFormat(@"privacy.clear_all.done", (long)n) : IMLocalized(@"privacy.clear_all.none");
}

NSString *IMClearAllConfirmBody(NSInteger n) {
    return IMLocalizedFormat(@"privacy.clear_all.confirm_body", (long)MAX(n, 0));
}

@implementation IMClearAll

+ (void)applyResult:(IMClearAllResult *)result completion:(void (^)(BOOL))completion {
    NSArray<NSURL *> *dirs = IMSessionTeardown.ownedMediaCacheDirectories;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL applied = [IMSocketManager.sharedManager applyClearAllItems:result.items];
        // 服务端已清、本机库落地失败：位点只增不减、清理幂等，立刻再试一次（瞬时的库繁忙 / 锁），省得本机旧记录靠回声才补上
        if (!applied) { applied = [IMSocketManager.sharedManager applyClearAllItems:result.items]; }
        if (!applied) { IMLogWarnWithTag(IMLogTagDatabase, @"clear_all_db_failed items=%lu（服务端已清，等 conv_update 回声补）", (unsigned long)result.items.count); }
        for (NSURL *dir in dirs) { [NSFileManager.defaultManager removeItemAtURL:dir error:NULL]; }
        dispatch_async(dispatch_get_main_queue(), ^{
            [IMViewedMediaStore.shared clearCurrentUser]; // 本地副本没了：回到没看过，门控按策略重判
            [UNUserNotificationCenter.currentNotificationCenter removeAllDeliveredNotifications];
            IMApplyAppIconBadge(0);
            [NSNotificationCenter.defaultCenter postNotificationName:IMSocketDidUpdateConversationNotification
                                                              object:IMSocketManager.sharedManager userInfo:nil]; // 列表 / Tab 红点据本地库重算
            IMLog(@"清除所有对话 本机落地 items=%lu db=%d", (unsigned long)result.items.count, applied);
            completion(applied);
        });
    });
}

@end
