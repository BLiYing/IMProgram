//  IMHTTPService.m

#import "IMHTTPService.h"
#import "IMConversation.h"
#import "IMUserCard.h"
#import "IMGroupInfo.h"
#import "IMLog.h"

static NSString * const kIMHTTPErrorDomain = @"IMHTTPService";

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

@interface IMHTTPService ()
@property (atomic, copy, nullable) NSString *currentToken; // 对外只读，内部可写
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
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:req
                                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (error) {
            // 传输层失败（连不上/超时）：转友好中文，不把英文 NSError 原文弹给用户。
            [self callOnMain:^{ completion(nil, [self errorWithMessage:IMFriendlyNetworkError(error)]); }];
            return;
        }
        id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        NSDictionary *body = [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
        if (!body) {
            // 非 JSON / 空响应（后端没起或打到错地址）：友好提示 + 附 HTTP 码便于排查。
            NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)response).statusCode : 0;
            NSString *msg = status == 0 ? @"服务器无响应，请确认后端已启动"
                : [NSString stringWithFormat:@"服务器响应异常 (HTTP %ld)", (long)status];
            [self callOnMain:^{ completion(nil, [self errorWithMessage:msg]); }];
            return;
        }
        [self callOnMain:^{ completion(body, nil); }];
    }];
    [task resume];
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
