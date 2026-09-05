//  IMHTTPService.m

#import "IMHTTPService+Private.h" // 类扩展（私有存储属性）与分文件 category 的共享内部接口
#import "IMServerEndpoint.h"
#import "IMConversation.h"
#import "IMUserCard.h"
#import "IMGroupInfo.h"
#import "IMPinnedMessage.h"
#import "IMDeviceModels.h"
#import "IMDeviceIdentity.h"
#import "IMHTTPLogFormatter.h"
#import "IMLog.h"
#import "IMFriendStateStore.h"
#import "IMSessionStore.h"
#import "IMSocketManager.h" // IMSocketDidRevokeSessionNotification（续期被拒时复用"被踢下线"通路）
#import "IMRemarkStore.h"

static NSString * const kIMHTTPErrorDomain = @"IMHTTPService";
static NSString * const kIMRequestIDHeader = @"X-Request-ID";

static BOOL IMHTTPLogIncludesBusinessContent(void) {
#ifdef DEBUG
    return YES;
#else
    return NO;
#endif
}

/// 上传进度桥（iOS 15+ per-task delegate）：completionHandler 任务仍会收到 didSendBodyData，
/// 借此把 multipart 上行字节进度回给调用方（主线程 0..1）。task 强持有本对象，无需外部保活。
@interface IMUploadProgressBridge : NSObject <NSURLSessionTaskDelegate>
@property (nonatomic, copy, nullable) void (^onProgress)(double fraction);
@end

@implementation IMUploadProgressBridge
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
   didSendBodyData:(int64_t)bytesSent
    totalBytesSent:(int64_t)totalBytesSent
totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend {
    if (totalBytesExpectedToSend <= 0 || !self.onProgress) { return; }
    double f = MIN(1.0, (double)totalBytesSent / (double)totalBytesExpectedToSend);
    void (^cb)(double) = self.onProgress;
    dispatch_async(dispatch_get_main_queue(), ^{ cb(f); });
}
@end

// 是否"鉴权失败"类错误码（账号/密码/封禁/token）→ 调用方应退回登录页，而非当网络问题重试。
BOOL IMIsAuthErrorCode(NSInteger code) {
    switch (code) {
        case 200001: // 用户不存在
        case 200002: // 密码错误
        case 200003: // 账号被封
        case 100101: // token 无效
        case 100102: // token 过期
            return YES;
        default:
            return NO;
    }
}

/// 业务错误码 → 友好中文（对齐 errcode）。未收录返回 nil，回退服务端原文。
/// 隐私：被拉黑/密码错误等用模糊文案，不暴露"你被对方拉黑了"。
/// 2026-08-25：从 static 提升为文件外可见，供 WS 拒收路径（IMSocketManager.handleSendRejected）复用，
/// 让被禁言/全员禁言等 send_msg 拒收错误也走同一中文映射（否则 error.localizedDescription = 英文原文）。
NSString *IMFriendlyMessageForCode(NSInteger code) {
    switch (code) {
        case 100101: case 100102: return @"登录已失效，请重新登录"; // invalid / expired token
        case 200001: return @"用户不存在";                          // user not found
        case 200002: return @"密码错误";                            // wrong password
        case 200003: return @"账号已被封禁";                        // account banned
        case 200004: return @"用户名已被注册";                      // user already exists
        case 300004: return @"账号已被禁言";                        // account muted（全局禁言）
        case 300206: return @"本群已开启全员禁言";                  // group all-muted（G2）
        case 200101: return @"你们已经是好友了";                    // already friends
        case 200102: return @"暂时无法添加对方为好友";              // blocked by peer（不暴露拉黑）
        case 200103: return @"对方不是你的好友";                    // not friend
        case 200104: return @"不能添加自己为好友";                  // cannot add yourself
        case 200105: return @"申请已发出，等待对方同意";            // request pending
        case 200106: return @"没有待处理的好友申请";                // no pending request
        case 200110: return @"二维码已失效，请向对方索取新的";      // qr expired（QRCODE P0）
        case 300201: return @"群不存在";                            // group not found
        case 300202: return @"群名不能为空且不超过 30 字";          // invalid group name
        case 300203: return @"你不在该群中";                        // not a group member
        // 300204 不映射：服务端会带具体原因（如"群主需先转让群主再退群"），透传更有用。
        case 300205: return @"群成员已达上限";                      // group member limit
        case 300207: return @"你已被移出该群，暂时或永久不可加入";  // banned from group（G2）
        case 300208: return @"你已被管理员禁言";                    // member muted（G2）
        // 300210 不映射：入群申请已提交，UI 走"待审批"分支而非错误提示。
        case 300211: return @"你的入群申请刚被拒绝，请稍后再试";    // join cooldown（拒后再扫码，语义单一可安全映射）
        case 300212: return @"该群已改为仅管理员可邀请，此邀请已失效"; // invite revoked（perm_invite，竞态兜底）
        case 100002: return @"操作过于频繁，请稍后再试";              // rate limited（全站通用码）
        case 500101: return @"转文字暂未开启（服务端未配置识别引擎）"; // transcribe disabled
        case 500102: return @"识别失败，请稍后重试";                  // transcribe failed
        case 500103: return @"转文字服务繁忙，请稍后再试";            // transcribe busy（队列满）
        default: return nil;
    }
}

/// 传输层错误（连不上 / 超时 / 无网络）→ 友好中文。区别于业务错误码：这类在拿到 JSON 前就失败。
static NSString *IMFriendlyNetworkError(NSError *error) {
    if ([error.domain isEqualToString:NSURLErrorDomain]) {
        switch (error.code) {
            case NSURLErrorCannotConnectToHost:
            case NSURLErrorCannotFindHost:
            case NSURLErrorTimedOut:
            case NSURLErrorNetworkConnectionLost:
                return @"无法连接服务器，请确认后端已启动、地址端口正确";
            case NSURLErrorNotConnectedToInternet:
                return @"网络未连接，请检查网络";
            default: break;
        }
    }
    return error.localizedDescription.length > 0 ? error.localizedDescription : @"网络错误";
}

/// 上传失败自动重试的次数上限（不含首次）。
static const NSInteger kIMUploadMaxRetries = 2;

/// 是否"重试有意义"的传输层错误：超时/连接中断/网络切换。
/// 业务错误（413 超限、鉴权失败）重试只是白费流量，必须排除。
BOOL IMIsTransientNetworkError(NSError *error) {
    NSError *underlying = error.userInfo[NSUnderlyingErrorKey] ?: error;
    if (![underlying.domain isEqualToString:NSURLErrorDomain]) { return NO; }
    switch (underlying.code) {
        case NSURLErrorTimedOut:
        case NSURLErrorNetworkConnectionLost:
        case NSURLErrorCannotConnectToHost:
        case NSURLErrorNotConnectedToInternet:
        case NSURLErrorDNSLookupFailed:
            return YES;
        default:
            return NO;
    }
}

@implementation IMHTTPService

+ (instancetype)sharedService {
    static IMHTTPService *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [IMHTTPService new]; });
    return instance;
}

// 登录 / token 生命周期的**公开入口**留在主实现：这几个方法声明在 IMHTTPService.h 上，
// 放进 category 会同时触发 -Wincomplete-implementation 与
// "category is implementing a method which will also be implemented by its primary class"。
// 真正的实现细节（续期 vs 密码登录的分流、在途合并、TTL 缓存）在 IMHTTPService+Auth.m。
- (void)loginWithUserID:(NSString *)userID
             completion:(void (^)(NSString *, NSError *))completion {
    // 内部各处（socket 换 token、页面进入时兜底）走这条：**优先续期**，没有续期凭据才退回密码登录。
    [self obtainTokenForUserID:userID forceCredentialLogin:NO completion:completion];
}

/// 取一枚可用 access token。两条来源共用同一套「TTL 缓存 / 在途合并 / 响应解析」，只有请求本身不同：
///   - 续期（默认）：POST /api/v1/token/refresh，凭 refreshToken，不碰密码；
///   - 凭据登录（forceCredentialLogin=YES，或压根没有 refreshToken）：POST /api/v1/login。
///
/// 登录页必须 forceCredentialLogin=YES——用户刚输入的密码就是要拿去验的，
/// 此刻若走续期就变成"密码填错也能进"（本地还留着上一个账号的有效凭据）。

- (void)invalidateToken {
    // 注意**不动 refreshToken**：这里作废的是 10 分钟 TTL 的 access token 缓存，
    // 而续期凭据是长效的、由登录/退登/被拒三处管理。顺手清掉它会让"换 host 重连"退化成必须重输密码。
    self.currentNickname = nil; // 换账号必须一起清，否则新账号会顶着旧账号的名字打包转发卡片
    self.currentToken = nil;
    self.tokenUserID = nil;
    self.tokenFetchedAt = 0;
}

- (void)loginWithUsername:(NSString *)username
               completion:(void (^)(NSString *, NSString *, NSError *))completion {
    self.username = username;
    __weak typeof(self) weakSelf = self;
    // 复用 loginWithUserID: 的在途合并与错误处理；userID 传 username 仅作本次的去重键，
    // 真正的内部 ID 由响应带回（见 lastLoginUserID）。
    // forceCredentialLogin=YES：用户刚输入的密码就是要拿去验的。走续期的话，本地若还留着上一个
    // 账号的有效凭据，密码填错也会"登录成功"。
    [self obtainTokenForUserID:username forceCredentialLogin:YES completion:^(NSString *token, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        completion(token, token.length > 0 ? self.lastLoginUserID : nil, error);
    }];
}

- (void)registerWithUsername:(NSString *)username
                    password:(NSString *)password
                    nickname:(NSString *)nickname
                  completion:(void (^)(NSError *))completion {
    NSMutableURLRequest *req = [self postRequestToPath:@"/api/v1/register"
                                                  body:@{ @"username": username ?: @"",
                                                          @"password": password ?: @"",
                                                          @"nickname": nickname ?: @"" }];
    [self runOKRequest:req fallback:@"注册失败" completion:completion];
}

- (void)updateUsername:(NSString *)username
                 token:(NSString *)token
            completion:(void (^)(NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/users/me/username" method:@"POST"
                                                    token:token body:@{ @"username": username ?: @"" }];
    [self runOKRequest:req fallback:@"修改用户名失败" completion:completion];
}

- (void)conversationsWithToken:(NSString *)token
                    completion:(void (^)(NSArray<IMConversation *> *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/conversations" method:@"GET" token:token body:nil];
    [self runDataRequest:req fallback:@"拉取会话失败" completion:^(NSDictionary *data, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSArray<IMConversation *> *convs = [IMConversation conversationsFromArray:data[@"conversations"]];
        // 备注名喂进全局缓存放在这一层（而非各调用方）：会话列表/转发选择/详情页都走这个方法，
        // 逐个 VC 去 ingest 早晚漏一个，漏了那页就显真实昵称、与别处不一致。
        // peer_remark 只覆盖出现过的对端（会话列表不是好友全集），故非权威全集。
        [IMRemarkStore.sharedStore ingestConversations:convs];
        completion(convs, nil);
    }];
}

- (void)downloadSettingsWithToken:(NSString *)token
                       completion:(void (^)(NSDictionary *_Nullable data, NSError *_Nullable error))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/download-settings" method:@"GET" token:token body:nil];
    [self runDataRequest:req fallback:@"拉取下载设置失败" completion:^(NSDictionary *data, NSError *error) {
        // 调用方以 nil 表示"没拿到设置"（保留旧值）；空字典还原为 nil，语义同手写版。
        completion(data.count > 0 ? data : nil, error);
    }];
}

- (void)updateDownloadSettingsWithToken:(NSString *)token
                               settings:(NSDictionary *)settings
                             completion:(void (^)(NSDictionary *_Nullable data, NSError *_Nullable error))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/download-settings" method:@"PUT" token:token body:(settings ?: @{})];
    [self runDataRequest:req fallback:@"保存下载设置失败" completion:^(NSDictionary *data, NSError *error) {
        completion(data.count > 0 ? data : nil, error); // nil=没拿到回执，调用方据此回滚
    }];
}

- (void)resetDownloadSettingsWithToken:(NSString *)token
                            completion:(void (^)(NSDictionary *_Nullable data, NSError *_Nullable error))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/download-settings/reset" method:@"POST" token:token body:@{}];
    [self runDataRequest:req fallback:@"重置下载设置失败" completion:^(NSDictionary *data, NSError *error) {
        completion(data.count > 0 ? data : nil, error); // nil=没拿到回执，调用方重拉刷新
    }];
}

#pragma mark - 通讯录（找人 / 好友关系）

- (void)searchUsersWithToken:(NSString *)token
                       query:(NSString *)query
                  completion:(void (^)(NSArray<IMUserCard *> *, NSError *))completion {
    NSString *q = [query stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet] ?: @"";
    NSString *path = [NSString stringWithFormat:@"/api/v1/users/search?q=%@&limit=20", q];
    NSMutableURLRequest *req = [self authedRequestForPath:path method:@"GET" token:token body:nil];
    [self runDataRequest:req fallback:@"搜索失败" completion:^(NSDictionary *data, NSError *error) {
        completion(error ? nil : [IMUserCard cardsFromArray:data[@"users"]], error);
    }];
}

- (void)usersBatchWithToken:(NSString *)token
                    userIDs:(NSArray<NSString *> *)userIDs
                 completion:(void (^)(NSArray<IMUserCard *> *, NSArray<NSString *> *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/users/batch" method:@"POST" token:token
                                                     body:@{@"ids": userIDs ?: @[]}];
    [self runDataRequest:req fallback:@"解析用户资料失败" completion:^(NSDictionary *data, NSError *error) {
        if (error) { completion(nil, nil, error); return; }
        NSArray *missing = [data[@"missing"] isKindOfClass:NSArray.class] ? data[@"missing"] : @[];
        completion([IMUserCard cardsFromArray:data[@"users"]], missing, nil);
    }];
}

- (void)friendsWithToken:(NSString *)token
                  status:(NSString *)status
              completion:(void (^)(NSArray<IMUserCard *> *, NSError *))completion {
    NSString *path = @"/api/v1/friends";
    if (status.length > 0) {
        path = [path stringByAppendingFormat:@"?status=%@", status];
    }
    // 不带 status（全部）/ accepted 才是"能有备注的关系"的全集，可用于清扫本地已被清空的备注；
    // blocked/pending 等是子集，只补不清（否则会把其他好友的备注误清空）。
    BOOL authoritative = (status.length == 0 || [status isEqualToString:@"accepted"]);
    NSMutableURLRequest *req = [self authedRequestForPath:path method:@"GET" token:token body:nil];
    [self runDataRequest:req fallback:@"拉取好友失败" completion:^(NSDictionary *data, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSArray<IMUserCard *> *friends = [IMUserCard cardsFromArray:data[@"friends"]];
        [IMRemarkStore.sharedStore ingestFriends:friends authoritative:authoritative];
        // 同一批数据顺路刷新「谁是我的好友」进程内快照：资料页 init 那一刻据此决定显示
        // 好友视图还是「加好友」视图，不必先猜一个再被网络结果推翻（见 IMFriendStateStore.h）。
        [IMFriendStateStore.sharedStore ingestFriends:friends authoritative:authoritative];
        completion(friends, nil);
    }];
}

- (void)reportWithToken:(NSString *)token
             targetType:(NSString *)targetType
               targetID:(NSString *)targetID
                 convID:(NSString *)convID
                 reason:(NSString *)reason
             completion:(void (^)(NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/reports" method:@"POST" token:token
        body:@{ @"target_type": targetType ?: @"", @"target_id": targetID ?: @"",
                @"conv_id": convID ?: @"", @"reason": reason ?: @"" }];
    [self runOKRequest:req fallback:@"举报失败" completion:completion];
}

- (void)addFavoriteWithToken:(NSString *)token
                 contentType:(NSString *)contentType
                     content:(NSString *)content
                     caption:(NSString *)caption
                    fileName:(NSString *)fileName
                    fileSize:(int64_t)fileSize
                    duration:(int64_t)duration
                    waveform:(NSString *)waveform
                       thumb:(NSString *)thumb
                      poster:(NSString *)poster
                      mediaW:(NSInteger)mediaW
                      mediaH:(NSInteger)mediaH
                sourceConvID:(NSString *)sourceConvID
               sourceConvSeq:(int64_t)sourceConvSeq
                  sourceFrom:(NSString *)sourceFrom
                  completion:(void (^)(NSError *))completion {
    NSMutableDictionary *body = [@{ @"content_type": contentType ?: @"text", @"content": content ?: @"",
                                    @"source_conv_id": sourceConvID ?: @"", @"source_conv_seq": @(sourceConvSeq),
                                    @"source_from": sourceFrom ?: @"" } mutableCopy];
    if (caption.length > 0) { body[@"caption"] = caption; } // 图说：连文字一起收藏（整体，2026-08-19）
    if (fileName.length > 0) { body[@"file_name"] = fileName; } // 文件收藏保真（转发/展示）
    if (fileSize > 0) { body[@"file_size"] = @(fileSize); }
    if (duration > 0) { body[@"duration"] = @(duration); } // 视频/语音时长（媒体宫格角标）
    if (waveform.length > 0) { body[@"waveform"] = waveform; } // 语音振幅指纹（收藏迷你播放器画波形）
    if (thumb.length > 0) { body[@"thumb"] = thumb; } // 磨砂占位缩略（图片/视频未下载态）
    if (poster.length > 0) { body[@"poster"] = poster; } // 视频封面首帧 URL（收端直显免解码）
    if (mediaW > 0) { body[@"media_w"] = @(mediaW); } // 媒体像素宽（收端按原比例定框，转发不丢宽高）
    if (mediaH > 0) { body[@"media_h"] = @(mediaH); }
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/favorites" method:@"POST" token:token body:body];
    [self runOKRequest:req fallback:@"收藏失败" completion:completion];
}

const NSInteger IMFavoritesPageSize = 60;

- (void)favoritesWithToken:(NSString *)token
                    offset:(NSInteger)offset
                completion:(void (^)(NSArray<NSDictionary *> *, NSInteger, NSError *))completion {
    NSString *path = [NSString stringWithFormat:@"/api/v1/favorites?limit=%ld&offset=%ld",
                      (long)IMFavoritesPageSize, (long)MAX(0, offset)];
    NSMutableURLRequest *req = [self authedRequestForPath:path method:@"GET" token:token body:nil];
    [self runDataRequest:req fallback:@"加载收藏失败" completion:^(NSDictionary *data, NSError *error) {
        if (error) { completion(nil, 0, error); return; }
        id list = data[@"favorites"];
        NSArray *items = [list isKindOfClass:[NSArray class]] ? list : @[];
        // page.total 缺失（老服务端）→ 退化成本页条数，UI 既不会显示错的总数也不会误以为还有更多。
        NSDictionary *page = [data[@"page"] isKindOfClass:[NSDictionary class]] ? data[@"page"] : nil;
        NSNumber *total = [page[@"total"] isKindOfClass:NSNumber.class] ? page[@"total"] : nil;
        completion(items, total ? total.integerValue : (NSInteger)items.count, nil);
    }];
}

- (void)deleteFavoriteWithToken:(NSString *)token
                     favoriteID:(int64_t)favoriteID
                     completion:(void (^)(NSError *))completion {
    NSString *path = [NSString stringWithFormat:@"/api/v1/favorites/%lld", favoriteID];
    NSMutableURLRequest *req = [self authedRequestForPath:path method:@"DELETE" token:token body:nil];
    [self runOKRequest:req fallback:@"删除失败" completion:completion];
}

- (void)linkPreviewWithToken:(NSString *)token url:(NSString *)url
                  completion:(void (^)(NSDictionary *, NSError *))completion {
    NSString *q = [url stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet] ?: @"";
    NSString *path = [@"/api/v1/link-preview?url=" stringByAppendingString:q];
    NSMutableURLRequest *req = [self authedRequestForPath:path method:@"GET" token:token body:nil];
    [self runDataRequest:req fallback:@"预览失败" completion:^(NSDictionary *data, NSError *error) {
        // 调用方以 nil 表示"无预览可用"（据此跳过缓存/渲染）；runDataRequest 成功恒回字典，空则还原为 nil。
        completion(data.count > 0 ? data : nil, error);
    }];
}

- (void)translateWithToken:(NSString *)token
                      text:(NSString *)text
                targetLang:(NSString *)targetLang
                completion:(void (^)(NSString *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/translate" method:@"POST" token:token
        body:@{ @"text": text ?: @"", @"target_lang": targetLang ?: @"zh" }];
    [self runDataRequest:req fallback:@"翻译失败" completion:^(NSDictionary *data, NSError *error) {
        if (error) { completion(nil, error); return; }
        id t = data[@"translation"];
        completion([t isKindOfClass:[NSString class]] ? t : @"", nil);
    }];
}

- (void)requestFriendWithToken:(NSString *)token
                        peerID:(NSString *)peerID
                         hello:(NSString *)hello
                    completion:(void (^)(BOOL, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/friends/request" method:@"POST" token:token
                                                     body:@{ @"user_id": peerID ?: @"", @"hello": hello ?: @"" }];
    [self runDataRequest:req fallback:@"操作失败" completion:^(NSDictionary *data, NSError *error) {
        if (error) { completion(NO, error); return; }
        NSString *outcome = [data[@"outcome"] isKindOfClass:[NSString class]] ? data[@"outcome"] : nil;
        completion([outcome isEqualToString:@"accepted"], nil);
    }];
}

- (void)friendActionWithToken:(NSString *)token
                       action:(NSString *)action
                       peerID:(NSString *)peerID
                   completion:(void (^)(NSError *))completion {
    NSString *path = [NSString stringWithFormat:@"/api/v1/friends/%@", action];
    NSMutableURLRequest *req = [self authedRequestForPath:path method:@"POST" token:token body:@{ @"user_id": peerID ?: @"" }];
    [self runOKRequest:req fallback:@"操作失败" completion:completion];
}

- (void)removeFriendWithToken:(NSString *)token
                       peerID:(NSString *)peerID
                   completion:(void (^)(NSError *))completion {
    NSString *seg = [peerID stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet] ?: @"";
    NSString *path = [NSString stringWithFormat:@"/api/v1/friends/%@", seg];
    NSMutableURLRequest *req = [self authedRequestForPath:path method:@"DELETE" token:token body:nil];
    [self runOKRequest:req fallback:@"删除失败" completion:completion];
}

#pragma mark - 群聊（M3）

- (void)createGroupWithToken:(NSString *)token
                        name:(NSString *)name
                   memberIDs:(NSArray<NSString *> *)memberIDs
                  completion:(void (^)(IMGroupInfo *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/groups" method:@"POST" token:token
        body:@{ @"name": name ?: @"", @"avatar_url": @"", @"member_ids": memberIDs ?: @[] }];
    [self runGroupInfoRequest:req fallback:@"建群失败" completion:completion];
}

- (void)groupsWithToken:(NSString *)token
             completion:(void (^)(NSArray<IMGroupInfo *> *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/groups" method:@"GET" token:token body:nil];
    [self runDataRequest:req fallback:@"拉取群列表失败" completion:^(NSDictionary *data, NSError *error) {
        completion(error ? nil : [IMGroupInfo groupsFromArray:data[@"groups"]], error);
    }];
}

- (void)groupInfoWithToken:(NSString *)token
                    convID:(NSString *)convID
                completion:(void (^)(IMGroupInfo *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:[self groupPathFor:convID suffix:@""]
                                                   method:@"GET" token:token body:nil];
    [self runGroupInfoRequest:req fallback:@"拉取群资料失败" completion:completion];
}

- (void)serverConfigWithToken:(NSString *)token
                   completion:(void (^)(NSInteger, BOOL, NSInteger, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/server-config" method:@"GET" token:token body:nil];
    [self runDataRequest:req fallback:@"拉取服务端配置失败" completion:^(NSDictionary *data, NSError *error) {
        if (error) { completion(0, NO, 0, error); return; }
        completion([data[@"max_group_members"] integerValue],
                   [data[@"supergroup_enabled"] boolValue],
                   [data[@"max_supergroup_members"] integerValue],
                   nil);
    }];
}

- (void)groupMembersPageWithToken:(NSString *)token
                           convID:(NSString *)convID
                           cursor:(NSString *)cursor
                            limit:(NSInteger)limit
                            query:(NSString *)query
                       completion:(void (^)(NSArray<IMGroupMember *> *, NSString *, BOOL, NSError *))completion {
    NSMutableString *suffix = [NSMutableString stringWithFormat:@"/members?limit=%ld", (long)(limit > 0 ? limit : 50)];
    if (cursor.length > 0) {
        [suffix appendFormat:@"&cursor=%@", [self pathEscape:cursor]];
    }
    if (query.length > 0) {
        [suffix appendFormat:@"&q=%@", [self pathEscape:query]];
    }
    NSMutableURLRequest *req = [self authedRequestForPath:[self groupPathFor:convID suffix:suffix]
                                                   method:@"GET" token:token body:nil];
    [self runDataRequest:req fallback:@"拉取群成员失败" completion:^(NSDictionary *data, NSError *error) {
        if (error) { completion(nil, nil, NO, error); return; }
        // ⚠️ 分页接口的成员数组在 **items** 里，不是 members——`GET /groups/{id}` 用 members，
        // 这个分页接口用 items，两者不同名。照直觉写成 members 会静默拿到空列表
        // （Web 端同一个坑当场把界面搞白屏了）。字段名以后端 handlers_group.go 为准。
        NSArray *raw = [data[@"items"] isKindOfClass:NSArray.class] ? data[@"items"] : @[];
        NSMutableArray<IMGroupMember *> *out = [NSMutableArray arrayWithCapacity:raw.count];
        for (id item in raw) {
            if (![item isKindOfClass:NSDictionary.class]) { continue; }
            IMGroupMember *m = [IMGroupMember memberFromDictionary:item];
            if (m) { [out addObject:m]; }
        }
        NSString *next = [data[@"next_cursor"] isKindOfClass:NSString.class] ? data[@"next_cursor"] : @"";
        completion(out, next, [data[@"has_more"] boolValue], nil);
    }];
}

- (void)pinnedMessagesWithToken:(NSString *)token
                         convID:(NSString *)convID
                     completion:(void (^)(NSArray<IMPinnedMessage *> *, NSError *))completion {
    NSString *path = [NSString stringWithFormat:@"/api/v1/conversations/%@/pinned", [self pathEscape:convID]];
    NSMutableURLRequest *req = [self authedRequestForPath:path method:@"GET" token:token body:nil];
    [self runDataRequest:req fallback:@"拉取置顶消息失败" completion:^(NSDictionary *data, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSArray *raw = [data[@"items"] isKindOfClass:[NSArray class]] ? data[@"items"] : @[];
        NSMutableArray<IMPinnedMessage *> *items = [NSMutableArray arrayWithCapacity:raw.count];
        for (id one in raw) {
            IMPinnedMessage *p = [IMPinnedMessage fromJSON:[one isKindOfClass:[NSDictionary class]] ? one : nil];
            if (p) { [items addObject:p]; } // 脏项跳过，不让一条坏数据废掉整条横幅
        }
        completion(items, nil);
    }];
}

- (void)readReceiptsWithToken:(NSString *)token
                       convID:(NSString *)convID
                      convSeq:(int64_t)convSeq
                   completion:(void (^)(NSArray<NSString *> *, NSArray<NSString *> *, BOOL, NSError *))completion {
    NSString *encoded = [convID stringByAddingPercentEncodingWithAllowedCharacters:
                         NSCharacterSet.URLPathAllowedCharacterSet] ?: convID;
    NSString *path = [NSString stringWithFormat:@"/api/v1/conversations/%@/messages/%lld/read-by", encoded, convSeq];
    NSMutableURLRequest *req = [self authedRequestForPath:path method:@"GET" token:token body:nil];
    if (!req) {
        [self callOnMain:^{ completion(nil, nil, NO, [self errorWithMessage:@"非法服务器地址"]); }];
        return;
    }
    [self runRequest:req completion:^(NSDictionary *body, NSError *error) {
        if (error) { completion(nil, nil, NO, error); return; }
        if ([body[@"code"] integerValue] != 0) {
            completion(nil, nil, NO, [self errorWithMessage:[self messageFrom:body fallback:@"拉取已读状态失败"]]);
            return;
        }
        NSDictionary *data = [body[@"data"] isKindOfClass:[NSDictionary class]] ? body[@"data"] : nil;
        NSArray *read = [data[@"read"] isKindOfClass:[NSArray class]] ? data[@"read"] : @[];
        NSArray *unread = [data[@"unread"] isKindOfClass:[NSArray class]] ? data[@"unread"] : @[];
        BOOL enabled = [data[@"enabled"] respondsToSelector:@selector(boolValue)] && [data[@"enabled"] boolValue];
        completion(read, unread, enabled, nil);
    }];
}

- (void)updateGroupWithToken:(NSString *)token convID:(NSString *)convID
                        name:(NSString *)name avatarURL:(NSString *)avatarURL intro:(NSString *)intro
                  completion:(void (^)(NSError *))completion {
    // 整体替换语义：name/avatar_url/intro 都要回带当前值，省略即被清空（后端 G1）。
    NSMutableURLRequest *req = [self authedRequestForPath:[self groupPathFor:convID suffix:@""]
                                                   method:@"PUT" token:token
                                                     body:@{ @"name": name ?: @"", @"avatar_url": avatarURL ?: @"", @"intro": intro ?: @"" }];
    [self runOKRequest:req fallback:@"保存群资料失败" completion:completion];
}

// 群公告发布/撤下（G1）：text 空即撤下。仅群主/管理员（越权服务端回 300204）。
- (void)setGroupAnnouncementWithToken:(NSString *)token convID:(NSString *)convID
                                 text:(NSString *)text completion:(void (^)(NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:[self groupPathFor:convID suffix:@"/announcement"]
                                                   method:@"PUT" token:token body:@{ @"text": text ?: @"" }];
    [self runOKRequest:req fallback:@"保存群公告失败" completion:completion];
}

// 群主/管理员自助全员禁言（G1）：until=0 解除 / -1 永久 / 其余到期毫秒时间戳。
- (void)setGroupMuteWithToken:(NSString *)token convID:(NSString *)convID
                        until:(int64_t)until completion:(void (^)(NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:[self groupPathFor:convID suffix:@"/mute"]
                                                   method:@"PUT" token:token body:@{ @"until": @(until) }];
    [self runOKRequest:req fallback:@"设置全员禁言失败" completion:completion];
}

// 我在本群的昵称（G1）：任意成员改自己的，空串=清除回退全局昵称。
- (void)setGroupMyNicknameWithToken:(NSString *)token convID:(NSString *)convID
                           nickname:(NSString *)nickname completion:(void (^)(NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:[self groupPathFor:convID suffix:@"/members/me/nickname"]
                                                   method:@"PUT" token:token body:@{ @"nickname": nickname ?: @"" }];
    [self runOKRequest:req fallback:@"保存群昵称失败" completion:completion];
}

// 群治理开关组（G2，群主/管理员整体替换）。
- (void)setGroupSettingsWithToken:(NSString *)token convID:(NSString *)convID
                     joinApproval:(BOOL)joinApproval permInvite:(BOOL)permInvite
                     permEditInfo:(BOOL)permEditInfo permPin:(BOOL)permPin
                   historyVisible:(BOOL)historyVisible completion:(void (^)(NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:[self groupPathFor:convID suffix:@"/settings"]
                                                   method:@"PUT" token:token body:@{
        @"join_approval": @(joinApproval), @"perm_invite": @(permInvite),
        @"perm_edit_info": @(permEditInfo), @"perm_pin": @(permPin), @"history_visible": @(historyVisible),
    }];
    [self runOKRequest:req fallback:@"保存群设置失败" completion:completion];
}

// 单独禁言成员（G2）：until=0 解禁 / -1 永久 / 其余到期毫秒。
- (void)muteGroupMemberWithToken:(NSString *)token convID:(NSString *)convID userID:(NSString *)userID
                           until:(int64_t)until completion:(void (^)(NSError *))completion {
    NSString *suffix = [NSString stringWithFormat:@"/members/%@/mute", [self pathEscape:userID]];
    NSMutableURLRequest *req = [self authedRequestForPath:[self groupPathFor:convID suffix:suffix]
                                                   method:@"PUT" token:token body:@{ @"until": @(until) }];
    [self runOKRequest:req fallback:@"禁言失败" completion:completion];
}

// 移出成员带封禁档（G2）：ban=none|cooldown|forever（缺省 cooldown）。
- (void)removeGroupMemberWithToken:(NSString *)token convID:(NSString *)convID userID:(NSString *)userID
                               ban:(NSString *)ban completion:(void (^)(NSError *))completion {
    NSString *suffix = [NSString stringWithFormat:@"/members/%@?ban=%@", [self pathEscape:userID], ban ?: @"cooldown"];
    NSMutableURLRequest *req = [self authedRequestForPath:[self groupPathFor:convID suffix:suffix]
                                                   method:@"DELETE" token:token body:nil];
    [self runOKRequest:req fallback:@"移除失败" completion:completion];
}

// 群黑名单列表（G2，群主/管理员）→ 回 [{user_id,banned_by,banned_at,expires_at}]。
- (void)groupBansWithToken:(NSString *)token convID:(NSString *)convID
                completion:(void (^)(NSArray<NSDictionary *> *bans, NSError *error))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:[self groupPathFor:convID suffix:@"/bans"]
                                                   method:@"GET" token:token body:nil];
    [self runDataRequest:req fallback:@"拉取黑名单失败" completion:^(NSDictionary *data, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSArray *bans = [data[@"bans"] isKindOfClass:[NSArray class]] ? data[@"bans"] : @[];
        completion(bans, nil);
    }];
}

// 解除拉黑（G2，群主/管理员）。
- (void)unbanGroupMemberWithToken:(NSString *)token convID:(NSString *)convID userID:(NSString *)userID
                       completion:(void (^)(NSError *))completion {
    NSString *suffix = [NSString stringWithFormat:@"/bans/%@", [self pathEscape:userID]];
    NSMutableURLRequest *req = [self authedRequestForPath:[self groupPathFor:convID suffix:suffix]
                                                   method:@"DELETE" token:token body:nil];
    [self runOKRequest:req fallback:@"解除失败" completion:completion];
}

- (void)inviteToGroupWithToken:(NSString *)token convID:(NSString *)convID
                     memberIDs:(NSArray<NSString *> *)memberIDs
                    completion:(void (^)(NSArray<NSString *> *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:[self groupPathFor:convID suffix:@"/members"]
                                                   method:@"POST" token:token
                                                     body:@{ @"member_ids": memberIDs ?: @[] }];
    // 用 runDataRequest（保留业务码）而非 runOKRequest：邀请可能返 300207（被邀请者已被移出/冷却期），
    // UI 需按码给"邀请别人"场景的第三人称文案；data 里的 added 是实际加入者（见 .h）。
    [self runDataRequest:req fallback:@"邀请失败" completion:^(NSDictionary *data, NSError *error) {
        if (error) { completion(@[], error); return; }
        NSArray *raw = [data[@"added"] isKindOfClass:NSArray.class] ? data[@"added"] : @[];
        NSMutableArray<NSString *> *added = [NSMutableArray arrayWithCapacity:raw.count];
        for (id item in raw) { if ([item isKindOfClass:NSString.class]) { [added addObject:item]; } }
        completion(added, nil);
    }];
}

- (void)leaveGroupWithToken:(NSString *)token convID:(NSString *)convID
                 completion:(void (^)(NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:[self groupPathFor:convID suffix:@"/members/me"]
                                                   method:@"DELETE" token:token body:nil];
    [self runOKRequest:req fallback:@"退群失败" completion:completion];
}

- (void)removeGroupMemberWithToken:(NSString *)token convID:(NSString *)convID userID:(NSString *)userID
                        completion:(void (^)(NSError *))completion {
    NSString *suffix = [NSString stringWithFormat:@"/members/%@", [self pathEscape:userID]];
    NSMutableURLRequest *req = [self authedRequestForPath:[self groupPathFor:convID suffix:suffix]
                                                   method:@"DELETE" token:token body:nil];
    [self runOKRequest:req fallback:@"移除失败" completion:completion];
}

- (void)setGroupRoleWithToken:(NSString *)token convID:(NSString *)convID userID:(NSString *)userID
                         role:(NSString *)role completion:(void (^)(NSError *))completion {
    NSString *suffix = [NSString stringWithFormat:@"/members/%@/role", [self pathEscape:userID]];
    NSMutableURLRequest *req = [self authedRequestForPath:[self groupPathFor:convID suffix:suffix]
                                                   method:@"PUT" token:token body:@{ @"role": role ?: @"" }];
    [self runOKRequest:req fallback:@"设置角色失败" completion:completion];
}

- (void)transferGroupWithToken:(NSString *)token convID:(NSString *)convID userID:(NSString *)userID
                    completion:(void (^)(NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:[self groupPathFor:convID suffix:@"/transfer"]
                                                   method:@"POST" token:token body:@{ @"user_id": userID ?: @"" }];
    [self runOKRequest:req fallback:@"转让失败" completion:completion];
}

- (void)dissolveGroupWithToken:(NSString *)token convID:(NSString *)convID
                    completion:(void (^)(NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:[self groupPathFor:convID suffix:@""]
                                                   method:@"DELETE" token:token body:nil];
    [self runOKRequest:req fallback:@"解散失败" completion:completion];
}

#pragma mark - 会话管理（M4.5）

- (void)conversationSettingsWithToken:(NSString *)token convID:(NSString *)convID
                           completion:(void (^)(NSDictionary *_Nullable, NSError *_Nullable))completion {
    NSString *path = [NSString stringWithFormat:@"/api/v1/conversations/%@/settings", [self pathEscape:convID]];
    NSMutableURLRequest *req = [self authedRequestForPath:path method:@"GET" token:token body:nil];
    [self runDataRequest:req fallback:@"拉取会话设置失败" completion:completion];
}

- (void)setFriendRemarkWithToken:(NSString *)token peerID:(NSString *)peerID remark:(NSString *)remark
                      completion:(void (^)(NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/friends/remark" method:@"POST" token:token
        body:@{ @"user_id": peerID ?: @"", @"remark": remark ?: @"" }];
    [self runOKRequest:req fallback:@"保存备注失败" completion:completion];
}

- (void)setConversationRemarkWithToken:(NSString *)token convID:(NSString *)convID remark:(NSString *)remark
                            completion:(void (^)(NSError *))completion {
    NSString *path = [NSString stringWithFormat:@"/api/v1/conversations/%@/remark", [self pathEscape:convID]];
    NSMutableURLRequest *req = [self authedRequestForPath:path method:@"PUT" token:token
        body:@{ @"remark": remark ?: @"" }];
    [self runOKRequest:req fallback:@"保存备注失败" completion:completion];
}

- (void)updateConversationSettingsWithToken:(NSString *)token convID:(NSString *)convID
                                   pinnedAt:(int64_t)pinnedAt muted:(BOOL)muted markedUnread:(BOOL)markedUnread
                                 completion:(void (^)(NSError *))completion {
    NSString *path = [NSString stringWithFormat:@"/api/v1/conversations/%@/settings", [self pathEscape:convID]];
    NSMutableURLRequest *req = [self authedRequestForPath:path method:@"PUT" token:token
        body:@{ @"pinned_at": @(pinnedAt), @"muted": @(muted), @"marked_unread": @(markedUnread) }];
    [self runOKRequest:req fallback:@"设置失败" completion:completion];
}

- (void)deleteConversationWithToken:(NSString *)token convID:(NSString *)convID
                         completion:(void (^)(NSError *))completion {
    NSString *path = [NSString stringWithFormat:@"/api/v1/conversations/%@", [self pathEscape:convID]];
    NSMutableURLRequest *req = [self authedRequestForPath:path method:@"DELETE" token:token body:nil];
    [self runOKRequest:req fallback:@"删除会话失败" completion:completion];
}

/// 群接口路径：/api/v1/groups/{convID}{suffix}（convID 经 path 转义）。
- (NSString *)groupPathFor:(NSString *)convID suffix:(NSString *)suffix {
    return [NSString stringWithFormat:@"/api/v1/groups/%@%@", [self pathEscape:convID], suffix];
}

- (NSString *)pathEscape:(NSString *)seg {
    return [seg stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet] ?: @"";
}

/// 执行"返回群资料"的请求（建群/群详情共用）。
- (void)runGroupInfoRequest:(nullable NSMutableURLRequest *)req
                   fallback:(NSString *)fallback
                 completion:(void (^)(IMGroupInfo *, NSError *))completion {
    if (!req) {
        [self callOnMain:^{ completion(nil, [self errorWithMessage:@"非法服务器地址"]); }];
        return;
    }
    [self runRequest:req completion:^(NSDictionary *body, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSInteger code = [body[@"code"] integerValue];
        if (code != 0) {
            // 保留业务码（同 runDataRequest）——300210 等审批分支得以直接复用本 helper。
            completion(nil, [self errorWithCode:code message:[self messageFrom:body fallback:fallback]]);
            return;
        }
        NSDictionary *data = [body[@"data"] isKindOfClass:[NSDictionary class]] ? body[@"data"] : nil;
        completion([IMGroupInfo groupFromDictionary:data], nil);
    }];
}

/// 执行"只关心成功/失败"的请求（群成员管理各动作共用）。
- (void)runOKRequest:(nullable NSMutableURLRequest *)req
            fallback:(NSString *)fallback
          completion:(void (^)(NSError *))completion {
    if (!req) {
        [self callOnMain:^{ completion([self errorWithMessage:@"非法服务器地址"]); }];
        return;
    }
    [self runRequest:req completion:^(NSDictionary *body, NSError *error) {
        if (error) { completion(error); return; }
        NSInteger code = [body[@"code"] integerValue];
        if (code != 0) {
            // 保留业务码（同 runDataRequest）：调用方即使今天只 toast，明天要按码分支也不用改这里。
            // 曾因这里丢码（-1）逼得 joinGroup 手写整套信封（见 git 记录），helper 丢码是手抄复发的根因。
            completion([self errorWithCode:code message:[self messageFrom:body fallback:fallback]]);
            return;
        }
        completion(nil);
    }];
}

/// 取 data 字典且**保留业务码**（errorWithCode，非 errorWithMessage）——QR/入群要按 200110/300210 分支。
- (void)runDataRequest:(nullable NSMutableURLRequest *)req
              fallback:(NSString *)fallback
            completion:(void (^)(NSDictionary *_Nullable data, NSError *_Nullable error))completion {
    if (!req) {
        [self callOnMain:^{ completion(nil, [self errorWithMessage:@"非法服务器地址"]); }];
        return;
    }
    [self runRequest:req completion:^(NSDictionary *body, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSInteger code = [body[@"code"] integerValue];
        if (code != 0) {
            completion(nil, [self errorWithCode:code message:[self messageFrom:body fallback:fallback]]);
            return;
        }
        NSDictionary *data = [body[@"data"] isKindOfClass:[NSDictionary class]] ? body[@"data"] : @{};
        completion(data, nil);
    }];
}

#pragma mark - 二维码体系（QRCODE P0）+ 入群（G3）

- (void)qrMyCardWithToken:(NSString *)token
               completion:(void (^)(NSDictionary *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/qr/me" method:@"GET" token:token body:nil];
    [self runDataRequest:req fallback:@"获取名片码失败" completion:completion];
}

- (void)qrResetMyCardWithToken:(NSString *)token
                    completion:(void (^)(NSDictionary *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/qr/me/reset" method:@"POST" token:token body:@{}];
    [self runDataRequest:req fallback:@"重置名片码失败" completion:completion];
}

- (void)groupQRWithToken:(NSString *)token convID:(NSString *)convID
              completion:(void (^)(NSDictionary *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:[self groupPathFor:convID suffix:@"/qr"]
                                                   method:@"GET" token:token body:nil];
    [self runDataRequest:req fallback:@"获取群二维码失败" completion:completion];
}

- (void)groupQRResetWithToken:(NSString *)token convID:(NSString *)convID
                   completion:(void (^)(NSDictionary *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:[self groupPathFor:convID suffix:@"/qr/reset"]
                                                   method:@"POST" token:token body:@{}];
    [self runDataRequest:req fallback:@"重置群二维码失败" completion:completion];
}

- (void)qrResolveWithToken:(NSString *)token raw:(NSString *)raw
                completion:(void (^)(NSDictionary *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/qr/resolve" method:@"POST" token:token
                                                     body:@{ @"raw": raw ?: @"" }];
    [self runDataRequest:req fallback:@"识别失败" completion:completion];
}

- (void)joinGroupWithToken:(NSString *)token code:(NSString *)code hello:(NSString *)hello
                completion:(void (^)(IMGroupInfo *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/groups/join" method:@"POST" token:token
                                                     body:@{ @"token": code ?: @"", @"hello": hello ?: @"" }];
    // runGroupInfoRequest 已保留业务码：300210（需审批已提交）等分支照常按 error.code 走。
    [self runGroupInfoRequest:req fallback:@"加入群聊失败" completion:completion];
}

- (void)joinRequestsWithToken:(NSString *)token convID:(NSString *)convID
                   completion:(void (^)(NSArray<NSDictionary *> *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:[self groupPathFor:convID suffix:@"/join-requests?status=pending"]
                                                   method:@"GET" token:token body:nil];
    [self runDataRequest:req fallback:@"加载入群申请失败" completion:^(NSDictionary *data, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSArray *reqs = [data[@"requests"] isKindOfClass:[NSArray class]] ? data[@"requests"] : @[];
        completion(reqs, nil);
    }];
}

- (void)decideJoinRequestWithToken:(NSString *)token convID:(NSString *)convID
                            userID:(NSString *)userID accept:(BOOL)accept
                        completion:(void (^)(NSError *))completion {
    NSString *suffix = [NSString stringWithFormat:@"/join-requests/%@", [self pathEscape:userID]];
    NSMutableURLRequest *req = [self authedRequestForPath:[self groupPathFor:convID suffix:suffix]
                                                   method:@"POST" token:token
                                                     body:@{ @"action": accept ? @"approve" : @"reject" }];
    [self runOKRequest:req fallback:@"审批失败" completion:completion];
}

#pragma mark - 扫码登录（QR P1，手机确认端）

- (void)qrLoginScanWithToken:(NSString *)token ticket:(NSString *)ticket
                  completion:(void (^)(NSDictionary *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/qr/login/scan" method:@"POST" token:token
                                                     body:@{ @"ticket": ticket ?: @"" }];
    // 保留业务码：码失效回 200110，确认页据此弹"二维码已失效"而非通用错误。
    [self runDataRequest:req fallback:@"识别登录码失败" completion:completion];
}

- (void)qrLoginConfirmWithToken:(NSString *)token ticket:(NSString *)ticket
                     completion:(void (^)(NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/qr/login/confirm" method:@"POST" token:token
                                                     body:@{ @"ticket": ticket ?: @"" }];
    // 只关心成功/失败；失效码 200110 的友好文案由 messageFrom 统一映射。
    [self runOKRequest:req fallback:@"确认登录失败" completion:completion];
}

- (void)qrLoginRejectWithToken:(NSString *)token ticket:(NSString *)ticket
                    completion:(void (^)(NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/qr/login/reject" method:@"POST" token:token
                                                     body:@{ @"ticket": ticket ?: @"" }];
    [self runOKRequest:req fallback:@"拒绝登录失败" completion:completion];
}

#pragma mark - 已登录设备（多设备管理，QR P2）

- (void)devicesWithToken:(NSString *)token
              completion:(void (^)(NSArray<IMDeviceSession *> *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/devices" method:@"GET" token:token body:nil];
    [self runDataRequest:req fallback:@"获取设备列表失败" completion:^(NSDictionary *data, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSArray *arr = [data[@"devices"] isKindOfClass:NSArray.class] ? data[@"devices"] : @[];
        completion([IMDeviceSession fromArray:arr], nil);
    }];
}

- (void)revokeDeviceWithToken:(NSString *)token sessionID:(NSString *)sessionID
                   completion:(void (^)(NSError *))completion {
    NSString *path = [NSString stringWithFormat:@"/api/v1/devices/%@/revoke", [self pathEscape:sessionID]];
    NSMutableURLRequest *req = [self authedRequestForPath:path method:@"POST" token:token body:@{}];
    [self runOKRequest:req fallback:@"退出设备失败" completion:completion];
}

- (void)logoutWithToken:(NSString *)token completion:(void (^)(NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/logout" method:@"POST" token:token body:@{}];
    [self runOKRequest:req fallback:@"退出登录失败" completion:completion];
}

- (void)revokeOtherDevicesWithToken:(NSString *)token
                         completion:(void (^)(NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/devices/revoke-others" method:@"POST" token:token body:@{}];
    [self runOKRequest:req fallback:@"退出其他设备失败" completion:completion];
}

#pragma mark - 我的资料

/// 单张用户名片请求的公共尾（me / users/:id / 更新资料三处共用）：组合 runDataRequest，
/// 只负责 data→IMUserCard 的映射——不再手抄信封体，业务码语义与全站 helper 一致。
- (void)runUserCardRequest:(nullable NSMutableURLRequest *)req
                  fallback:(NSString *)fallback
                completion:(void (^)(IMUserCard *, NSError *))completion {
    [self runDataRequest:req fallback:fallback completion:^(NSDictionary *data, NSError *error) {
        completion(error || data.count == 0 ? nil : [IMUserCard cardsFromArray:@[data]].firstObject, error);
    }];
}

- (void)myProfileWithToken:(NSString *)token
                completion:(void (^)(IMUserCard *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/users/me" method:@"GET" token:token body:nil];
    [self runUserCardRequest:req fallback:@"拉取资料失败" completion:completion];
}

- (void)userProfileWithToken:(NSString *)token
                      userID:(NSString *)userID
                  completion:(void (^)(IMUserCard *, NSError *))completion {
    NSString *encoded = [userID stringByAddingPercentEncodingWithAllowedCharacters:
                         NSCharacterSet.URLPathAllowedCharacterSet] ?: @"";
    NSString *path = [NSString stringWithFormat:@"/api/v1/users/%@", encoded];
    NSMutableURLRequest *req = [self authedRequestForPath:path method:@"GET" token:token body:nil];
    [self runUserCardRequest:req fallback:@"拉取资料失败" completion:completion];
}

- (void)updateProfileWithToken:(NSString *)token
                      nickname:(NSString *)nickname
                     avatarURL:(NSString *)avatarURL
                         phone:(NSString *)phone
                          tags:(NSArray<NSString *> *)tags
                    completion:(void (^)(IMUserCard *, NSError *))completion {
    NSDictionary *bodyDict = @{ @"nickname": nickname ?: @"", @"avatar_url": avatarURL ?: @"",
                                @"phone": phone ?: @"", @"tags": tags ?: @[] };
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/users/me" method:@"PUT" token:token body:bodyDict];
    [self runUserCardRequest:req fallback:@"保存资料失败" completion:completion];
}

- (void)changePasswordWithToken:(NSString *)token
                    oldPassword:(NSString *)oldPassword
                    newPassword:(NSString *)newPassword
                     completion:(void (^)(NSError *))completion {
    NSDictionary *body = @{ @"old_password": oldPassword ?: @"", @"new_password": newPassword ?: @"" };
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/users/me/password" method:@"POST" token:token body:body];
    __weak typeof(self) weakSelf = self;
    // 改密成功时后端会**轮换本机的长效续期凭据**并在 data.refresh_token 里回一枚新的
    // （见后端 handleChangePassword）。必须就地换掉本地那枚：旧的已在服务端作废，
    // 不换的话下次冷启动续期被拒 → 用户刚改完密码就被登出。
    // 用 runDataRequest 而不是 runOKRequest：后者丢掉 data（也保业务码，见 CODING_STYLE §5）。
    [self runDataRequest:req fallback:@"修改密码失败" completion:^(NSDictionary *data, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        NSString *fresh = [data[@"refresh_token"] isKindOfClass:NSString.class] ? data[@"refresh_token"] : nil;
        if (self && !error && fresh.length > 0) {
            self.refreshToken = fresh;
            [IMSessionStore saveRefreshToken:fresh];
        }
        if (completion) { completion(error); }
    }];
}

- (void)sentFilesWithToken:(NSString *)token
                     cursor:(NSString *)cursor
                 completion:(void (^)(NSArray<NSDictionary *> *, NSString *, BOOL, NSError *))completion {
    NSString *path = @"/api/v1/files/sent?limit=50";
    if (cursor.length > 0) {
        NSString *encoded = [cursor stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
        path = [path stringByAppendingFormat:@"&cursor=%@", encoded ?: @""];
    }
    NSMutableURLRequest *req = [self authedRequestForPath:path method:@"GET" token:token body:nil];
    if (!req) {
        [self callOnMain:^{ completion(nil, nil, NO, [self errorWithMessage:@"非法服务器地址"]); }];
        return;
    }
    [self runRequest:req completion:^(NSDictionary *body, NSError *error) {
        if (error) { completion(nil, nil, NO, error); return; }
        if ([body[@"code"] integerValue] != 0) {
            completion(nil, nil, NO, [self errorWithMessage:[self messageFrom:body fallback:@"拉取文件失败"]]);
            return;
        }
        NSDictionary *data = [body[@"data"] isKindOfClass:NSDictionary.class] ? body[@"data"] : @{};
        NSArray *files = [data[@"files"] isKindOfClass:NSArray.class] ? data[@"files"] : @[];
        NSString *next = [data[@"next_cursor"] isKindOfClass:NSString.class] ? data[@"next_cursor"] : nil;
        completion(files, next, [data[@"has_more"] boolValue], nil);
    }];
}

- (void)hideMessageWithToken:(NSString *)token
                      convID:(NSString *)convID
                     convSeq:(int64_t)convSeq
                  completion:(void (^)(NSError *))completion {
    NSDictionary *bodyDict = @{ @"conv_id": convID ?: @"", @"conv_seq": @(convSeq) };
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/messages/hide" method:@"POST" token:token body:bodyDict];
    [self runOKRequest:req fallback:@"删除失败" completion:completion];
}

- (void)transcribeVoiceWithToken:(NSString *)token
                          convID:(NSString *)convID
                         convSeq:(int64_t)convSeq
                      completion:(void (^)(NSString *, NSString *, NSError *))completion {
    NSDictionary *bodyDict = @{ @"conv_id": convID ?: @"", @"conv_seq": @(convSeq) };
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/voice/transcripts" method:@"POST" token:token body:bodyDict];
    // 走 runDataRequest 而非 runOKRequest：需要按业务码分支（未启用/队列满/限流文案各不同），
    // runOKRequest 会把 code 丢掉只留文案。
    [self runDataRequest:req fallback:@"转文字失败" completion:^(NSDictionary *data, NSError *error) {
        if (error) { completion(nil, nil, error); return; }
        NSString *status = [data[@"status"] isKindOfClass:NSString.class] ? data[@"status"] : @"";
        NSString *text = [data[@"text"] isKindOfClass:NSString.class] ? data[@"text"] : nil;
        completion(status, text, nil);
    }];
}

- (void)fetchHiddenWithToken:(NSString *)token
                  completion:(void (^)(NSArray<NSDictionary *> *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/messages/hidden" method:@"GET" token:token body:nil];
    [self runDataRequest:req fallback:@"拉取隐藏列表失败" completion:^(NSDictionary *data, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSArray *items = [data[@"items"] isKindOfClass:NSArray.class] ? data[@"items"] : @[];
        completion(items, nil);
    }];
}

#pragma mark - 内部

/// 构造带 Bearer 的请求；body 非空时按 JSON 写入并设 Content-Type。
- (nullable NSMutableURLRequest *)authedRequestForPath:(NSString *)path
                                                method:(NSString *)method
                                                 token:(NSString *)token
                                                  body:(nullable NSDictionary *)body {
    NSURL *url = [self urlForPath:path];
    if (!url) { return nil; }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = method;
    [req setValue:[NSString stringWithFormat:@"Bearer %@", token ?: @""] forHTTPHeaderField:@"Authorization"];
    if (body) {
        [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
    }
    req.timeoutInterval = 10;
    return req;
}

- (void)uploadData:(NSData *)data
          fileName:(NSString *)fileName
          mimeType:(NSString *)mimeType
             token:(NSString *)token
        completion:(void (^)(NSString *, NSString *, NSError *))completion {
    [self uploadData:data fileName:fileName mimeType:mimeType token:token progress:nil completion:completion];
}

- (void)uploadData:(NSData *)data
          fileName:(NSString *)fileName
          mimeType:(NSString *)mimeType
             token:(NSString *)token
          progress:(void (^)(double))progress
        completion:(void (^)(NSString *, NSString *, NSError *))completion {
    [self uploadData:data fileName:fileName mimeType:mimeType token:token path:@"/api/v1/upload" progress:progress completion:completion];
}

/// voice P0：/api/v1/upload?as=voice——切用 voice 白名单 + 16MB 上限（服务端 handlers_upload.go 分派）。
/// mimeType 传 audio/mp4（AAC-LC 单声道 16kHz），fileName 需带 .m4a 才能过白名单。
- (void)uploadVoiceData:(NSData *)data
               fileName:(NSString *)fileName
               mimeType:(NSString *)mimeType
                  token:(NSString *)token
               progress:(nullable void (^)(double))progress
             completion:(void (^)(NSString *_Nullable url, NSError *_Nullable error))completion {
    [self uploadData:data fileName:fileName mimeType:mimeType token:token path:@"/api/v1/upload?as=voice" progress:progress completion:^(NSString *u, NSString *ct, NSError *e) {
        completion(u, e);
    }];
}

- (void)uploadData:(NSData *)data
          fileName:(NSString *)fileName
          mimeType:(NSString *)mimeType
             token:(NSString *)token
              path:(NSString *)path
          progress:(void (^)(double))progress
        completion:(void (^)(NSString *, NSString *, NSError *))completion {
    NSURL *url = [self urlForPath:path];
    if (!url || data.length == 0) { [self callOnMain:^{ completion(nil, nil, [self errorWithMessage:@"无效的上传"]); }]; return; }
    // multipart 信封落磁盘再流式上传：原先把 74MB 视频再拷进 NSMutableData，峰值内存翻倍且拼装本身就慢。
    NSString *boundary = [@"----IMBoundary" stringByAppendingString:NSUUID.UUID.UUIDString];
    NSURL *bodyFile = [self writeMultipartBodyToTempFileWithData:data fileName:fileName mimeType:mimeType boundary:boundary];
    if (!bodyFile) { [self callOnMain:^{ completion(nil, nil, [self errorWithMessage:@"上传准备失败（磁盘空间不足？）"]); }]; return; }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = 60; // 空闲超时；整单上限由 uploadSession 的 timeoutIntervalForResource 控制
    [req setValue:[NSString stringWithFormat:@"Bearer %@", token ?: @""] forHTTPHeaderField:@"Authorization"];
    [req setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];

    __weak typeof(self) ws = self;
    void (^cleanup)(void) = ^{ [NSFileManager.defaultManager removeItemAtURL:bodyFile error:NULL]; };
    [self runUploadRequest:req bodyFile:bodyFile attempt:0 progress:progress completion:^(NSDictionary *resp, NSError *error) {
        __strong typeof(ws) self = ws;
        cleanup();
        if (!self) { return; }
        if (error) { completion(nil, nil, error); return; }
        if ([resp[@"code"] integerValue] != 0) { completion(nil, nil, [self errorWithMessage:[self messageFrom:resp fallback:@"上传失败"]]); return; }
        NSDictionary *d = [resp[@"data"] isKindOfClass:[NSDictionary class]] ? resp[@"data"] : @{};
        NSString *u = [d[@"url"] isKindOfClass:[NSString class]] ? d[@"url"] : nil;
        NSString *ct = [d[@"content_type"] isKindOfClass:[NSString class]] ? d[@"content_type"] : @"image";
        completion(u, ct, u ? nil : [self errorWithMessage:@"上传响应异常"]);
    }];
}

- (void)uploadAvatarData:(NSData *)data
                   token:(NSString *)token
              completion:(void (^)(NSString *, NSError *))completion {
    NSURL *url = [self urlForPath:@"/api/v1/avatar"];
    if (!url || data.length == 0) { [self callOnMain:^{ completion(nil, [self errorWithMessage:@"无效的上传"]); }]; return; }
    NSString *boundary = [@"----IMBoundary" stringByAppendingString:NSUUID.UUID.UUIDString];
    NSURL *bodyFile = [self writeMultipartBodyToTempFileWithData:data fileName:@"avatar.jpg" mimeType:@"image/jpeg" boundary:boundary];
    if (!bodyFile) { [self callOnMain:^{ completion(nil, [self errorWithMessage:@"上传准备失败（磁盘空间不足？）"]); }]; return; }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = 60;
    [req setValue:[NSString stringWithFormat:@"Bearer %@", token ?: @""] forHTTPHeaderField:@"Authorization"];
    [req setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];

    __weak typeof(self) ws = self;
    void (^cleanup)(void) = ^{ [NSFileManager.defaultManager removeItemAtURL:bodyFile error:NULL]; };
    [self runUploadRequest:req bodyFile:bodyFile attempt:0 progress:nil completion:^(NSDictionary *resp, NSError *error) {
        __strong typeof(ws) self = ws;
        cleanup();
        if (!self) { return; }
        if (error) { completion(nil, error); return; }
        if ([resp[@"code"] integerValue] != 0) { completion(nil, [self errorWithMessage:[self messageFrom:resp fallback:@"上传失败"]]); return; }
        NSDictionary *d = [resp[@"data"] isKindOfClass:[NSDictionary class]] ? resp[@"data"] : @{};
        NSString *u = [d[@"url"] isKindOfClass:[NSString class]] ? d[@"url"] : nil;
        completion(u, u ? nil : [self errorWithMessage:@"上传响应异常"]);
    }];
}

- (NSURLSessionTask *)performUploadAPI:(NSString *)path
                                method:(NSString *)method
                                  body:(NSData *)body
                                 token:(NSString *)token
                            completion:(void (^)(NSDictionary *_Nullable, NSError *_Nullable))completion {
    NSURL *url = [self urlForPath:path];
    if (!url) { completion(nil, [self errorWithMessage:@"非法服务器地址"]); return nil; }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = method ?: @"POST";
    req.timeoutInterval = 60;
    [req setValue:[NSString stringWithFormat:@"Bearer %@", token ?: @""] forHTTPHeaderField:@"Authorization"];
    if (body) {
        // 分片是原始字节（application/octet-stream），不是 multipart —— 服务端直接 io.Copy 落盘。
        BOOL isJSON = [path hasSuffix:@"/init"];
        [req setValue:(isJSON ? @"application/json" : @"application/octet-stream") forHTTPHeaderField:@"Content-Type"];
        req.HTTPBody = body;
    }
    __weak typeof(self) ws = self;
    return [self runTaskForRequest:req completion:^(NSDictionary *resp, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) { completion(nil, error); return; }
        if ([resp[@"code"] integerValue] != 0) {
            // 透传业务码（>0）：调用方据此区分「服务端明确拒绝」（如上传会话过期 → 该换会话重来）
            // 与「网络失败」（code=-1 → 保留 offset 稍后重试）。
            NSInteger code = [resp[@"code"] integerValue];
            completion(nil, [self errorWithCode:(code != 0 ? code : -1)
                                        message:[self messageFrom:resp fallback:@"上传失败"]]);
            return;
        }
        NSDictionary *d = [resp[@"data"] isKindOfClass:NSDictionary.class] ? resp[@"data"] : @{};
        completion(d, nil);
    }];
}

+ (BOOL)isBusinessError:(NSError *)error {
    return [error.domain isEqualToString:kIMHTTPErrorDomain] && error.code > 0;
}

/// 把 multipart 信封（头 + 文件字节 + 尾）写到临时文件，供 uploadTaskWithRequest:fromFile: 流式读取。
/// 返回 nil = 写盘失败。
- (nullable NSURL *)writeMultipartBodyToTempFileWithData:(NSData *)data
                                                fileName:(NSString *)fileName
                                                mimeType:(NSString *)mimeType
                                                boundary:(NSString *)boundary {
    NSURL *dst = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                                         [@"im-upload-" stringByAppendingString:NSUUID.UUID.UUIDString]]];
    NSString *head = [NSString stringWithFormat:
        @"--%@\r\nContent-Disposition: form-data; name=\"file\"; filename=\"%@\"\r\nContent-Type: %@\r\n\r\n",
        boundary, fileName ?: @"file", mimeType ?: @"application/octet-stream"];
    NSString *tail = [NSString stringWithFormat:@"\r\n--%@--\r\n", boundary];
    if (![NSFileManager.defaultManager createFileAtPath:dst.path contents:nil attributes:nil]) { return nil; }
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingToURL:dst error:NULL];
    if (!fh) { return nil; }
    NSError *werr = nil;
    BOOL ok = [fh writeData:[head dataUsingEncoding:NSUTF8StringEncoding] error:&werr]
           && [fh writeData:data error:&werr]
           && [fh writeData:[tail dataUsingEncoding:NSUTF8StringEncoding] error:&werr];
    [fh closeAndReturnError:NULL];
    if (!ok) {
        IMLogErrorWithTag(IMLogTagHTTP, @"upload_body_write_failed error=%@", werr.localizedDescription ?: @"-");
        [NSFileManager.defaultManager removeItemAtURL:dst error:NULL];
        return nil;
    }
    return dst;
}

/// 传输层瞬时错误（超时/连接中断/网络切换）自动重试；业务错误（4xx/5xx 的 JSON 信封）不重试。
/// 大文件上传一次失败就是几十秒白干，用户只会看到"发送失败"，必须自愈。
- (void)runUploadRequest:(NSURLRequest *)req
                bodyFile:(NSURL *)bodyFile
                 attempt:(NSInteger)attempt
                progress:(void (^)(double))progress
              completion:(void (^)(NSDictionary *body, NSError *error))completion {
    __weak typeof(self) ws = self;
    [self runRequest:req bodyFile:bodyFile progress:progress completion:^(NSDictionary *body, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (!error || attempt >= kIMUploadMaxRetries || !IMIsTransientNetworkError(error)) {
            completion(body, error);
            return;
        }
        NSTimeInterval delay = 1.5 * (double)(attempt + 1); // 1.5s / 3s，够短不至于让用户干等
        IMLogWarnWithTag(IMLogTagHTTP, @"upload_retry attempt=%ld delay_s=%.1f reason=%@",
                         (long)(attempt + 1), delay, error.localizedDescription ?: @"-");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (progress) { progress(0); } // 重试从头传，进度回零，别让 UI 卡在半截
            [self runUploadRequest:req bodyFile:bodyFile attempt:attempt + 1 progress:progress completion:completion];
        });
    }];
}

- (nullable NSURL *)urlForPath:(NSString *)path {
    return [IMServerEndpoint.shared httpURLForHost:self.host path:path];
}

- (nullable NSMutableURLRequest *)postRequestToPath:(NSString *)path body:(NSDictionary *)body {
    NSURL *url = [self urlForPath:path];
    if (!url) { return nil; }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
    req.timeoutInterval = 10;
    return req;
}

/// 执行请求并把统一响应解析成字典，主线程回调。
- (void)runRequest:(NSURLRequest *)req completion:(void (^)(NSDictionary *body, NSError *error))completion {
    [self runRequest:req progress:nil completion:completion];
}

- (NSURLSessionTask *)runTaskForRequest:(NSURLRequest *)req
                             completion:(void (^)(NSDictionary *body, NSError *error))completion {
    return [self runRequest:req bodyFile:nil progress:nil completion:completion];
}

/// 上传专用会话：大文件上行必须与普通 API 用不同的超时口径。
/// `timeoutIntervalForRequest` 是**空闲**超时（两次数据回调之间），`timeoutIntervalForResource` 才是整单上限。
/// 之前所有请求共用 30s，74MB 视频传到 46s 被 -1001 掐断（见 2026-08-03 真机日志）。
- (NSURLSession *)uploadSession {
    static NSURLSession *session;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 60;      // 60s 没有任何字节进出才算卡死
        cfg.timeoutIntervalForResource = 60 * 60; // 整单上限 1h，弱网大文件也不会被硬掐
        session = [NSURLSession sessionWithConfiguration:cfg];
    });
    return session;
}

/// runRequest 的带上行进度变体：progress 非空时挂 per-task delegate 取 didSendBodyData（上传专用）。
- (void)runRequest:(NSURLRequest *)req
          progress:(void (^)(double fraction))progress
        completion:(void (^)(NSDictionary *body, NSError *error))completion {
    [self runRequest:req bodyFile:nil progress:progress completion:completion];
}

/// bodyFile 非空 → 走 uploadTaskWithRequest:fromFile:（请求体从磁盘流式读，不进内存）。
/// 返回底层 task：分片上传的暂停/换链需要**真正 abort 在飞请求**（不 abort 的话 8MB 请求体会
/// 继续上传到完为止——快速连点暂停/恢复曾累积 30 个并发 PUT 挤爆带宽，见 2026-08-03 真机日志）。
- (NSURLSessionTask *)runRequest:(NSURLRequest *)req
          bodyFile:(NSURL *)bodyFile
          progress:(void (^)(double fraction))progress
        completion:(void (^)(NSDictionary *body, NSError *error))completion {
    NSMutableURLRequest *request = [req mutableCopy];
    NSString *requestID = [request valueForHTTPHeaderField:kIMRequestIDHeader];
    if (requestID.length == 0) {
        requestID = IMHTTPNewRequestID();
        [request setValue:requestID forHTTPHeaderField:kIMRequestIDHeader];
    }
    NSString *method = request.HTTPMethod ?: @"GET";
    NSString *path = request.URL.path.length > 0 ? request.URL.path : @"/";
    NSString *contentType = [request valueForHTTPHeaderField:@"Content-Type"];
    unsigned long long bodyBytes = request.HTTPBody.length;
    if (bodyFile) {
        bodyBytes = [[NSFileManager.defaultManager attributesOfItemAtPath:bodyFile.path error:NULL][NSFileSize] unsignedLongLongValue];
    }
    NSString *requestBody = bodyFile ? [NSString stringWithFormat:@"<multipart file %llu bytes>", bodyBytes]
                                     : IMHTTPLogBody(request.HTTPBody, contentType, IMHTTPLogIncludesBusinessContent());
    CFAbsoluteTime startedAt = CFAbsoluteTimeGetCurrent();
    IMLogHTTP(@"[req=%@][REQUEST] %@ %@ bytes=%llu body=%@", requestID, method, path, bodyBytes, requestBody);

    __weak typeof(self) weakSelf = self;
    void (^handler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        NSHTTPURLResponse *httpResponse = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        NSString *serverRequestID = [httpResponse valueForHTTPHeaderField:kIMRequestIDHeader];
        NSString *correlationID = serverRequestID.length > 0 ? serverRequestID : requestID;
        NSTimeInterval durationMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000;
        if (error) {
            IMLogErrorWithTag(IMLogTagHTTP,
                              @"[req=%@][ERROR] %@ %@ duration_ms=%.1f domain=%@ code=%ld message=%@",
                              correlationID, method, path, durationMs,
                              error.domain, (long)error.code, error.localizedDescription ?: @"-");
            // 传输层失败（连不上/超时）：转友好中文，不把英文 NSError 原文弹给用户；
            // 原始 NSError 挂在 NSUnderlyingErrorKey，上传重试据此判断是否值得重试。
            NSError *friendly = [NSError errorWithDomain:kIMHTTPErrorDomain code:-1
                userInfo:@{ NSLocalizedDescriptionKey: IMFriendlyNetworkError(error), NSUnderlyingErrorKey: error }];
            [self callOnMain:^{ completion(nil, friendly); }];
            return;
        }
        NSInteger status = httpResponse.statusCode;
        NSString *responseType = [httpResponse valueForHTTPHeaderField:@"Content-Type"];
        // 高频轮询接口（会话列表 /conversations、隐藏消息 /messages/hidden）成功响应只记条数摘要，
        // 不记整份 body——它们约每 16s 一轮、内容高度重复，是 dev 汇聚日志膨胀的主因（占 ~90% 体积），
        // 摘要保留状态/条数/耗时足够排查。非 200（错误响应）仍记完整 body 便于定位。子路径
        //（/conversations/{id}/pinned 等）不以此后缀结尾，照常完整记录。
        BOOL pollSummary = status == 200 &&
            ([path hasSuffix:@"/conversations"] || [path hasSuffix:@"/messages/hidden"]);
        NSString *responseBody = pollSummary
            ? IMHTTPPollResponseSummary(data)
            : IMHTTPLogBody(data, responseType, IMHTTPLogIncludesBusinessContent());
        IMLogHTTP(@"[req=%@][RESPONSE] status=%ld duration_ms=%.1f bytes=%lu body=%@",
                  correlationID, (long)status, durationMs, (unsigned long)data.length, responseBody);

        id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        NSDictionary *body = [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
        if (!body) {
            // 非 JSON / 空响应（后端没起或打到错地址）：友好提示 + 附 HTTP 码便于排查。
            NSString *msg = status == 0 ? @"服务器无响应，请确认后端已启动"
                : [NSString stringWithFormat:@"服务器响应异常 (HTTP %ld)", (long)status];
            [self callOnMain:^{ completion(nil, [self errorWithMessage:msg]); }];
            return;
        }
        [self callOnMain:^{ completion(body, nil); }];
    };
    // 上传（有请求体文件或需要进度）走上传会话，其余走共享会话保持原行为。
    NSURLSessionTask *task = bodyFile
        ? [[self uploadSession] uploadTaskWithRequest:request fromFile:bodyFile completionHandler:handler]
        : (progress ? [[self uploadSession] dataTaskWithRequest:request completionHandler:handler]
                    : [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:handler]);
    if (progress) {
        IMUploadProgressBridge *bridge = [IMUploadProgressBridge new];
        bridge.onProgress = progress;
        if (@available(iOS 15.0, *)) { task.delegate = bridge; } // task 强持有 delegate，completionHandler 任务仍会收 didSendBodyData
    }
    [task resume];
    return task;
}

- (void)callOnMain:(void (^)(void))block {
    dispatch_async(dispatch_get_main_queue(), block);
}

- (NSString *)messageFrom:(NSDictionary *)body fallback:(NSString *)fallback {
    // 优先按业务码映射友好中文；未收录再用服务端原文 / fallback。
    NSInteger code = [body[@"code"] respondsToSelector:@selector(integerValue)] ? [body[@"code"] integerValue] : 0;
    NSString *friendly = IMFriendlyMessageForCode(code);
    if (friendly) { return friendly; }
    NSString *msg = [body[@"message"] isKindOfClass:[NSString class]] ? body[@"message"] : nil;
    return msg.length > 0 ? msg : fallback;
}

- (NSError *)errorWithMessage:(NSString *)message {
    return [self errorWithCode:-1 message:message]; // -1 = 网络/未知（非业务码）
}

- (NSError *)errorWithCode:(NSInteger)code message:(NSString *)message {
    return [NSError errorWithDomain:kIMHTTPErrorDomain code:code
                           userInfo:@{ NSLocalizedDescriptionKey: message ?: @"unknown" }];
}

@end
