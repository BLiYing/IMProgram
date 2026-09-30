//  IMPendingNotificationRoute.m

#import "IMPendingNotificationRoute.h"
#import "IMDatabase.h"
#import "IMConversation.h"
#import "IMConversationRouter.h"
#import "IMLog.h"
#import "IMSessionStore.h"

static NSInteger const kIMPendingRouteMaxAttempts = 6;      // 约 0.5+1+1.5+2+2.5+3 = 10.5s 总窗口
static NSTimeInterval const kIMPendingRouteBaseInterval = 0.5;

NSString *IMPushConvIDFromUserInfo(NSDictionary *userInfo) {
    id value = userInfo[@"conv_id"];
    if (![value isKindOfClass:NSString.class]) { return nil; }
    NSString *convID = (NSString *)value;
    return convID.length > 0 ? convID : nil;
}

IMConversation *IMPlaceholderConversationForPush(NSString *convID, NSString *selfUID, NSString *title) {
    if (convID.length == 0 || selfUID.length == 0) { return nil; }
    NSString *name = [title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    IMConversation *c = [IMConversation new];
    c.convID = convID;
    if ([convID hasPrefix:@"g_"]) {
        c.isGroup = YES;
        c.name = name.length > 0 ? name : nil;
        return c;
    }
    NSString *prefix = @"u_", *mid = @"_u_";
    if (![convID hasPrefix:prefix]) { return nil; }
    NSString *body = [convID substringFromIndex:prefix.length];
    NSRange r = [body rangeOfString:mid];
    if (r.location == NSNotFound) { return nil; }
    NSString *a = [body substringToIndex:r.location];
    NSString *b = [body substringFromIndex:NSMaxRange(r)];
    if (a.length == 0 || b.length == 0) { return nil; }
    NSString *peer = [a isEqualToString:selfUID] ? b : ([b isEqualToString:selfUID] ? a : nil);
    if (peer.length == 0 || [peer isEqualToString:selfUID]) { return nil; }
    c.isGroup = NO;
    c.peer = peer;
    c.peerNickname = name.length > 0 ? name : nil;
    return c;
}

@implementation IMPendingNotificationRoute {
    NSString *_pendingConvID;
    NSString *_pendingTitle;
    NSInteger _attempts;
}

+ (instancetype)shared {
    static IMPendingNotificationRoute *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [IMPendingNotificationRoute new]; });
    return s;
}

- (void)setPendingConvID:(NSString *)convID title:(NSString *)title {
    if (convID.length == 0) { return; }
    _pendingConvID = [convID copy];
    _pendingTitle = [title copy];
    _attempts = 0;
    // 点通知这一刻 App 常常已经在跑（后台/锁屏点开都不是冷启动，UITabBarController 早就
    // appear 过了，不会再触发一次 viewDidAppear）——不在这里主动试一次的话，只有下次真的
    // 冷启动才会命中 tryRouteWithHost:，表现就是"点通知只是把 App 带到前台，没有跳转"。
    // 冷启动时主界面还没建好，IMSessionStore 里也还没有本次登录的 host/userID，这次尝试
    // 自然落空，交给 IMMainTabBarController viewDidAppear 里的那次兜底。
    [self tryRouteWithHost:IMSessionStore.host ?: @"" userID:IMSessionStore.userID ?: @""];
}

- (void)tryRouteWithHost:(NSString *)host userID:(NSString *)userID {
    if (_pendingConvID.length == 0 || host.length == 0 || userID.length == 0) { return; }
    IMConversation *conversation = [IMDatabase.sharedDatabase cachedConversationWithID:_pendingConvID];
    BOOL placeholder = NO;
    if (!conversation) {
        conversation = IMPlaceholderConversationForPush(_pendingConvID, userID, _pendingTitle);
        placeholder = conversation != nil;
    }
    // 凑出了会话对象只是够格去 push，不代表真的 push 成功了——冷启动早期这里调用时窗口/
    // 导航控制器可能还没建好，opener 会原样报 NO。**只有 openConversation: 真返回 YES 才算数**，
    // 否则和"本地库还没查到这个会话"一样，落进下面的退避重试；不然会出现"日志说已打开、
    // 屏幕上其实什么也没跳"——`setPendingConvID:` 里那次早触发的尝试正是撞在这个窗口上
    // （IMSessionStore 已有 host/userID，但 SceneDelegate 还没把 window.rootViewController
    // 换成真正的主界面），过去因为没检查返回值就当场清掉了 pending，之后 viewDidAppear
    // 兜底那次发现 pending 已经空了，什么都不做（/code-review 之后手测发现的真根因）。
    if (conversation && [IMConversationRouter openConversation:conversation host:host userID:userID]) {
        IMLogPush(@"push_tap_route_opened conv_id=%@ placeholder=%d", _pendingConvID, placeholder);
        _pendingConvID = nil;
        _pendingTitle = nil;
        _attempts = 0;
        return;
    }
    _attempts++;
    if (_attempts >= kIMPendingRouteMaxAttempts) {
        IMLogWarnWithTag(IMLogTagPush, @"push_tap_route_giveup conv_id=%@ attempts=%ld", _pendingConvID, (long)_attempts);
        _pendingConvID = nil;
        _pendingTitle = nil;
        _attempts = 0;
        return;
    }
    __weak typeof(self) ws = self;
    NSTimeInterval delay = kIMPendingRouteBaseInterval * _attempts; // 简单线性退避，够用不必指数
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [ws tryRouteWithHost:host userID:userID];
    });
}

@end
