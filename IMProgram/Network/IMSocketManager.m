//  IMSocketManager.m

#import "IMSocketManager.h"
#import "IMProtocol.h"
#import "IMConversation.h"
#import "IMMessageModel.h"
#import "IMDatabase.h"
#import "IMHTTPService.h"
#import "IMLog.h"

#pragma mark - 调参常量

static const NSTimeInterval kIMPingInterval   = 25.0; ///< 心跳周期（协议要求 25s）
static const NSTimeInterval kIMAckTimeout     = 5.0;  ///< ack 超时即重发
static const NSInteger      kIMMaxResend      = 3;    ///< ack 超时最大重发次数
static const NSTimeInterval kIMReconnectBase  = 1.0;  ///< 重连退避基数
static const NSTimeInterval kIMReconnectCap   = 30.0; ///< 重连退避上限

static NSString * const kIMErrorDomain = @"IMSocketManagerErrorDomain";

NSString * const IMSocketDidReceiveMessageNotification = @"IMSocketDidReceiveMessageNotification";
NSString * const IMSocketDidReceiveFriendEventNotification = @"IMSocketDidReceiveFriendEventNotification";
NSString * const IMSocketDidReceiveGroupEventNotification = @"IMSocketDidReceiveGroupEventNotification";
NSString * const kIMGroupEventKey = @"groupEvent";
NSString * const kIMGroupTargetKey = @"groupTarget";
NSString * const IMSocketDidReceiveReadNotification = @"IMSocketDidReceiveReadNotification";
NSString * const IMSocketDidChangeStateNotification = @"IMSocketDidChangeStateNotification";
NSString * const kIMConvIDKey = @"convID";
NSString * const IMSocketDidReceivePresenceNotification = @"IMSocketDidReceivePresenceNotification";
NSString * const kIMPresenceUserKey = @"presenceUser";
NSString * const kIMPresenceKey = @"presence";
NSString * const IMSocketDidApplyMsgOpNotification = @"IMSocketDidApplyMsgOpNotification";
NSString * const kIMMsgOpTargetSeqKey = @"msgOpTargetSeq";
NSString * const kIMMsgOpKey = @"msgOp";
NSString * const kIMMsgOpContentKey = @"msgOpContent";
NSString * const IMSocketDidRejectMsgOpNotification = @"IMSocketDidRejectMsgOpNotification";
NSString * const IMSocketDidUpdateConversationNotification = @"IMSocketDidUpdateConversationNotification";

#pragma mark - 待确认发送项

/// 一条已发出、等待 ack 的消息及其超时重发上下文。
@interface IMPendingSend : NSObject
@property (nonatomic, copy)   NSString *clientMsgID;
@property (nonatomic, strong) NSData   *payload;       ///< 已序列化的信封，重发时原样再发
@property (nonatomic, copy, nullable) IMSendCompletion completion;
@property (nonatomic, assign) NSInteger retries;
@property (nonatomic, strong, nullable) dispatch_source_t ackTimer;
@end

@implementation IMPendingSend
@end

#pragma mark - IMSocketManager

@interface IMSocketManager () <NSURLSessionWebSocketDelegate>
@property (nonatomic, assign) IMSocketState state;
@property (nonatomic, copy, nullable)   NSString *userID;
- (void)cancelAllPendingSendsWithMessage:(NSString *)message;
- (BOOL)applyMsgOpPayload:(NSDictionary *)payload advancingSyncedConvSeq:(int64_t)syncedConvSeq;
- (BOOL)performDatabaseOperation:(void (^)(IMDatabase *database))operation;
@end

@implementation IMSocketManager {
    dispatch_queue_t _queue;          ///< 串行队列：所有内部状态仅在此队列变更
    NSURLSession *_session;
    NSURLSessionWebSocketTask *_task;
    NSString *_host;
    int64_t   _seq;                   ///< 客户端单调自增请求号
    BOOL      _manualClose;           ///< 用户主动断开，禁止自动重连
    NSInteger _reconnectAttempts;
    NSUInteger _connectionGeneration;  ///< 使旧登录请求/socket 回调在切账号或新重连后失效
    IMDatabaseAccountContext *_databaseContext; ///< 与当前连接账号及激活代次绑定，拒绝 A→B→A 的迟到落库
    dispatch_source_t _pingTimer;
    NSMutableDictionary<NSString *, IMPendingSend *> *_pending;
    NSMutableDictionary<NSString *, NSNumber *> *_syncedSeq; // conv_id -> 已连续同步完成的 conv_seq（非“见过的最大值”）
    NSMutableSet<NSString *> *_trackedConvs;                 // 需在重连后增量同步的会话
    NSMutableSet<NSString *> *_syncingConvs;                 // 已发出 sync_req、等待该会话响应，避免实时连发造成请求风暴
    NSMutableDictionary<NSString *, NSNumber *> *_syncStalledUntil; // conv_id -> 该时刻(CFAbsoluteTime)前不再发 sync_req：
                                                             // 整页处理完位点没动（落库持续失败/页内空洞）时热重试只会烧 CPU
    NSMutableSet<NSString *> *_pendingOps;                   // 已发出、待确认的消息操作 client_msg_id（撤回/编辑/置顶），供失败回滚
}

+ (instancetype)sharedManager {
    static IMSocketManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [IMSocketManager new]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.improgram.socket", DISPATCH_QUEUE_SERIAL);
        _pending = [NSMutableDictionary dictionary];
        _syncedSeq = [NSMutableDictionary dictionary];
        _trackedConvs = [NSMutableSet set];
        _syncingConvs = [NSMutableSet set];
        _syncStalledUntil = [NSMutableDictionary dictionary];
        _pendingOps = [NSMutableSet set];
        _state = IMSocketStateDisconnected;
    }
    return self;
}

#pragma mark - 连接生命周期

- (void)connectToHost:(NSString *)host userID:(NSString *)userID {
    if (host.length == 0 || userID.length == 0) {
        IMLogSocket(@"connect 参数为空，忽略");
        return;
    }
    dispatch_async(_queue, ^{
        IMDatabaseAccountContext *databaseContext = IMDatabase.sharedDatabase.currentAccountContext;
        if (![databaseContext.ownerUserID isEqualToString:userID]) {
            IMLogSocket(@"忽略与当前数据库账号不一致的连接请求 socket_uid=%@ db_uid=%@",
                        userID, databaseContext.ownerUserID ?: @"(none)");
            return;
        }
        BOOL activationChanged = self->_databaseContext && self->_databaseContext != databaseContext;
        BOOL accountChanged = activationChanged
            || (self.userID.length > 0 && ![self.userID isEqualToString:userID]);
        if (accountChanged) {
            // 同一单例会跨登录复用；同步游标若不按账号清空，会把上个账号在同一 conv_id 的位置带过来，
            // 新账号便会从过大的 since 开始，永久漏掉历史。
            [self->_syncedSeq removeAllObjects];
            [self->_trackedConvs removeAllObjects];
            [self->_syncingConvs removeAllObjects];
            [self->_pendingOps removeAllObjects];
            [self cancelAllPendingSendsWithMessage:@"账号已切换"];
        }
        self->_databaseContext = databaseContext;
        // 幂等：已连到同一 host+uid 且未主动断开 → 复用现连接（避免会话列表/聊天页重复调用造成重连抖动）。
        if (self.state != IMSocketStateDisconnected && !self->_manualClose
            && !activationChanged
            && [self->_host isEqualToString:host] && [self.userID isEqualToString:userID]) {
            return;
        }
        self->_host = [host copy];
        self.userID = userID;
        self->_manualClose = NO;
        self->_reconnectAttempts = 0;
        [self openSocket];
    });
}

/// Socket 的所有落库都必须携带连接建立时捕获的账号上下文。
/// 账号在主线程先切换后，旧 socket 队列中尚未处理的帧会在这里被数据库层再次拒绝。
- (BOOL)performDatabaseOperation:(void (^)(IMDatabase *database))operation {
    IMDatabaseAccountContext *context = _databaseContext;
    BOOL performed = [IMDatabase.sharedDatabase performWithAccountContext:context block:operation];
    if (!performed) {
        IMLogSocket(@"丢弃失效连接代次的数据库操作 socket_uid=%@ db_context_uid=%@",
                    self.userID ?: @"", context.ownerUserID ?: @"");
    }
    return performed;
}

- (void)disconnect {
    dispatch_async(_queue, ^{
        self->_manualClose = YES;
        [self teardownSocket];
        [self->_syncedSeq removeAllObjects];
        [self->_trackedConvs removeAllObjects];
        [self->_syncingConvs removeAllObjects];
        [self->_pendingOps removeAllObjects];
        [self cancelAllPendingSendsWithMessage:@"连接已关闭"];
        [self updateState:IMSocketStateDisconnected];
    });
}

/// 建立一条新连接（仅在 _queue 调用）：先经 HTTP 登录换取 JWT，再用 ?token= 连 ws。
- (void)openSocket {
    [self teardownSocket];
    NSUInteger generation = ++_connectionGeneration;
    [self updateState:IMSocketStateConnecting];
    NSString *host = _host;
    NSString *uid = self.userID;
    __weak typeof(self) weakSelf = self;
    [self fetchTokenForHost:host userID:uid completion:^(NSString *token, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        dispatch_async(self->_queue, ^{
            // 登录 HTTP 可能在切换账号/发起新一轮重连之后才返回；绝不能用旧 uid 的 token 建立新连接。
            if (self->_manualClose || generation != self->_connectionGeneration
                || ![self.userID isEqualToString:uid] || ![self->_host isEqualToString:host]) {
                return;
            }
            if (token.length == 0) {
                IMLogSocket(@"登录换取 token 失败，稍后重连: %@", error.localizedDescription);
                [self scheduleReconnect];
                return;
            }
            [self openSocketWithToken:token host:host];
        });
    }];
}

/// 用换到的 token 打开 WebSocket（仅在 _queue 调用）。
- (void)openSocketWithToken:(NSString *)token host:(NSString *)host {
    NSString *encoded = [token stringByAddingPercentEncodingWithAllowedCharacters:
                         NSCharacterSet.URLQueryAllowedCharacterSet] ?: token;
    NSString *urlStr = [NSString stringWithFormat:@"ws://%@/ws?token=%@", host, encoded];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) {
        IMLogSocket(@"非法 ws 地址 host=%@", host);
        [self scheduleReconnect];
        return;
    }
    NSOperationQueue *delegateQueue = [NSOperationQueue new];
    delegateQueue.maxConcurrentOperationCount = 1;
    _session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration
                                             delegate:self
                                        delegateQueue:delegateQueue];
    _task = [_session webSocketTaskWithURL:url];
    [_task resume];
    [self receiveNext];
    IMLogSocket(@"connecting ws://%@/ws (token)", host);
}

/// 经 HTTP 登录接口换取 JWT（开发期无密码，仅凭 uid 签发）。completion 可能在任意线程回调。
- (void)fetchTokenForHost:(NSString *)host userID:(NSString *)uid completion:(void (^)(NSString *token, NSError *error))completion {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://%@/api/v1/login", host]];
    if (!url) {
        completion(nil, [self errorWithCode:5003 msg:@"非法登录地址"]);
        return;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    // 与 HTTP 层共用同一登录态：带上全局密码（空=后端开发期免密直签）。
    NSString *password = IMHTTPService.sharedService.password ?: @"";
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{ @"username": uid ?: @"", @"password": password } options:0 error:NULL];
    req.timeoutInterval = 10;

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:req
                                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (error) { completion(nil, error); return; }
        id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        NSDictionary *body = [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
        NSDictionary *payload = [body[@"data"] isKindOfClass:[NSDictionary class]] ? body[@"data"] : nil;
        NSString *token = [payload[@"token"] isKindOfClass:[NSString class]] ? payload[@"token"] : nil;
        if ([body[@"code"] integerValue] != 0 || token.length == 0) {
            completion(nil, [self errorWithCode:5004 msg:@"登录失败"]);
            return;
        }
        completion(token, nil);
    }];
    [task resume];
}

/// 关闭并清理当前连接资源（仅在 _queue 调用）。
- (void)teardownSocket {
    [self stopHeartbeat];
    [_task cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:nil];
    _task = nil;
    [_session invalidateAndCancel];
    _session = nil;
}

#pragma mark - 断线与重连

/// 统一处理一次断线：清理、失败未决发送、按需重连（仅在 _queue 调用）。
- (void)handleDisconnect:(nullable NSError *)error {
    if (self.state == IMSocketStateDisconnected && _task == nil) {
        return; // 已处理过，避免重复
    }
    IMLogSocket(@"disconnected: %@", error.localizedDescription ?: @"(closed)");
    [self teardownSocket];
    [_syncingConvs removeAllObjects]; // 未收到的 sync_resp 已失效；重连后从已持久化连续位置重发
    [self updateState:IMSocketStateDisconnected];
    if (!_manualClose) {
        [self scheduleReconnect];
    }
}

/// 指数退避重连（仅在 _queue 调用）。
- (void)scheduleReconnect {
    if (_manualClose) { return; }
    NSTimeInterval delay = MIN(kIMReconnectCap, kIMReconnectBase * pow(2, _reconnectAttempts));
    _reconnectAttempts++;
    NSUInteger generation = _connectionGeneration;
    IMLogSocket(@"reconnect in %.1fs (attempt %ld)", delay, (long)_reconnectAttempts);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), _queue, ^{
        if (self->_manualClose || generation != self->_connectionGeneration) { return; }
        [self openSocket];
    });
}

#pragma mark - 收发

/// 递归接收下一帧（completion 回到任意线程，统一切回 _queue 处理）。
- (void)receiveNext {
    NSURLSessionWebSocketTask *task = _task;
    if (!task) { return; }
    __weak typeof(self) weakSelf = self;
    [task receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        dispatch_async(self->_queue, ^{
            if (task != self->_task) { return; }   // 旧连接的回调，丢弃
            if (error) {
                [self handleDisconnect:error];
                return;
            }
            if (message.type == NSURLSessionWebSocketMessageTypeString) {
                [self handleFrame:message.string];
            }
            [self receiveNext];
        });
    }];
}

/// 解析并分发一帧文本信封（仅在 _queue 调用）。
- (void)handleFrame:(NSString *)text {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    NSError *err = nil;
    id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&err] : nil;
    if (![obj isKindOfClass:[NSDictionary class]]) {
        IMLogSocket(@"丢弃非法信封: %@ (%@)", text, err.localizedDescription);
        return;
    }
    NSDictionary *env = obj;
    NSString *type = env[kIMKeyType];
    NSDictionary *payload = [env[kIMKeyData] isKindOfClass:[NSDictionary class]] ? env[kIMKeyData] : @{};

    if ([type isEqualToString:kIMTypeAck]) {
        [self handleAck:payload];
    } else if ([type isEqualToString:kIMTypeNewMsg]) {
        [self handleNewMsg:payload];
    } else if ([type isEqualToString:kIMTypeSyncResp]) {
        [self handleSyncResp:payload];
    } else if ([type isEqualToString:kIMTypeReceipt]) {
        [self handleReceipt:payload];
    } else if ([type isEqualToString:kIMTypeTyping]) {
        [self handleTyping:payload];
    } else if ([type isEqualToString:kIMTypePresence]) {
        [self handlePresence:payload];
    } else if ([type isEqualToString:kIMTypeFriend]) {
        [self handleFriendEvent];
    } else if ([type isEqualToString:kIMTypeGroup]) {
        [self handleGroupEvent:payload];
    } else if ([type isEqualToString:kIMTypeMsgOp]) {
        [self applyMsgOpPayload:payload];
    } else if ([type isEqualToString:kIMTypeConvUpdate]) {
        [self handleConvUpdate:payload];
    } else if ([type isEqualToString:kIMTypePong]) {
        // 心跳回应，无需处理
    } else if ([type isEqualToString:kIMTypeError]) {
        NSString *cmid = [payload[@"client_msg_id"] isKindOfClass:[NSString class]] ? payload[@"client_msg_id"] : nil;
        // 消息操作被拒（如撤回超时 300008）：不动消息，主线程广播回滚提示。
        if (cmid.length > 0 && [_pendingOps containsObject:cmid]) {
            [_pendingOps removeObject:cmid];
            NSString *msg = [payload[@"message"] isKindOfClass:[NSString class]] ? payload[@"message"] : @"操作失败";
            dispatch_async(dispatch_get_main_queue(), ^{
                [NSNotificationCenter.defaultCenter postNotificationName:IMSocketDidRejectMsgOpNotification
                                                                  object:self userInfo:@{ @"message": msg }];
            });
        } else if (cmid.length > 0) {
            // 带 client_msg_id 的 error = 对某条 send_msg 的拒绝（如被拉黑）→ 立刻判该条发送失败。
            [self handleSendRejected:cmid code:[payload[@"code"] integerValue] message:payload[@"message"]];
        } else {
            IMLogSocket(@"服务端 error: %@", payload);
        }
    } else {
        IMLogSocket(@"未处理类型: %@", type);
    }
}

#pragma mark - 心跳

- (void)startHeartbeat {
    [self stopHeartbeat];
    _pingTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
    dispatch_source_set_timer(_pingTimer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kIMPingInterval * NSEC_PER_SEC)),
                              (uint64_t)(kIMPingInterval * NSEC_PER_SEC),
                              (uint64_t)(1 * NSEC_PER_SEC));
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_pingTimer, ^{
        [weakSelf sendEnvelopeType:kIMTypePing data:nil completion:nil];
    });
    dispatch_resume(_pingTimer);
}

- (void)stopHeartbeat {
    if (_pingTimer) {
        dispatch_source_cancel(_pingTimer);
        _pingTimer = nil;
    }
}

#pragma mark - 发送 + ACK 超时重发

- (NSString *)sendText:(NSString *)text toUser:(NSString *)toUserID completion:(IMSendCompletion)completion {
    return [self sendText:text toUser:toUserID replyToConvSeq:0 completion:completion];
}

- (NSString *)sendText:(NSString *)text toConv:(NSString *)convID completion:(IMSendCompletion)completion {
    return [self sendText:text toConv:convID replyToConvSeq:0 completion:completion];
}

- (NSString *)sendText:(NSString *)text toUser:(NSString *)toUserID replyToConvSeq:(int64_t)replyToConvSeq completion:(IMSendCompletion)completion {
    NSString *convID = IMConversationID(self.userID ?: @"", toUserID);
    return [self sendText:text toUser:toUserID convID:convID replyToConvSeq:replyToConvSeq forwardFrom:nil completion:completion];
}

- (NSString *)sendText:(NSString *)text toConv:(NSString *)convID replyToConvSeq:(int64_t)replyToConvSeq completion:(IMSendCompletion)completion {
    // 群聊：to 留空，服务端按 conv_id 查群成员写扩散（PROTOCOL §6.6）。
    return [self sendText:text toUser:@"" convID:convID replyToConvSeq:replyToConvSeq forwardFrom:nil completion:completion];
}

- (NSString *)forwardText:(NSString *)text toConv:(NSString *)convID toUser:(NSString *)toUserID forwardFrom:(NSString *)forwardFrom completion:(IMSendCompletion)completion {
    return [self sendText:text toUser:(toUserID ?: @"") convID:convID replyToConvSeq:0 forwardFrom:forwardFrom completion:completion];
}

- (NSString *)forwardContent:(NSString *)content contentType:(NSString *)contentType toConv:(NSString *)convID toUser:(NSString *)toUserID forwardFrom:(NSString *)forwardFrom fileName:(NSString *)fileName fileSize:(int64_t)fileSize completion:(IMSendCompletion)completion {
    return [self forwardContent:content contentType:contentType toConv:convID toUser:toUserID forwardFrom:forwardFrom
                       fileName:fileName fileSize:fileSize attributes:nil completion:completion];
}

- (NSString *)forwardContent:(NSString *)content contentType:(NSString *)contentType toConv:(NSString *)convID toUser:(NSString *)toUserID forwardFrom:(NSString *)forwardFrom fileName:(NSString *)fileName fileSize:(int64_t)fileSize attributes:(IMMediaAttributes *)attributes completion:(IMSendCompletion)completion {
    NSString *ct = contentType.length > 0 ? contentType : @"text";
    if ([ct isEqualToString:@"text"]) { // 文本走既有路径（可带引用等），媒体走带 content_type 的负载
        return [self forwardText:content toConv:convID toUser:toUserID forwardFrom:forwardFrom completion:completion];
    }
    NSString *clientMsgID = [NSUUID UUID].UUIDString;
    NSMutableDictionary *payload = [@{
        @"client_msg_id": clientMsgID,
        @"conv_id":       convID ?: @"",
        @"to":            toUserID ?: @"",
        @"content_type":  ct,
        @"content":       content ?: @"",
    } mutableCopy];
    if (forwardFrom.length > 0) { payload[@"forward_from"] = forwardFrom; }
    if ([ct isEqualToString:@"file"] && fileName.length > 0) { payload[@"file_name"] = fileName; }
    if ([ct isEqualToString:@"file"] && fileSize > 0) { payload[@"file_size"] = @(fileSize); }
    [self applyMediaAttributes:attributes toPayload:payload]; // 封面/尺寸/时长随转发一并带走
    dispatch_async(_queue, ^{
        [self enqueueSendWithClientMsgID:clientMsgID payload:payload completion:completion];
    });
    return clientMsgID;
}

/// 把媒体元数据写进 send_msg 负载（PROTOCOL §4.1）：0/空=未知，不上行。发送与转发共用。
/// 这里是媒体上行的唯一收口，故也是"发出去到底带没带尺寸/时长"的唯一可信日志点。
- (void)applyMediaAttributes:(IMMediaAttributes *)attributes toPayload:(NSMutableDictionary *)payload {
    if (!attributes) { return; }
    if (attributes.groupID.length > 0) { payload[@"group_id"] = attributes.groupID; } // 相册分组（M4+），服务端透传
    if (attributes.poster.length > 0) { payload[@"poster"] = attributes.poster; }     // 视频封面首帧 URL（M4+），收端直显免解码
    if (attributes.pixelWidth > 0)  { payload[@"media_w"] = @(attributes.pixelWidth); }
    if (attributes.pixelHeight > 0) { payload[@"media_h"] = @(attributes.pixelHeight); }
    if (attributes.durationMillis > 0) { payload[@"duration"] = @(attributes.durationMillis); }
    if (attributes.fileSize > 0 && !payload[@"file_size"]) { payload[@"file_size"] = @(attributes.fileSize); }

    NSString *ct = payload[@"content_type"] ?: @"";
    BOOL isMedia = [ct isEqualToString:@"image"] || [ct isEqualToString:@"video"];
    if (!isMedia) { return; }
    // 只记元数据，不记 content/poster URL 之外的业务正文（URL 属媒体元信息，允许）。
    if (attributes.pixelWidth <= 0 || attributes.pixelHeight <= 0) {
        // 收端只能回退"加载完再自适应"，是排版异常的头号根因 → 发出即留痕。
        IMLogWarnWithTag(IMLogTagMedia, @"media_meta_missing conv_id=%@ client_msg_id=%@ content_type=%@ bytes=%lld has_poster=%@",
                         payload[@"conv_id"], payload[@"client_msg_id"], ct, attributes.fileSize,
                         attributes.poster.length > 0 ? @"1" : @"0");
        return;
    }
    IMLogMedia(@"media_meta_attached conv_id=%@ client_msg_id=%@ content_type=%@ media_w=%ld media_h=%ld duration_ms=%lld bytes=%lld",
                payload[@"conv_id"], payload[@"client_msg_id"], ct,
                (long)attributes.pixelWidth, (long)attributes.pixelHeight, attributes.durationMillis, attributes.fileSize);
}

- (NSString *)sendMedia:(NSString *)url contentType:(NSString *)contentType toConv:(NSString *)convID toUser:(NSString *)toUserID completion:(IMSendCompletion)completion {
    return [self sendMedia:url contentType:contentType toConv:convID toUser:toUserID groupID:nil poster:nil completion:completion];
}

- (NSString *)sendFile:(NSString *)url fileName:(NSString *)fileName fileSize:(int64_t)fileSize toConv:(NSString *)convID toUser:(NSString *)toUserID completion:(IMSendCompletion)completion {
    NSString *clientMsgID = [NSUUID UUID].UUIDString;
    NSMutableDictionary *payload = [@{
        @"client_msg_id": clientMsgID,
        @"conv_id": convID ?: @"",
        @"to": toUserID ?: @"",
        @"content_type": @"file",
        @"content": url ?: @"",
        @"file_name": fileName ?: @"",
        @"file_size": @(fileSize),
    } mutableCopy];
    dispatch_async(_queue, ^{
        [self enqueueSendWithClientMsgID:clientMsgID payload:payload completion:completion];
    });
    return clientMsgID;
}

- (NSString *)sendMedia:(NSString *)url contentType:(NSString *)contentType toConv:(NSString *)convID toUser:(NSString *)toUserID groupID:(NSString *)groupID completion:(IMSendCompletion)completion {
    return [self sendMedia:url contentType:contentType toConv:convID toUser:toUserID groupID:groupID poster:nil completion:completion];
}

- (NSString *)sendMedia:(NSString *)url contentType:(NSString *)contentType toConv:(NSString *)convID toUser:(NSString *)toUserID groupID:(NSString *)groupID poster:(NSString *)poster completion:(IMSendCompletion)completion {
    return [self sendMedia:url contentType:contentType toConv:convID toUser:toUserID
                attributes:[IMMediaAttributes attributesWithGroupID:groupID poster:poster] completion:completion];
}

- (NSString *)sendMedia:(NSString *)url contentType:(NSString *)contentType toConv:(NSString *)convID toUser:(NSString *)toUserID attributes:(IMMediaAttributes *)attributes completion:(IMSendCompletion)completion {
    NSString *clientMsgID = [NSUUID UUID].UUIDString;
    NSMutableDictionary *payload = [@{
        @"client_msg_id": clientMsgID,
        @"conv_id":       convID ?: @"",
        @"to":            toUserID ?: @"",
        @"content_type":  contentType ?: @"image",
        @"content":       url ?: @"",
    } mutableCopy];
    [self applyMediaAttributes:attributes toPayload:payload];
    dispatch_async(_queue, ^{
        [self enqueueSendWithClientMsgID:clientMsgID payload:payload completion:completion];
    });
    return clientMsgID;
}

/// 共用发送路径：构造 send_msg 负载并入队（ack 超时重发等由 enqueue 统一处理）。
- (NSString *)sendText:(NSString *)text toUser:(NSString *)toUserID convID:(NSString *)convID replyToConvSeq:(int64_t)replyToConvSeq forwardFrom:(NSString *)forwardFrom completion:(IMSendCompletion)completion {
    NSString *clientMsgID = [NSUUID UUID].UUIDString;
    NSMutableDictionary *payload = [@{
        @"client_msg_id": clientMsgID,
        @"conv_id":       convID ?: @"",
        @"to":            toUserID ?: @"",
        @"content_type":  @"text",
        @"content":       text ?: @"",
    } mutableCopy];
    if (replyToConvSeq > 0) { payload[@"reply_to"] = @{ @"conv_seq": @(replyToConvSeq) }; } // 引用（M4-2）
    if (forwardFrom.length > 0) { payload[@"forward_from"] = forwardFrom; }                 // 转发溯源（M4-3）
    dispatch_async(_queue, ^{
        [self enqueueSendWithClientMsgID:clientMsgID payload:payload completion:completion];
    });
    return clientMsgID;
}

/// 序列化 send_msg、登记待确认项、发送并武装超时（仅在 _queue 调用）。
- (void)enqueueSendWithClientMsgID:(NSString *)clientMsgID
                           payload:(NSDictionary *)payload
                        completion:(IMSendCompletion)completion {
    NSData *frame = [self encodeEnvelopeType:kIMTypeSendMsg data:payload];
    if (!frame) {
        [self finishSend:completion success:NO error:[self errorWithCode:5001 msg:@"序列化失败"] convSeq:0];
        return;
    }
    IMPendingSend *p = [IMPendingSend new];
    p.clientMsgID = clientMsgID;
    p.payload = frame;
    p.completion = completion;
    _pending[clientMsgID] = p;
    [self writeData:frame];
    [self armAckTimer:p];
}

/// 为待确认项武装一个超时定时器（仅在 _queue 调用）。
- (void)armAckTimer:(IMPendingSend *)p {
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
    dispatch_source_set_timer(timer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kIMAckTimeout * NSEC_PER_SEC)),
                              DISPATCH_TIME_FOREVER, (uint64_t)(0.5 * NSEC_PER_SEC));
    __weak typeof(self) weakSelf = self;
    __weak IMPendingSend *weakP = p;
    dispatch_source_set_event_handler(timer, ^{
        [weakSelf handleAckTimeout:weakP];
    });
    p.ackTimer = timer;
    dispatch_resume(timer);
}

/// ack 超时：未超次数则用同一 client_msg_id 重发，否则判失败（仅在 _queue 调用）。
- (void)handleAckTimeout:(IMPendingSend *)p {
    if (!p || _pending[p.clientMsgID] != p) { return; }
    [self cancelAckTimer:p];
    if (p.retries < kIMMaxResend) {
        p.retries++;
        IMLogSocket(@"ack 超时，重发 %@ (第 %ld 次)", p.clientMsgID, (long)p.retries);
        [self writeData:p.payload];
        [self armAckTimer:p];
    } else {
        [_pending removeObjectForKey:p.clientMsgID];
        IMLogSocket(@"ack 重发耗尽，判失败 %@", p.clientMsgID);
        [self finishSend:p.completion success:NO error:[self errorWithCode:5002 msg:@"ack 超时"] convSeq:0];
    }
}

- (void)cancelAckTimer:(IMPendingSend *)p {
    if (p.ackTimer) {
        dispatch_source_cancel(p.ackTimer);
        p.ackTimer = nil;
    }
}

/// 主动退出或切换账号时终止旧账号的未决发送，避免其定时器在新账号连接上重发旧负载（仅在 _queue 调用）。
- (void)cancelAllPendingSendsWithMessage:(NSString *)message {
    NSArray<IMPendingSend *> *pending = _pending.allValues;
    [_pending removeAllObjects];
    for (IMPendingSend *item in pending) {
        [self cancelAckTimer:item];
        [self finishSend:item.completion
                 success:NO
                   error:[self errorWithCode:5005 msg:message ?: @"发送已取消"]
                 convSeq:0];
    }
}

/// 处理 ack：匹配待确认项，停表，回调成功（仅在 _queue 调用）。
- (void)handleAck:(NSDictionary *)data {
    NSString *clientMsgID = data[@"client_msg_id"];
    IMPendingSend *p = clientMsgID ? _pending[clientMsgID] : nil;
    if (!p) { return; } // 重发产生的重复 ack，已处理过
    [self cancelAckTimer:p];
    [_pending removeObjectForKey:clientMsgID];
    int64_t convSeq = [data[@"conv_seq"] longLongValue];
    // ACK 只证明这一条已保存，不证明它之前的所有 conv_seq 已连续同步；不能拿它推进历史游标。
    [self finishSend:p.completion success:YES error:nil convSeq:convSeq];
}

/// 服务端拒收某条 send_msg（被拉黑 200102 / 被禁言 300004 等）：取消重发计时、判该条失败（不重试）。
/// 透传服务端真实 code，供 UI 区分提示（含被拒文案）。仅在 _queue 调用。
- (void)handleSendRejected:(NSString *)clientMsgID code:(NSInteger)code message:(NSString *)message {
    IMPendingSend *p = _pending[clientMsgID];
    if (!p) { return; }
    [self cancelAckTimer:p];
    [_pending removeObjectForKey:clientMsgID];
    NSString *msg = ([message isKindOfClass:[NSString class]] && message.length > 0) ? message : @"发送失败";
    if (code == 0) { code = 200102; } // 兜底：缺 code 按拒收处理
    [self finishSend:p.completion success:NO error:[self errorWithCode:code msg:msg] convSeq:0];
}

/// 处理 new_msg：走统一的「收到一条消息」流程（仅在 _queue 调用）。
- (void)handleNewMsg:(NSDictionary *)data {
    [self processIncomingMessage:[IMMessageModel receivedMessageWithNewMsgData:data]];
}

/// 处理 sync_resp：按会话投递增量消息；has_more 时以新位点继续拉（仅在 _queue 调用）。
- (void)handleSyncResp:(NSDictionary *)data {
    NSArray *convs = [data[@"conversations"] isKindOfClass:[NSArray class]] ? data[@"conversations"] : @[];
    for (NSDictionary *conv in convs) {
        if (![conv isKindOfClass:[NSDictionary class]]) { continue; }
        NSString *convID = conv[@"conv_id"];
        if (convID.length > 0) { [_syncingConvs removeObject:convID]; }
        int64_t pageStart = [self syncedSeqForConv:convID];
        NSArray *messages = [conv[@"messages"] isKindOfClass:[NSArray class]] ? conv[@"messages"] : @[];
        for (NSDictionary *md in messages) {
            if (![md isKindOfClass:[NSDictionary class]]) { continue; }
            [self processIncomingMessage:[IMMessageModel receivedMessageWithNewMsgData:md]];
        }
        int64_t responseLatest = [conv[@"latest_conv_seq"] longLongValue];
        int64_t continuous = [self syncedSeqForConv:convID];
        // latest_conv_seq 是“本页最后一条”，只能用于校验，不能强制覆盖客户端连续位置。
        // 若服务端页内意外缺号，停在空洞前并等待后续重连重试，绝不越级落游标。
        BOOL pageIsContinuous = responseLatest == continuous;
        if (!pageIsContinuous) {
            IMLogSocket(@"sync page not contiguous conv=%@ start=%lld response_latest=%lld continuous=%lld",
                        convID ?: @"", pageStart, responseLatest, continuous);
        }
        // 一整页处理完位点纹丝没动（典型：落库持续失败）——立刻重拉只会拿到同一页、再失败，
        // 形成打满 CPU/磁盘的热循环（真机复现：13s 内 2.2 万条失败日志）。退避 10s 后再试。
        if (messages.count > 0 && continuous == pageStart && convID.length > 0) {
            _syncStalledUntil[convID] = @(CFAbsoluteTimeGetCurrent() + 10);
            IMLogSocket(@"sync stalled (no durable progress); backing off 10s conv=%@ synced=%lld", convID, continuous);
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), _queue, ^{
                __strong typeof(weakSelf) self = weakSelf;
                if (!self) { return; }
                [self sendSyncReqForConvs:@[convID]]; // 到点重试；仍无进展会再次退避，节奏 6 次/分钟
            });
            continue;
        }
        [_syncStalledUntil removeObjectForKey:convID ?: @""];
        if ([conv[@"has_more"] boolValue] && convID.length > 0) {
            if (pageIsContinuous && continuous > pageStart) {
                [self sendSyncReqForConvs:@[convID]]; // 仅以本页实际连续处理完成的位置继续翻页
            } else {
                IMLogSocket(@"sync pagination stopped without continuous progress conv=%@", convID);
            }
        }
    }
}

/// 统一处理收到的一条消息：推进同步位点、回执、投递 delegate（仅在 _queue 调用）。
- (void)processIncomingMessage:(IMMessageModel *)msg {
    int64_t prevSynced = [self syncedSeqForConv:msg.convID];
    BOOL isNextContiguous = msg.convSeq > 0 && msg.convSeq == prevSynced + 1;
    // msg_op 事件行（撤回/编辑/置顶，来自 sync 补拉）：应用其效果、不作气泡渲染、不入库为消息。
    if ([msg.contentType isEqualToString:kIMTypeMsgOp]) {
        NSDictionary *op = [self jsonObjectFromString:msg.content];
        BOOL applied = op && [self applyMsgOpPayload:op
                             advancingSyncedConvSeq:isNextContiguous ? msg.convSeq : 0];
        if (isNextContiguous && applied) {
            [self updateSyncedSeqForConv:msg.convID seq:msg.convSeq];
        }
        return;
    }
    // 空洞自愈：conv_seq 由服务端连续分配，若收到的序号跳过了已同步位点之后的中间段，
    // 说明中间有未拉取（离线）消息 → 先从已同步位点补拉，避免实时消息把 synced 推过空洞造成漏消息。
    if (prevSynced > 0 && msg.convSeq > prevSynced + 1 && [_trackedConvs containsObject:msg.convID]) {
        [self sendSyncReqForConvs:@[msg.convID]]; // 用当前（更低的）位点作 since，把缺口拉回
    } else if (prevSynced == 0 && msg.convSeq > 1 && [_trackedConvs containsObject:msg.convID]) {
        [self sendSyncReqForConvs:@[msg.convID]]; // 新账号首次只见到较大序号，同样必须从 0 补齐
    }
    // 落库放在网络层：无论当前在会话列表还是聊天页（甚至无页面）收到的消息都持久化，
    // 避免「在列表收到、未入库、之后开聊天页因 synced 已前进而漏拉」。按 conv_seq 幂等 upsert。
    __block BOOL saved = NO;
    BOOL contextIsCurrent = [self performDatabaseOperation:^(IMDatabase *database) {
        saved = [database saveIncomingMessage:msg
                       advancingSyncedConvSeq:isNextContiguous ? msg.convSeq : 0];
    }];
    if (!contextIsCurrent) { return; }
    if ([msg.contentType isEqualToString:@"file"]) {
        IMLogSocket(@"file message conv=%@ seq=%lld from=%@ name=%@ bytes=%lld",
                    msg.convID, msg.convSeq, msg.from ?: @"", msg.fileName ?: @"", msg.fileSize);
    }
    if (isNextContiguous && saved) {
        [self updateSyncedSeqForConv:msg.convID seq:msg.convSeq];
    } else if (!saved) {
        IMLogSocket(@"incoming message not durable; cursor held conv=%@ seq=%lld", msg.convID, msg.convSeq);
    }
    if (saved) { [self sendReceiptForConv:msg.convID upTo:msg.convSeq]; }
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        id<IMSocketManagerDelegate> d = self.delegate;
        if ([d respondsToSelector:@selector(socketManager:didReceiveMessage:)]) {
            [d socketManager:self didReceiveMessage:msg];
        }
        // 广播给非当前页（会话列表实时刷新未读/最后一条），不占用单一 delegate。
        [NSNotificationCenter.defaultCenter postNotificationName:IMSocketDidReceiveMessageNotification
                                                         object:self
                                                       userInfo:@{ kIMConvIDKey: msg.convID ?: @"" }];
    });
}

/// 收到好友关系变更帧：主线程广播，通讯录刷新（无需切页）。负载仅作语义，收到即刷。
- (void)handleFriendEvent {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:IMSocketDidReceiveFriendEventNotification object:self];
    });
}

/// 收到群变更帧（invite/leave/remove/role/transfer/profile）：主线程广播，
/// 会话列表/群资料页据此刷新；remove 且 target=自己 → 客户端移出该群会话。
- (void)handleGroupEvent:(NSDictionary *)data {
    NSString *convID = [data[@"conv_id"] isKindOfClass:[NSString class]] ? data[@"conv_id"] : @"";
    NSString *event = [data[@"event"] isKindOfClass:[NSString class]] ? data[@"event"] : @"";
    NSString *target = [data[@"target"] isKindOfClass:[NSString class]] ? data[@"target"] : @"";
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:IMSocketDidReceiveGroupEventNotification
                                                          object:self
                                                        userInfo:@{ kIMConvIDKey: convID,
                                                                    kIMGroupEventKey: event,
                                                                    kIMGroupTargetKey: target }];
    });
}

/// 收到会话级设置变更帧（置顶/免打扰/标未读/删除会话，M4.5）：主线程广播，会话列表据此刷新（多端同步）。
- (void)handleConvUpdate:(NSDictionary *)data {
    NSString *convID = [data[@"conv_id"] isKindOfClass:[NSString class]] ? data[@"conv_id"] : @"";
    NSString *action = [data[@"action"] isKindOfClass:[NSString class]] ? data[@"action"] : @"";
    BOOL contextIsCurrent = YES;
    if ([action isEqualToString:@"settings"]) {
        contextIsCurrent = [self performDatabaseOperation:^(IMDatabase *database) {
            [database applyCachedSettingsForConversation:convID
                                                 pinnedAt:[data[@"pinned_at"] longLongValue]
                                                    muted:[data[@"muted"] boolValue]
                                             markedUnread:[data[@"marked_unread"] boolValue]];
        }];
    } else if ([action isEqualToString:@"delete"]) {
        contextIsCurrent = [self performDatabaseOperation:^(IMDatabase *database) {
            [database deleteCachedConversation:convID];
        }];
    }
    if (!contextIsCurrent) { return; }
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:IMSocketDidUpdateConversationNotification
                                                          object:self
                                                        userInfo:@{ kIMConvIDKey: convID }];
    });
}

#pragma mark - 消息操作（msg_op，M4）

- (void)recallMessageInConv:(NSString *)convID targetConvSeq:(int64_t)targetConvSeq {
    if (convID.length == 0 || targetConvSeq <= 0) { return; }
    NSString *clientMsgID = [NSUUID UUID].UUIDString;
    NSDictionary *payload = @{
        @"op": kIMMsgOpRecall, @"conv_id": convID,
        @"target_conv_seq": @(targetConvSeq), @"client_msg_id": clientMsgID,
    };
    dispatch_async(_queue, ^{
        [self->_pendingOps addObject:clientMsgID];
        [self sendEnvelopeType:kIMTypeMsgOp data:payload completion:nil];
    });
}

- (void)editMessageInConv:(NSString *)convID targetConvSeq:(int64_t)targetConvSeq content:(NSString *)content {
    if (convID.length == 0 || targetConvSeq <= 0 || content.length == 0) { return; }
    NSString *clientMsgID = [NSUUID UUID].UUIDString;
    NSDictionary *payload = @{
        @"op": kIMMsgOpEdit, @"conv_id": convID,
        @"target_conv_seq": @(targetConvSeq), @"content": content, @"client_msg_id": clientMsgID,
    };
    dispatch_async(_queue, ^{
        [self->_pendingOps addObject:clientMsgID];
        [self sendEnvelopeType:kIMTypeMsgOp data:payload completion:nil];
    });
}

/// 应用一条消息操作到本地（DB 落库 + 主线程广播）。payload 来自实时 msg_op 帧或 sync 的 msg_op 事件行负载。
/// 仅在 _queue 调用。
- (void)applyMsgOpPayload:(NSDictionary *)payload {
    [self applyMsgOpPayload:payload advancingSyncedConvSeq:0];
}

- (BOOL)applyMsgOpPayload:(NSDictionary *)payload advancingSyncedConvSeq:(int64_t)syncedConvSeq {
    NSString *op = [payload[@"op"] isKindOfClass:[NSString class]] ? payload[@"op"] : @"";
    NSString *convID = [payload[@"conv_id"] isKindOfClass:[NSString class]] ? payload[@"conv_id"] : @"";
    int64_t target = [payload[@"target_conv_seq"] longLongValue];
    if (convID.length == 0 || target <= 0) { return NO; }

    NSString *cmid = [payload[@"client_msg_id"] isKindOfClass:[NSString class]] ? payload[@"client_msg_id"] : nil;
    if (cmid.length > 0) { [_pendingOps removeObject:cmid]; } // 我方操作成功回执

    int64_t now = (int64_t)([NSDate date].timeIntervalSince1970 * 1000);
    NSString *newContent = nil;
    int64_t recalledAt = 0, editedAt = 0, pinnedAt = 0;
    if ([op isEqualToString:kIMMsgOpRecall]) {
        recalledAt = now;
    } else if ([op isEqualToString:kIMMsgOpEdit]) {
        editedAt = now;
        newContent = [payload[@"content"] isKindOfClass:[NSString class]] ? payload[@"content"] : @"";
    } else if ([op isEqualToString:kIMMsgOpPin]) {
        pinnedAt = now;
    } else {
        return NO; // 未知 op：忽略不崩
    }
    NSString *by = [payload[@"by"] isKindOfClass:[NSString class]] ? payload[@"by"] : nil;
    __block BOOL applied = NO;
    [self performDatabaseOperation:^(IMDatabase *database) {
        applied = [database applyMsgOpForConv:convID targetConvSeq:target
                                    recalledAt:recalledAt recalledBy:by
                                      editedAt:editedAt pinnedAt:pinnedAt newContent:newContent
                          advancingSyncedConvSeq:syncedConvSeq];
    }];
    if (!applied) { return NO; }
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableDictionary *info = [@{ kIMConvIDKey: convID, kIMMsgOpTargetSeqKey: @(target), kIMMsgOpKey: op } mutableCopy];
        if (newContent) { info[kIMMsgOpContentKey] = newContent; }
        [NSNotificationCenter.defaultCenter postNotificationName:IMSocketDidApplyMsgOpNotification object:self userInfo:info];
    });
    return YES;
}

/// 从 JSON 字符串解析字典（op 事件行 content 自描述负载）；非法返回 nil。
- (nullable NSDictionary *)jsonObjectFromString:(NSString *)s {
    NSData *d = [s isKindOfClass:[NSString class]] ? [s dataUsingEncoding:NSUTF8StringEncoding] : nil;
    id obj = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
    return [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
}

/// 回送送达回执（仅在 _queue 调用）。
- (void)sendReceiptForConv:(NSString *)convID upTo:(int64_t)convSeq {
    if (convID.length == 0) { return; }
    [self sendEnvelopeType:kIMTypeReceipt
                      data:@{ @"conv_id": convID, @"status": @"delivered", @"up_to_conv_seq": @(convSeq) }
                completion:nil];
}

#pragma mark - M2：已读回执 / 正在输入 / 在线状态

/// 上报已读（status=read 推进已读位点）（异步进 _queue）。
- (void)markReadConv:(NSString *)convID upToConvSeq:(int64_t)convSeq {
    if (convID.length == 0 || convSeq <= 0) { return; }
    dispatch_async(_queue, ^{
        [self sendEnvelopeType:kIMTypeReceipt
                          data:@{ @"conv_id": convID, @"status": @"read", @"up_to_conv_seq": @(convSeq) }
                    completion:nil];
    });
}

/// 发送「正在输入」（异步进 _queue）。
- (void)sendTypingForConv:(NSString *)convID {
    if (convID.length == 0) { return; }
    dispatch_async(_queue, ^{
        [self sendEnvelopeType:kIMTypeTyping data:@{ @"conv_id": convID } completion:nil];
    });
}

/// 上报在线态关注全集（异步进 _queue）。userIDs 为 nil 视作空集（取消全部关注）。
- (void)watchUsers:(NSArray<NSString *> *)userIDs {
    NSArray<NSString *> *set = [userIDs isKindOfClass:[NSArray class]] ? userIDs : @[];
    dispatch_async(_queue, ^{
        // 诊断：在线态订阅链路的「发出」书挡，与服务端 watch_registered、下方 presence 收到对账。
        IMLogSocket(@"watch → %lu 个: [%@]", (unsigned long)set.count, [set componentsJoinedByString:@","]);
        [self sendEnvelopeType:kIMTypeWatch data:@{ @"set": set } completion:nil];
    });
}

/// 处理对端已读回执（仅在 _queue 调用）：只关心 read，投递 delegate。
- (void)handleReceipt:(NSDictionary *)data {
    if (![data[@"status"] isEqual:@"read"]) { return; } // delivered 单勾本端暂不显示
    NSString *convID = [data[@"conv_id"] isKindOfClass:[NSString class]] ? data[@"conv_id"] : nil;
    NSString *from = [data[@"from"] isKindOfClass:[NSString class]] ? data[@"from"] : @"";
    int64_t upTo = [data[@"up_to_conv_seq"] longLongValue];
    if (convID.length == 0) { return; }
    BOOL contextIsCurrent = NO;
    if ([from isEqualToString:self.userID]) {
        contextIsCurrent = [self performDatabaseOperation:^(IMDatabase *database) {
            [database markConversation:convID readUpToConvSeq:upTo];
        }];
    } else {
        contextIsCurrent = [self performDatabaseOperation:^(IMDatabase *database) {
            [database markConversation:convID peerReadUpToConvSeq:upTo];
        }];
    }
    if (!contextIsCurrent) { return; }
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        id<IMSocketManagerDelegate> d = self.delegate;
        if ([d respondsToSelector:@selector(socketManager:didReadConv:by:upToConvSeq:)]) {
            [d socketManager:self didReadConv:convID by:from upToConvSeq:upTo];
        }
        // 广播给会话列表（非当前页）：对端已读→列表"我发的"变✓✓；本人多端已读→列表未读清零。
        [NSNotificationCenter.defaultCenter postNotificationName:IMSocketDidReceiveReadNotification
                                                         object:self
                                                       userInfo:@{ kIMConvIDKey: convID ?: @"" }];
    });
}

/// 处理对端「正在输入」（仅在 _queue 调用）。
- (void)handleTyping:(NSDictionary *)data {
    NSString *convID = [data[@"conv_id"] isKindOfClass:[NSString class]] ? data[@"conv_id"] : nil;
    NSString *from = [data[@"from"] isKindOfClass:[NSString class]] ? data[@"from"] : @"";
    if (convID.length == 0) { return; }
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        id<IMSocketManagerDelegate> d = self.delegate;
        if ([d respondsToSelector:@selector(socketManager:didTypingInConv:by:)]) {
            [d socketManager:self didTypingInConv:convID by:from];
        }
    });
}

/// 处理在线状态广播（仅在 _queue 调用）。服务端只推上线；下线由 presence.onlineUntil 到期本地降级。
- (void)handlePresence:(NSDictionary *)data {
    NSString *user = [data[@"user"] isKindOfClass:[NSString class]] ? data[@"user"] : nil;
    if (user.length == 0) { return; }
    IMPresence *presence = [IMPresence presenceFromFrameDictionary:data];
    // 诊断：在线态链路的「收到」书挡（在此记全部 presence 帧，不受当前 delegate 页过滤影响）。
    NSString *presenceStatus = [data[@"status"] isKindOfClass:[NSString class]] ? data[@"status"] : @"?";
    IMLogSocket(@"presence 收到 %@ → %@", user, presenceStatus);
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        id<IMSocketManagerDelegate> d = self.delegate;
        if ([d respondsToSelector:@selector(socketManager:didChangePresenceForUser:presence:)]) {
            [d socketManager:self didChangePresenceForUser:user presence:presence];
        }
        // 同时广播给非 delegate 页（会话列表）：对端上线帧一到即时点亮列表绿点，无需等下次重拉 /conversations。
        [NSNotificationCenter.defaultCenter postNotificationName:IMSocketDidReceivePresenceNotification
                                                         object:self
                                                       userInfo:@{ kIMPresenceUserKey: user, kIMPresenceKey: presence }];
    });
}

#pragma mark - 增量同步（重连补偿拉取）

- (void)trackConversation:(NSString *)convID {
    [self trackConversation:convID syncedSeq:0];
}

- (void)trackConversation:(NSString *)convID syncedSeq:(int64_t)syncedSeq {
    if (convID.length == 0) { return; }
    dispatch_async(_queue, ^{
        [self updateSyncedSeqForConv:convID seq:syncedSeq]; // 以持久化位点为起点（取较大值）
        [self->_trackedConvs addObject:convID];
        if (self.state == IMSocketStateConnected) {
            [self sendSyncReqForConvs:@[convID]];
        }
    });
}

/// 当前会话已同步到的最大 conv_seq（仅在 _queue 调用）。
- (int64_t)syncedSeqForConv:(NSString *)convID {
    return convID ? _syncedSeq[convID].longLongValue : 0;
}

/// 推进会话同步位点（取较大值，幂等）（仅在 _queue 调用）。
- (void)updateSyncedSeqForConv:(NSString *)convID seq:(int64_t)seq {
    if (convID.length == 0 || seq <= 0) { return; }
    if (seq > [self syncedSeqForConv:convID]) {
        _syncedSeq[convID] = @(seq);
    }
}

/// 为指定会话从各自已同步位点发一个 sync_req（仅在 _queue 调用）。
- (void)sendSyncReqForConvs:(NSArray<NSString *> *)convIDs {
    NSMutableArray *cursors = [NSMutableArray array];
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    for (NSString *convID in convIDs) {
        if ([_syncingConvs containsObject:convID]) { continue; }
        if (_syncStalledUntil[convID].doubleValue > now) { continue; } // 退避期内不追加请求（处理空洞/落库失败的热循环）
        [cursors addObject:@{ @"conv_id": convID, @"since_conv_seq": @([self syncedSeqForConv:convID]) }];
        [_syncingConvs addObject:convID];
    }
    if (cursors.count == 0) { return; }
    [self sendEnvelopeType:kIMTypeSyncReq data:@{ @"cursors": cursors } completion:nil];
}

/// （重）连成功后对所有已登记会话发起增量同步（仅在 _queue 调用）。
- (void)syncTrackedConversations {
    [self sendSyncReqForConvs:_trackedConvs.allObjects];
    // 离线期间在本地读过的位点也要在重连后重放；服务端按最大值幂等推进。
    __block NSArray<IMConversation *> *cachedConversations = @[];
    [self performDatabaseOperation:^(IMDatabase *database) {
        cachedConversations = database.cachedConversations;
    }];
    for (IMConversation *conversation in cachedConversations) {
        if (conversation.readSeq > 0) {
            [self sendEnvelopeType:kIMTypeReceipt
                              data:@{ @"conv_id": conversation.convID ?: @"",
                                      @"status": @"read",
                                      @"up_to_conv_seq": @(conversation.readSeq) }
                        completion:nil];
        }
    }
}

#pragma mark - 信封编码与写出

/// 编码并立即写出一个无需 ack 的信封（ping/receipt）（仅在 _queue 调用）。
- (void)sendEnvelopeType:(NSString *)type data:(nullable NSDictionary *)data completion:(nullable IMSendCompletion)completion {
    NSData *frame = [self encodeEnvelopeType:type data:data];
    if (frame) { [self writeData:frame]; }
}

/// 把负载包成信封并序列化为 JSON（失败返回 nil 并记日志）。
- (nullable NSData *)encodeEnvelopeType:(NSString *)type data:(nullable NSDictionary *)data {
    NSMutableDictionary *env = [NSMutableDictionary dictionaryWithObject:type forKey:kIMKeyType];
    env[kIMKeySeq] = @(++_seq);
    if (data) { env[kIMKeyData] = data; }
    NSError *err = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:env options:0 error:&err];
    if (!json) { IMLogSocket(@"信封序列化失败: %@", err.localizedDescription); }
    return json;
}

/// 写出一帧；未连接或写失败时记录（重发/重连机制兜底）。
- (void)writeData:(NSData *)data {
    NSURLSessionWebSocketTask *task = _task;
    if (!task || self.state != IMSocketStateConnected) {
        IMLogSocket(@"未连接，暂不发送（待重连后由超时重发兜底）");
        return;
    }
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSURLSessionWebSocketMessage *msg = [[NSURLSessionWebSocketMessage alloc] initWithString:text];
    __weak typeof(self) weakSelf = self;
    [task sendMessage:msg completionHandler:^(NSError *error) {
        if (!error) { return; }
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        IMLogSocket(@"发送失败: %@", error.localizedDescription);
        dispatch_async(self->_queue, ^{
            if (task == self->_task) {
                [self handleDisconnect:error];
            }
        });
    }];
}

#pragma mark - 状态与回调

/// 更新状态并在主线程通知 delegate（仅在 _queue 调用）。
- (void)updateState:(IMSocketState)state {
    if (_state == state) { return; }
    _state = state;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        id<IMSocketManagerDelegate> d = self.delegate;
        if ([d respondsToSelector:@selector(socketManager:didChangeState:)]) {
            [d socketManager:self didChangeState:state];
        }
        // 同时广播：会话列表等非 delegate 页据此显示 连接中/未连接（delegate 槽被聊天页占用）。
        [NSNotificationCenter.defaultCenter postNotificationName:IMSocketDidChangeStateNotification
                                                         object:self userInfo:@{ @"state": @(state) }];
    });
}

/// 统一在主线程回调发送结果。
- (void)finishSend:(nullable IMSendCompletion)completion success:(BOOL)success error:(nullable NSError *)error convSeq:(int64_t)convSeq {
    if (!completion) { return; }
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(success, error, convSeq);
    });
}

- (NSError *)errorWithCode:(NSInteger)code msg:(NSString *)msg {
    return [NSError errorWithDomain:kIMErrorDomain code:code
                           userInfo:@{ NSLocalizedDescriptionKey: msg ?: @"" }];
}

#pragma mark - NSURLSessionWebSocketDelegate

- (void)URLSession:(NSURLSession *)session webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask
didOpenWithProtocol:(NSString *)protocol {
    dispatch_async(_queue, ^{
        if (webSocketTask != self->_task) { return; }
        self->_reconnectAttempts = 0;
        [self updateState:IMSocketStateConnected];
        [self startHeartbeat];
        [self syncTrackedConversations]; // 按各会话 synced_conv_seq 触发增量同步，补回离线/缺失消息
        IMLogSocket(@"connected as uid=%@", self.userID);
    });
}

- (void)URLSession:(NSURLSession *)session webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask
  didCloseWithCode:(NSURLSessionWebSocketCloseCode)closeCode reason:(NSData *)reason {
    dispatch_async(_queue, ^{
        if (webSocketTask != self->_task) { return; }
        [self handleDisconnect:[self errorWithCode:closeCode msg:@"connection closed"]];
    });
}

@end
