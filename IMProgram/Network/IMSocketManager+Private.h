#import "IMSocketManager.h"
#import "IMBacklogTracker.h"
#import "IMDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@class IMPendingSend;

/// IMSocketManager 的**共享类扩展**：把内部状态与内部方法暴露给同类的分文件 category
/// （CODING_STYLE §7 ②：一组内聚方法 → 分文件 category）。
///
/// 拆分的直接原因是体量红线，但选择**沿"离线补拉"这条线**切，是照着服务端的同一刀
/// （IMServer 把 sync.go 从 hub.go 拆出）：实时投递与离线补拉互为补充但机制完全不同，
/// 尤其超级群下在线只推轻量信号、正文全靠补拉，这条链的独立性只增不减。
///
/// **线程约定**：除非另有说明，下列状态与方法**只在 `queue` 上访问**。
@interface IMSocketManager () <NSURLSessionWebSocketDelegate> {
@protected

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
    IMBacklogTracker *_backlog;       ///< 离线积压的连接级簿记（超级群/head/缺口/回执合批），见其头注释
    NSMutableSet<NSString *> *_syncingConvs;                 // 已发出 sync_req、等待该会话响应，避免实时连发造成请求风暴
    NSMutableDictionary<NSString *, NSNumber *> *_syncStalledUntil; // conv_id -> 该时刻(CFAbsoluteTime)前不再发 sync_req：
                                                             // 整页处理完位点没动（落库持续失败/页内空洞）时热重试只会烧 CPU
    NSMutableSet<NSString *> *_pendingOps;                   // 已发出、待确认的消息操作 client_msg_id（撤回/编辑/置顶），供失败回滚
    NSArray<NSString *> *_watchedUsers;                      // 在线态关注全集：连接级易失态，重连成功后由本类自动重发（PROTOCOL §5.5）
}

@property (nonatomic, assign) IMSocketState state;
@property (nonatomic, copy, nullable)   NSString *userID;

- (void)cancelAllPendingSendsWithMessage:(NSString *)message;
- (BOOL)applyMsgOpPayload:(NSDictionary *)payload advancingSyncedConvSeq:(int64_t)syncedConvSeq;
- (BOOL)performDatabaseOperation:(void (^)(IMDatabase *database))operation;

/// 下面这些由主实现提供、被 +Sync category 复用（仅在 queue 调用）。
- (int64_t)syncedSeqForConv:(NSString *)convID;
- (void)updateSyncedSeqForConv:(NSString *)convID seq:(int64_t)seq;
- (BOOL)processIncomingMessage:(IMMessageModel *)msg fromSync:(BOOL)fromSync syncAdvanceSeq:(int64_t)syncAdvanceSeq;
- (void)sendSyncReqForConvs:(NSArray<NSString *> *)convIDs;

/// 排队一个 delivered 回执（同会话取最大位点，短窗口合批发一帧）。由主实现提供。
- (void)sendReceiptForConv:(NSString *)convID upTo:(int64_t)convSeq;
- (void)sendEnvelopeType:(NSString *)type data:(nullable NSDictionary *)data completion:(nullable IMSendCompletion)completion;

@end

/// +Sync category **自己**提供的方法，主实现在收帧分发处调用（仅在 queue 调用）。
///
/// 必须声明在这里、不能混进上面的类扩展：类扩展属于**主类**，把 category 的实现方法
/// 声明进去，编译器会判定"category 实现了一个主类也会实现的方法"（-Wobjc-protocol-method-implementation），
/// 而这种重复实现在运行期谁生效是未定义的——今天靠链接顺序碰巧对，明天加个文件就换人。
@interface IMSocketManager (Sync)
- (void)handleSyncResp:(NSDictionary *)data;
@end

NS_ASSUME_NONNULL_END
