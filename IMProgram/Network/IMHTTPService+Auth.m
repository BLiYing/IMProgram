//  IMHTTPService+Auth.m
//  登录 / token 生命周期：密码登录、续期（refresh_token）、在途合并、TTL 缓存、注册。
//
//  从 IMHTTPService.m 切出来的直接原因是体量红线（CODING_STYLE §7），但这条线本身就该独立：
//  这一族方法共享一套私有状态（currentToken / tokenFetchedAt / 在途登录队列），
//  与上传、好友、会话等接口没有交集。

#import "IMHTTPService+Private.h"
#import "IMDeviceIdentity.h"
#import "IMLog.h"
#import "IMSessionStore.h"
#import "IMSocketManager.h" // IMSocketDidRevokeSessionNotification（续期被拒时复用"被踢下线"通路）
#import "IMUserCard.h"

@implementation IMHTTPService (Auth)

- (void)obtainTokenForUserID:(NSString *)userID
        forceCredentialLogin:(BOOL)forceCredentialLogin
                  completion:(void (^)(NSString *, NSError *))completion {
    // TTL 内同账号直接复用缓存 token：会话列表每次 viewWillAppear 都会走到这里，
    // 不去重就是每切一次页面一次 POST /login（真机日志一分钟内 5 次）。TTL 取 10 分钟，
    // 远小于服务端 24h 过期；异常失效（如服务端换密钥）由下一次 TTL 过期后的重登自愈。
    NSString *cached = self.currentToken;
    if (cached.length > 0 && [self.tokenUserID isEqualToString:userID]
        && CFAbsoluteTimeGetCurrent() - self.tokenFetchedAt < 600) {
        [self callOnMain:^{ completion(cached, nil); }];
        return;
    }
    // 合并在途登录：同账号已有一发在途 → 只排队，回来共享同一枚 token（见属性处说明，防冷启动并发自踢）。
    // 极罕见的"在途中切到别的账号"走独立请求（owner=NO），不动共享队列，避免它的回调丢失。
    BOOL owner = NO;
    @synchronized (self) {
        if (self.loginInFlight && [self.loginInFlightUserID isEqualToString:userID]) {
            if (!self.pendingLoginCompletions) { self.pendingLoginCompletions = [NSMutableArray array]; }
            [self.pendingLoginCompletions addObject:[completion copy]];
            return;
        }
        if (!self.loginInFlight) {
            self.loginInFlight = YES;
            self.loginInFlightUserID = userID;
            self.pendingLoginCompletions = [NSMutableArray arrayWithObject:[completion copy]];
            owner = YES;
        }
    }
    // 设备管理（QR P2）：随登录上报稳定 device_id + 平台/名/版本，后端按 (uid, device_id) 顶替同一台旧会话
    // （避免每次登录堆一行），并在"已登录设备"里展示、可远程踢。字段皆可选，缺省后端按 UA 兜底。
    // 发给后端的必须是 **username**（公开句柄）——登录接口不认内部 ID。
    // userID 参数只作内存缓存键 / 在途合并键。self.username 为空时回退传入值，兼容早期调用路径。
    NSString *loginName = self.username.length > 0 ? self.username : userID;
    BOOL usingRefresh = (!forceCredentialLogin && self.refreshToken.length > 0);
    NSURLRequest *req = usingRefresh
        ? [self postRequestToPath:@"/api/v1/token/refresh" body:@{ @"refresh_token": self.refreshToken }]
        : [self postRequestToPath:@"/api/v1/login"
                             body:@{ @"username": loginName ?: @"", @"password": self.password ?: @"",
                                     @"device_id": IMDeviceIdentity.deviceID,
                                     @"platform": IMDeviceIdentity.platform,
                                     @"device_name": IMDeviceIdentity.deviceName,
                                     @"app_version": IMDeviceIdentity.appVersion }];
    if (!req) {
        [self finishLogin:owner userID:userID token:nil error:[self errorWithMessage:@"非法服务器地址"] soloCompletion:completion];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [self runRequest:req completion:^(NSDictionary *body, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (error) { [self finishLogin:owner userID:userID token:nil error:error soloCompletion:completion]; return; }
        NSDictionary *data = [body[@"data"] isKindOfClass:[NSDictionary class]] ? body[@"data"] : nil;
        NSString *token = [data[@"token"] isKindOfClass:[NSString class]] ? data[@"token"] : nil;
        if ([body[@"code"] integerValue] != 0 || token.length == 0) {
            NSInteger code = [body[@"code"] integerValue];
            // 续期被服务端明确拒绝（凭据不存在/会话已被注销/账号被封）→ 这枚凭据永远不会再好起来：
            // 擦掉它，并复用"被踢下线"那条既有通路把用户送回登录页。
            // 不擦的话，每次进页面都会拿同一枚废凭据重试，界面永远停在"未连接"且没有任何出路
            // （密码已不再落盘，退不回密码登录）。
            if (usingRefresh && IMIsAuthErrorCode(code)) {
                IMLogWarnWithTag(IMLogTagHTTP, @"refresh_rejected code=%ld → 清凭据并回登录页", (long)code);
                self.refreshToken = nil;
                [IMSessionStore saveRefreshToken:nil];
                [NSNotificationCenter.defaultCenter postNotificationName:IMSocketDidRevokeSessionNotification object:nil];
            }
            // 带上业务码，便于调用方区分"鉴权失败(退登录)"与"网络问题(重试)"。
            [self finishLogin:owner userID:userID token:nil
                        error:[self errorWithCode:code message:[self messageFrom:body fallback:@"登录失败"]]
               soloCompletion:completion];
            return;
        }
        // 服务端分配的内部 ID：首次登录时 App 尚不知道自己是谁，只能从这里取。
        NSString *serverUID = [data[@"uid"] isKindOfClass:[NSString class]] ? data[@"uid"] : nil;
        self.lastLoginUserID = serverUID.length > 0 ? serverUID : userID;
        self.currentToken = token; // 缓存：供聊天页等无需重登即可发 HTTP（举报）
        // 缓存键用**服务端返回的内部 ID**：调用方传进来的 userID 在首次登录时是 username，
        // 若拿它当键，随后各处以内部 ID 调用会全部 miss 缓存、每次都真发一次 /login。
        self.tokenUserID = self.lastLoginUserID;
        self.tokenFetchedAt = CFAbsoluteTimeGetCurrent();
        // 收下续期凭据（只有 /login 会下发；续期接口刻意不轮换，见后端 handleTokenRefresh 注释）。
        // **在这里落盘而不是交给登录页**：触发登录的入口不止一个（socket 换 token、冷启动静默重登），
        // 交给各调用方保存必然漏一处。拿到它就把明文密码从内存与磁盘一起清掉——这是第 5 步的目的。
        NSString *refresh = [data[@"refresh_token"] isKindOfClass:NSString.class] ? data[@"refresh_token"] : nil;
        if (refresh.length > 0) {
            self.refreshToken = refresh;
            [IMSessionStore saveRefreshToken:refresh];
            self.password = nil;
            [IMSessionStore clearLegacyPassword];
        }
        [self warmUpMyNicknameWithToken:token];
        [self finishLogin:owner userID:userID token:token error:nil soloCompletion:completion];
    }];
}

/// 收束一次登录：owner=YES 时把共享队列里排队的 completion 全部 fan-out（并清空在途状态）；
/// owner=NO（独立请求）只回 soloCompletion。全部切主线程回调，与旧行为一致。
- (void)finishLogin:(BOOL)owner userID:(NSString *)userID token:(nullable NSString *)token
              error:(nullable NSError *)error soloCompletion:(void (^)(NSString *, NSError *))soloCompletion {
    if (!owner) {
        [self callOnMain:^{ soloCompletion(token, error); }];
        return;
    }
    NSArray *pending;
    @synchronized (self) {
        pending = self.pendingLoginCompletions ?: @[];
        self.pendingLoginCompletions = nil;
        self.loginInFlight = NO;
        self.loginInFlightUserID = nil;
    }
    [self callOnMain:^{
        for (void (^cb)(NSString *, NSError *) in pending) { cb(token, error); }
    }];
}

/// 登录后异步拉一次本人资料，把公开显示名缓存起来（供合并转发标题等**同步**场景取用）。
/// 已有缓存就不重复拉——token 每 10 分钟会因 TTL 重登一次（见 IMServer current_task「已知坑」），
/// 不设这道闸门就会变成每 10 分钟一次无谓请求。失败静默：调用方本就要能降级。
- (void)warmUpMyNicknameWithToken:(NSString *)token {
    if (token.length == 0 || self.currentNickname.length > 0) { return; }
    __weak typeof(self) ws = self;
    [self myProfileWithToken:token completion:^(IMUserCard *card, NSError *err) {
        __strong typeof(ws) self = ws;
        // 取 nickname 而非 displayName：后者是「备注名 > 昵称」，而这个值会被写进**发出去的**
        // 卡片标题——备注仅本人可见，绝不能外流（同 IMConversationPublicName 的纪律）。
        if (!self || err || card.nickname.length == 0) { return; }
        self.currentNickname = card.nickname;
    }];
}

@end
