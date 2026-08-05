//  IMHTTPService.m

#import "IMHTTPService.h"
#import "IMConversation.h"
#import "IMUserCard.h"
#import "IMGroupInfo.h"
#import "IMHTTPLogFormatter.h"
#import "IMLog.h"

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
static NSString *IMFriendlyMessageForCode(NSInteger code) {
    switch (code) {
        case 100101: case 100102: return @"登录已失效，请重新登录"; // invalid / expired token
        case 200001: return @"用户不存在";                          // user not found
        case 200002: return @"密码错误";                            // wrong password
        case 200003: return @"账号已被封禁";                        // account banned
        case 200004: return @"用户名已被注册";                      // user already exists
        case 200101: return @"你们已经是好友了";                    // already friends
        case 200102: return @"暂时无法添加对方为好友";              // blocked by peer（不暴露拉黑）
        case 200103: return @"对方不是你的好友";                    // not friend
        case 200104: return @"不能添加自己为好友";                  // cannot add yourself
        case 200105: return @"申请已发出，等待对方同意";            // request pending
        case 200106: return @"没有待处理的好友申请";                // no pending request
        case 300201: return @"群不存在";                            // group not found
        case 300202: return @"群名不能为空且不超过 30 字";          // invalid group name
        case 300203: return @"你不在该群中";                        // not a group member
        // 300204 不映射：服务端会带具体原因（如"群主需先转让群主再退群"），透传更有用。
        case 300205: return @"群成员已达上限";                      // group member limit
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

@interface IMHTTPService ()
@property (atomic, copy, nullable) NSString *currentToken; // 对外只读，内部可写
@property (atomic, copy, nullable) NSString *tokenUserID;      // 缓存 token 归属的 uid（切账号即失效）
@property (atomic, assign) CFAbsoluteTime tokenFetchedAt;      // 取得时刻：TTL 内直接复用，不重复 POST /login
@end

@implementation IMHTTPService

+ (instancetype)sharedService {
    static IMHTTPService *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [IMHTTPService new]; });
    return instance;
}

- (void)loginWithUserID:(NSString *)userID
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
    NSDictionary *reqBody = @{ @"username": userID ?: @"", @"password": self.password ?: @"" };
    NSURLRequest *req = [self postRequestToPath:@"/api/v1/login" body:reqBody];
    if (!req) {
        [self callOnMain:^{ completion(nil, [self errorWithMessage:@"非法服务器地址"]); }];
        return;
    }
    [self runRequest:req completion:^(NSDictionary *body, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSDictionary *data = [body[@"data"] isKindOfClass:[NSDictionary class]] ? body[@"data"] : nil;
        NSString *token = [data[@"token"] isKindOfClass:[NSString class]] ? data[@"token"] : nil;
        if ([body[@"code"] integerValue] != 0 || token.length == 0) {
            // 带上业务码，便于调用方区分"鉴权失败(退登录)"与"网络问题(重试)"。
            completion(nil, [self errorWithCode:[body[@"code"] integerValue]
                                        message:[self messageFrom:body fallback:@"登录失败"]]);
            return;
        }
        self.currentToken = token; // 缓存：供聊天页等无需重登即可发 HTTP（举报）
        self.tokenUserID = userID;
        self.tokenFetchedAt = CFAbsoluteTimeGetCurrent();
        completion(token, nil);
    }];
}

- (void)registerWithUsername:(NSString *)username
                    password:(NSString *)password
                  completion:(void (^)(NSError *))completion {
    NSURLRequest *req = [self postRequestToPath:@"/api/v1/register"
                                           body:@{ @"username": username ?: @"", @"password": password ?: @"" }];
    if (!req) {
        [self callOnMain:^{ completion([self errorWithMessage:@"非法服务器地址"]); }];
        return;
    }
    [self runRequest:req completion:^(NSDictionary *body, NSError *error) {
        if (error) { completion(error); return; }
        if ([body[@"code"] integerValue] != 0) {
            completion([self errorWithMessage:[self messageFrom:body fallback:@"注册失败"]]);
            return;
        }
        completion(nil);
    }];
}

- (void)conversationsWithToken:(NSString *)token
                    completion:(void (^)(NSArray<IMConversation *> *, NSError *))completion {
    NSURL *url = [self urlForPath:@"/api/v1/conversations"];
    if (!url) {
        [self callOnMain:^{ completion(nil, [self errorWithMessage:@"非法服务器地址"]); }];
        return;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", token ?: @""] forHTTPHeaderField:@"Authorization"];
    req.timeoutInterval = 10;
    [self runRequest:req completion:^(NSDictionary *body, NSError *error) {
        if (error) { completion(nil, error); return; }
        if ([body[@"code"] integerValue] != 0) {
            completion(nil, [self errorWithMessage:[self messageFrom:body fallback:@"拉取会话失败"]]);
            return;
        }
        NSDictionary *data = [body[@"data"] isKindOfClass:[NSDictionary class]] ? body[@"data"] : nil;
        completion([IMConversation conversationsFromArray:data[@"conversations"]], nil);
    }];
}

#pragma mark - 通讯录（找人 / 好友关系）

- (void)searchUsersWithToken:(NSString *)token
                       query:(NSString *)query
                  completion:(void (^)(NSArray<IMUserCard *> *, NSError *))completion {
    NSString *q = [query stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet] ?: @"";
    NSString *path = [NSString stringWithFormat:@"/api/v1/users/search?q=%@&limit=20", q];
    NSMutableURLRequest *req = [self authedRequestForPath:path method:@"GET" token:token body:nil];
    if (!req) {
        [self callOnMain:^{ completion(nil, [self errorWithMessage:@"非法服务器地址"]); }];
        return;
    }
    [self runRequest:req completion:^(NSDictionary *body, NSError *error) {
        if (error) { completion(nil, error); return; }
        if ([body[@"code"] integerValue] != 0) {
            completion(nil, [self errorWithMessage:[self messageFrom:body fallback:@"搜索失败"]]);
            return;
        }
        NSDictionary *data = [body[@"data"] isKindOfClass:[NSDictionary class]] ? body[@"data"] : nil;
        completion([IMUserCard cardsFromArray:data[@"users"]], nil);
    }];
}

- (void)friendsWithToken:(NSString *)token
                  status:(NSString *)status
              completion:(void (^)(NSArray<IMUserCard *> *, NSError *))completion {
    NSString *path = @"/api/v1/friends";
    if (status.length > 0) {
        path = [path stringByAppendingFormat:@"?status=%@", status];
    }
    NSMutableURLRequest *req = [self authedRequestForPath:path method:@"GET" token:token body:nil];
    if (!req) {
        [self callOnMain:^{ completion(nil, [self errorWithMessage:@"非法服务器地址"]); }];
        return;
    }
    [self runRequest:req completion:^(NSDictionary *body, NSError *error) {
        if (error) { completion(nil, error); return; }
        if ([body[@"code"] integerValue] != 0) {
            completion(nil, [self errorWithMessage:[self messageFrom:body fallback:@"拉取好友失败"]]);
            return;
        }
        NSDictionary *data = [body[@"data"] isKindOfClass:[NSDictionary class]] ? body[@"data"] : nil;
        completion([IMUserCard cardsFromArray:data[@"friends"]], nil);
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
    if (!req) {
        [self callOnMain:^{ completion([self errorWithMessage:@"非法服务器地址"]); }];
        return;
    }
    [self runRequest:req completion:^(NSDictionary *body, NSError *error) {
        if (error) { completion(error); return; }
        if ([body[@"code"] integerValue] != 0) {
            completion([self errorWithMessage:[self messageFrom:body fallback:@"举报失败"]]);
            return;
        }
        completion(nil);
    }];
}

- (void)addFavoriteWithToken:(NSString *)token
                 contentType:(NSString *)contentType
                     content:(NSString *)content
                sourceConvID:(NSString *)sourceConvID
               sourceConvSeq:(int64_t)sourceConvSeq
                  sourceFrom:(NSString *)sourceFrom
                  completion:(void (^)(NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/favorites" method:@"POST" token:token
        body:@{ @"content_type": contentType ?: @"text", @"content": content ?: @"",
                @"source_conv_id": sourceConvID ?: @"", @"source_conv_seq": @(sourceConvSeq),
                @"source_from": sourceFrom ?: @"" }];
    if (!req) { [self callOnMain:^{ completion([self errorWithMessage:@"非法服务器地址"]); }]; return; }
    [self runRequest:req completion:^(NSDictionary *body, NSError *error) {
        if (error) { completion(error); return; }
        if ([body[@"code"] integerValue] != 0) { completion([self errorWithMessage:[self messageFrom:body fallback:@"收藏失败"]]); return; }
        completion(nil);
    }];
}

- (void)favoritesWithToken:(NSString *)token
                completion:(void (^)(NSArray<NSDictionary *> *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/favorites" method:@"GET" token:token body:nil];
    if (!req) { [self callOnMain:^{ completion(nil, [self errorWithMessage:@"非法服务器地址"]); }]; return; }
    [self runRequest:req completion:^(NSDictionary *body, NSError *error) {
        if (error) { completion(nil, error); return; }
        if ([body[@"code"] integerValue] != 0) { completion(nil, [self errorWithMessage:[self messageFrom:body fallback:@"加载收藏失败"]]); return; }
        id list = body[@"data"][@"favorites"];
        completion([list isKindOfClass:[NSArray class]] ? list : @[], nil);
    }];
}

- (void)deleteFavoriteWithToken:(NSString *)token
                     favoriteID:(int64_t)favoriteID
                     completion:(void (^)(NSError *))completion {
    NSString *path = [NSString stringWithFormat:@"/api/v1/favorites/%lld", favoriteID];
    NSMutableURLRequest *req = [self authedRequestForPath:path method:@"DELETE" token:token body:nil];
    if (!req) { [self callOnMain:^{ completion([self errorWithMessage:@"非法服务器地址"]); }]; return; }
    [self runRequest:req completion:^(NSDictionary *body, NSError *error) {
        if (error) { completion(error); return; }
        if ([body[@"code"] integerValue] != 0) { completion([self errorWithMessage:[self messageFrom:body fallback:@"删除失败"]]); return; }
        completion(nil);
    }];
}

- (void)linkPreviewWithToken:(NSString *)token url:(NSString *)url
                  completion:(void (^)(NSDictionary *, NSError *))completion {
    NSString *q = [url stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet] ?: @"";
    NSString *path = [@"/api/v1/link-preview?url=" stringByAppendingString:q];
    NSMutableURLRequest *req = [self authedRequestForPath:path method:@"GET" token:token body:nil];
    if (!req) { [self callOnMain:^{ completion(nil, [self errorWithMessage:@"非法服务器地址"]); }]; return; }
    [self runRequest:req completion:^(NSDictionary *body, NSError *error) {
        if (error) { completion(nil, error); return; }
        if ([body[@"code"] integerValue] != 0) { completion(nil, [self errorWithMessage:[self messageFrom:body fallback:@"预览失败"]]); return; }
        id data = body[@"data"];
        completion([data isKindOfClass:[NSDictionary class]] ? data : nil, nil);
    }];
}

- (void)translateWithToken:(NSString *)token
                      text:(NSString *)text
                targetLang:(NSString *)targetLang
                completion:(void (^)(NSString *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/translate" method:@"POST" token:token
        body:@{ @"text": text ?: @"", @"target_lang": targetLang ?: @"zh" }];
    if (!req) { [self callOnMain:^{ completion(nil, [self errorWithMessage:@"非法服务器地址"]); }]; return; }
    [self runRequest:req completion:^(NSDictionary *body, NSError *error) {
        if (error) { completion(nil, error); return; }
        if ([body[@"code"] integerValue] != 0) { completion(nil, [self errorWithMessage:[self messageFrom:body fallback:@"翻译失败"]]); return; }
        id t = body[@"data"][@"translation"];
        completion([t isKindOfClass:[NSString class]] ? t : @"", nil);
    }];
}

- (void)requestFriendWithToken:(NSString *)token
                        peerID:(NSString *)peerID
                    completion:(void (^)(BOOL, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/friends/request" method:@"POST" token:token
                                                     body:@{ @"user_id": peerID ?: @"" }];
    if (!req) {
        [self callOnMain:^{ completion(NO, [self errorWithMessage:@"非法服务器地址"]); }];
        return;
    }
    [self runRequest:req completion:^(NSDictionary *body, NSError *error) {
        if (error) { completion(NO, error); return; }
        if ([body[@"code"] integerValue] != 0) {
            completion(NO, [self errorWithMessage:[self messageFrom:body fallback:@"操作失败"]]);
            return;
        }
        NSDictionary *data = [body[@"data"] isKindOfClass:[NSDictionary class]] ? body[@"data"] : nil;
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
    if (!req) {
        [self callOnMain:^{ completion([self errorWithMessage:@"非法服务器地址"]); }];
        return;
    }
    [self runRequest:req completion:^(NSDictionary *body, NSError *error) {
        if (error) { completion(error); return; }
        if ([body[@"code"] integerValue] != 0) {
            completion([self errorWithMessage:[self messageFrom:body fallback:@"操作失败"]]);
            return;
        }
        completion(nil);
    }];
}

- (void)removeFriendWithToken:(NSString *)token
                       peerID:(NSString *)peerID
                   completion:(void (^)(NSError *))completion {
    NSString *seg = [peerID stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet] ?: @"";
    NSString *path = [NSString stringWithFormat:@"/api/v1/friends/%@", seg];
    NSMutableURLRequest *req = [self authedRequestForPath:path method:@"DELETE" token:token body:nil];
    if (!req) {
        [self callOnMain:^{ completion([self errorWithMessage:@"非法服务器地址"]); }];
        return;
    }
    [self runRequest:req completion:^(NSDictionary *body, NSError *error) {
        if (error) { completion(error); return; }
        if ([body[@"code"] integerValue] != 0) {
            completion([self errorWithMessage:[self messageFrom:body fallback:@"删除失败"]]);
            return;
        }
        completion(nil);
    }];
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
    if (!req) {
        [self callOnMain:^{ completion(nil, [self errorWithMessage:@"非法服务器地址"]); }];
        return;
    }
    [self runRequest:req completion:^(NSDictionary *body, NSError *error) {
        if (error) { completion(nil, error); return; }
        if ([body[@"code"] integerValue] != 0) {
            completion(nil, [self errorWithMessage:[self messageFrom:body fallback:@"拉取群列表失败"]]);
            return;
        }
        NSDictionary *data = [body[@"data"] isKindOfClass:[NSDictionary class]] ? body[@"data"] : nil;
        completion([IMGroupInfo groupsFromArray:data[@"groups"]], nil);
    }];
}

- (void)groupInfoWithToken:(NSString *)token
                    convID:(NSString *)convID
                completion:(void (^)(IMGroupInfo *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:[self groupPathFor:convID suffix:@""]
                                                   method:@"GET" token:token body:nil];
    [self runGroupInfoRequest:req fallback:@"拉取群资料失败" completion:completion];
}

- (void)updateGroupWithToken:(NSString *)token convID:(NSString *)convID
                        name:(NSString *)name avatarURL:(NSString *)avatarURL
                  completion:(void (^)(NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:[self groupPathFor:convID suffix:@""]
                                                   method:@"PUT" token:token
                                                     body:@{ @"name": name ?: @"", @"avatar_url": avatarURL ?: @"" }];
    [self runOKRequest:req fallback:@"保存群资料失败" completion:completion];
}

- (void)inviteToGroupWithToken:(NSString *)token convID:(NSString *)convID
                     memberIDs:(NSArray<NSString *> *)memberIDs
                    completion:(void (^)(NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:[self groupPathFor:convID suffix:@"/members"]
                                                   method:@"POST" token:token
                                                     body:@{ @"member_ids": memberIDs ?: @[] }];
    [self runOKRequest:req fallback:@"邀请失败" completion:completion];
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
        if ([body[@"code"] integerValue] != 0) {
            completion(nil, [self errorWithMessage:[self messageFrom:body fallback:fallback]]);
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
        if ([body[@"code"] integerValue] != 0) {
            completion([self errorWithMessage:[self messageFrom:body fallback:fallback]]);
            return;
        }
        completion(nil);
    }];
}

#pragma mark - 我的资料

- (void)myProfileWithToken:(NSString *)token
                completion:(void (^)(IMUserCard *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/users/me" method:@"GET" token:token body:nil];
    if (!req) {
        [self callOnMain:^{ completion(nil, [self errorWithMessage:@"非法服务器地址"]); }];
        return;
    }
    [self runRequest:req completion:^(NSDictionary *body, NSError *error) {
        if (error) { completion(nil, error); return; }
        if ([body[@"code"] integerValue] != 0) {
            completion(nil, [self errorWithMessage:[self messageFrom:body fallback:@"拉取资料失败"]]);
            return;
        }
        NSDictionary *data = [body[@"data"] isKindOfClass:[NSDictionary class]] ? body[@"data"] : nil;
        completion(data ? [IMUserCard cardsFromArray:@[data]].firstObject : nil, nil);
    }];
}

- (void)userProfileWithToken:(NSString *)token
                      userID:(NSString *)userID
                  completion:(void (^)(IMUserCard *, NSError *))completion {
    NSString *encoded = [userID stringByAddingPercentEncodingWithAllowedCharacters:
                         NSCharacterSet.URLPathAllowedCharacterSet] ?: @"";
    NSString *path = [NSString stringWithFormat:@"/api/v1/users/%@", encoded];
    NSMutableURLRequest *req = [self authedRequestForPath:path method:@"GET" token:token body:nil];
    if (!req) {
        [self callOnMain:^{ completion(nil, [self errorWithMessage:@"非法服务器地址"]); }];
        return;
    }
    [self runRequest:req completion:^(NSDictionary *body, NSError *error) {
        if (error) { completion(nil, error); return; }
        if ([body[@"code"] integerValue] != 0) {
            completion(nil, [self errorWithMessage:[self messageFrom:body fallback:@"拉取资料失败"]]);
            return;
        }
        NSDictionary *data = [body[@"data"] isKindOfClass:[NSDictionary class]] ? body[@"data"] : nil;
        completion(data ? [IMUserCard cardsFromArray:@[data]].firstObject : nil, nil);
    }];
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
    if (!req) {
        [self callOnMain:^{ completion(nil, [self errorWithMessage:@"非法服务器地址"]); }];
        return;
    }
    [self runRequest:req completion:^(NSDictionary *body, NSError *error) {
        if (error) { completion(nil, error); return; }
        if ([body[@"code"] integerValue] != 0) {
            completion(nil, [self errorWithMessage:[self messageFrom:body fallback:@"保存资料失败"]]);
            return;
        }
        NSDictionary *data = [body[@"data"] isKindOfClass:[NSDictionary class]] ? body[@"data"] : nil;
        completion(data ? [IMUserCard cardsFromArray:@[data]].firstObject : nil, nil);
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
    NSURL *url = [self urlForPath:@"/api/v1/upload"];
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
    if (self.host.length == 0) { return nil; }
    return [NSURL URLWithString:[NSString stringWithFormat:@"http://%@%@", self.host, path]];
}

- (nullable NSURLRequest *)postRequestToPath:(NSString *)path body:(NSDictionary *)body {
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
        NSString *responseBody = IMHTTPLogBody(data, responseType, IMHTTPLogIncludesBusinessContent());
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
