//  IMSocketManager.m

#import "IMSocketManager.h"
#import "IMProtocol.h"
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
@end

@implementation IMSocketManager {
    dispatch_queue_t _queue;          ///< 串行队列：所有内部状态仅在此队列变更
    NSURLSession *_session;
    NSURLSessionWebSocketTask *_task;
    NSString *_host;
    int64_t   _seq;                   ///< 客户端单调自增请求号
    BOOL      _manualClose;           ///< 用户主动断开，禁止自动重连
    NSInteger _reconnectAttempts;
    dispatch_source_t _pingTimer;
    NSMutableDictionary<NSString *, IMPendingSend *> *_pending;
    NSMutableDictionary<NSString *, NSNumber *> *_syncedSeq; // conv_id -> 已同步到的最大 conv_seq
    NSMutableSet<NSString *> *_trackedConvs;                 // 需在重连后增量同步的会话
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
        _state = IMSocketStateDisconnected;
    }
    return self;
}

#pragma mark - 连接生命周期

- (void)connectToHost:(NSString *)host userID:(NSString *)userID {
    if (host.length == 0 || userID.length == 0) {
        IMLog(@"connect 参数为空，忽略");
        return;
    }
    dispatch_async(_queue, ^{
        // 幂等：已连到同一 host+uid 且未主动断开 → 复用现连接（避免会话列表/聊天页重复调用造成重连抖动）。
        if (self.state == IMSocketStateConnected && !self->_manualClose
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

- (void)disconnect {
    dispatch_async(_queue, ^{
        self->_manualClose = YES;
        [self teardownSocket];
        [self updateState:IMSocketStateDisconnected];
    });
}

/// 建立一条新连接（仅在 _queue 调用）：先经 HTTP 登录换取 JWT，再用 ?token= 连 ws。
- (void)openSocket {
    [self teardownSocket];
    [self updateState:IMSocketStateConnecting];
    NSString *host = _host;
    NSString *uid = self.userID;
    __weak typeof(self) weakSelf = self;
    [self fetchTokenForHost:host userID:uid completion:^(NSString *token, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        dispatch_async(self->_queue, ^{
            if (self->_manualClose) { return; }
            if (token.length == 0) {
                IMLog(@"登录换取 token 失败，稍后重连: %@", error.localizedDescription);
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
        IMLog(@"非法 ws 地址 host=%@", host);
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
    IMLog(@"connecting ws://%@/ws (token)", host);
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
    IMLog(@"disconnected: %@", error.localizedDescription ?: @"(closed)");
    [self teardownSocket];
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
    IMLog(@"reconnect in %.1fs (attempt %ld)", delay, (long)_reconnectAttempts);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), _queue, ^{
        if (self->_manualClose) { return; }
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
        IMLog(@"丢弃非法信封: %@ (%@)", text, err.localizedDescription);
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
    } else if ([type isEqualToString:kIMTypePong]) {
        // 心跳回应，无需处理
    } else if ([type isEqualToString:kIMTypeError]) {
        // 带 client_msg_id 的 error = 对某条 send_msg 的拒绝（如被拉黑）→ 立刻判该条发送失败。
        NSString *cmid = [payload[@"client_msg_id"] isKindOfClass:[NSString class]] ? payload[@"client_msg_id"] : nil;
        if (cmid.length > 0) {
            [self handleSendRejected:cmid code:[payload[@"code"] integerValue] message:payload[@"message"]];
        } else {
            IMLog(@"服务端 error: %@", payload);
        }
    } else {
        IMLog(@"未处理类型: %@", type);
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
    NSString *convID = IMConversationID(self.userID ?: @"", toUserID);
    return [self sendText:text toUser:toUserID convID:convID completion:completion];
}

- (NSString *)sendText:(NSString *)text toConv:(NSString *)convID completion:(IMSendCompletion)completion {
    // 群聊：to 留空，服务端按 conv_id 查群成员写扩散（PROTOCOL §6.6）。
    return [self sendText:text toUser:@"" convID:convID completion:completion];
}

/// 共用发送路径：构造 send_msg 负载并入队（ack 超时重发等由 enqueue 统一处理）。
- (NSString *)sendText:(NSString *)text toUser:(NSString *)toUserID convID:(NSString *)convID completion:(IMSendCompletion)completion {
    NSString *clientMsgID = [NSUUID UUID].UUIDString;
    NSDictionary *payload = @{
        @"client_msg_id": clientMsgID,
        @"conv_id":       convID ?: @"",
        @"to":            toUserID ?: @"",
        @"content_type":  @"text",
        @"content":       text ?: @"",
    };
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
        IMLog(@"ack 超时，重发 %@ (第 %ld 次)", p.clientMsgID, (long)p.retries);
        [self writeData:p.payload];
        [self armAckTimer:p];
    } else {
        [_pending removeObjectForKey:p.clientMsgID];
        IMLog(@"ack 重发耗尽，判失败 %@", p.clientMsgID);
        [self finishSend:p.completion success:NO error:[self errorWithCode:5002 msg:@"ack 超时"] convSeq:0];
    }
}

- (void)cancelAckTimer:(IMPendingSend *)p {
    if (p.ackTimer) {
        dispatch_source_cancel(p.ackTimer);
        p.ackTimer = nil;
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
    [self updateSyncedSeqForConv:data[@"conv_id"] seq:convSeq]; // 自己发的消息也推进同步位点
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
        NSArray *messages = [conv[@"messages"] isKindOfClass:[NSArray class]] ? conv[@"messages"] : @[];
        for (NSDictionary *md in messages) {
            if (![md isKindOfClass:[NSDictionary class]]) { continue; }
            [self processIncomingMessage:[IMMessageModel receivedMessageWithNewMsgData:md]];
        }
        if ([conv[@"has_more"] boolValue] && convID.length > 0) {
            [self sendSyncReqForConvs:@[convID]]; // 以更新后的位点继续翻页
        }
    }
}

/// 统一处理收到的一条消息：推进同步位点、回执、投递 delegate（仅在 _queue 调用）。
- (void)processIncomingMessage:(IMMessageModel *)msg {
    // 空洞自愈：conv_seq 由服务端连续分配，若收到的序号跳过了已同步位点之后的中间段，
    // 说明中间有未拉取（离线）消息 → 先从已同步位点补拉，避免实时消息把 synced 推过空洞造成漏消息。
    int64_t prevSynced = [self syncedSeqForConv:msg.convID];
    if (prevSynced > 0 && msg.convSeq > prevSynced + 1 && [_trackedConvs containsObject:msg.convID]) {
        [self sendSyncReqForConvs:@[msg.convID]]; // 用当前（更低的）位点作 since，把缺口拉回
    }
    [self updateSyncedSeqForConv:msg.convID seq:msg.convSeq];
    [self sendReceiptForConv:msg.convID upTo:msg.convSeq];
    // 落库放在网络层：无论当前在会话列表还是聊天页（甚至无页面）收到的消息都持久化，
    // 避免「在列表收到、未入库、之后开聊天页因 synced 已前进而漏拉」。按 conv_seq 幂等 upsert。
    [IMDatabase.sharedDatabase saveMessage:msg];
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

/// 处理对端已读回执（仅在 _queue 调用）：只关心 read，投递 delegate。
- (void)handleReceipt:(NSDictionary *)data {
    if (![data[@"status"] isEqual:@"read"]) { return; } // delivered 单勾本端暂不显示
    NSString *convID = [data[@"conv_id"] isKindOfClass:[NSString class]] ? data[@"conv_id"] : nil;
    NSString *from = [data[@"from"] isKindOfClass:[NSString class]] ? data[@"from"] : @"";
    int64_t upTo = [data[@"up_to_conv_seq"] longLongValue];
    if (convID.length == 0) { return; }
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

/// 处理在线状态广播（仅在 _queue 调用）。
- (void)handlePresence:(NSDictionary *)data {
    NSString *user = [data[@"user"] isKindOfClass:[NSString class]] ? data[@"user"] : nil;
    BOOL online = [data[@"status"] isEqual:@"online"];
    if (user.length == 0) { return; }
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        id<IMSocketManagerDelegate> d = self.delegate;
        if ([d respondsToSelector:@selector(socketManager:didChangePresenceForUser:online:)]) {
            [d socketManager:self didChangePresenceForUser:user online:online];
        }
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
    for (NSString *convID in convIDs) {
        [cursors addObject:@{ @"conv_id": convID, @"since_conv_seq": @([self syncedSeqForConv:convID]) }];
    }
    if (cursors.count == 0) { return; }
    [self sendEnvelopeType:kIMTypeSyncReq data:@{ @"cursors": cursors } completion:nil];
}

/// （重）连成功后对所有已登记会话发起增量同步（仅在 _queue 调用）。
- (void)syncTrackedConversations {
    [self sendSyncReqForConvs:_trackedConvs.allObjects];
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
    if (!json) { IMLog(@"信封序列化失败: %@", err.localizedDescription); }
    return json;
}

/// 写出一帧；未连接或写失败时记录（重发/重连机制兜底）。
- (void)writeData:(NSData *)data {
    NSURLSessionWebSocketTask *task = _task;
    if (!task || self.state != IMSocketStateConnected) {
        IMLog(@"未连接，暂不发送（待重连后由超时重发兜底）");
        return;
    }
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSURLSessionWebSocketMessage *msg = [[NSURLSessionWebSocketMessage alloc] initWithString:text];
    [task sendMessage:msg completionHandler:^(NSError *error) {
        if (error) { IMLog(@"发送失败: %@", error.localizedDescription); }
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
        IMLog(@"connected as uid=%@", self.userID);
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
