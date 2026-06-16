//  IMHTTPService.m

#import "IMHTTPService.h"
#import "IMConversation.h"
#import "IMUserCard.h"
#import "IMLog.h"

static NSString * const kIMHTTPErrorDomain = @"IMHTTPService";

@implementation IMHTTPService

+ (instancetype)sharedService {
    static IMHTTPService *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [IMHTTPService new]; });
    return instance;
}

- (void)loginWithUserID:(NSString *)userID
             completion:(void (^)(NSString *, NSError *))completion {
    NSURLRequest *req = [self postRequestToPath:@"/api/v1/login" body:@{ @"uid": userID ?: @"" }];
    if (!req) {
        [self callOnMain:^{ completion(nil, [self errorWithMessage:@"非法服务器地址"]); }];
        return;
    }
    [self runRequest:req completion:^(NSDictionary *body, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSDictionary *data = [body[@"data"] isKindOfClass:[NSDictionary class]] ? body[@"data"] : nil;
        NSString *token = [data[@"token"] isKindOfClass:[NSString class]] ? data[@"token"] : nil;
        if ([body[@"code"] integerValue] != 0 || token.length == 0) {
            completion(nil, [self errorWithMessage:[self messageFrom:body fallback:@"登录失败"]]);
            return;
        }
        completion(token, nil);
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
            [self callOnMain:^{ completion(nil, error); }];
            return;
        }
        id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        NSDictionary *body = [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
        if (!body) {
            // 非 JSON 响应（如旧后端 404 纯文本）：带上 HTTP 状态码与正文片段，便于排查。
            NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)response).statusCode : 0;
            NSString *snippet = data.length > 0 ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
            if (snippet.length > 120) { snippet = [snippet substringToIndex:120]; }
            NSString *msg = [NSString stringWithFormat:@"响应解析失败 (HTTP %ld) %@", (long)status, snippet ?: @""];
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
    NSString *msg = [body[@"message"] isKindOfClass:[NSString class]] ? body[@"message"] : nil;
    return msg.length > 0 ? msg : fallback;
}

- (NSError *)errorWithMessage:(NSString *)message {
    return [NSError errorWithDomain:kIMHTTPErrorDomain code:-1
                           userInfo:@{ NSLocalizedDescriptionKey: message ?: @"unknown" }];
}

@end
