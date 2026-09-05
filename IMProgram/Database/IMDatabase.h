//  IMDatabase.h
//  客户端本地消息落库：App 重启秒显历史、按已存最大 conv_seq 断点续传。
//  实现：FMDB + SQLite（FMDatabaseQueue 线程安全）。需经 CocoaPods 引入 FMDB，用 .xcworkspace 打开。

#import <Foundation/Foundation.h>

@class IMConversation;
@class IMDatabaseAccountContext;
@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

/// 不透明账号上下文：绑定 owner_uid 与一次账号激活代次。
/// A→B→A 后第一代 A 上下文仍会失效，不能仅靠 uid 判断迟到异步回调是否合法。
@interface IMDatabaseAccountContext : NSObject
@property (nonatomic, copy, readonly) NSString *ownerUserID;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface IMDatabase : NSObject

/// 默认库（Documents/im.sqlite）。
+ (instancetype)sharedDatabase;

/// 指定文件（供测试用临时路径）。
- (instancetype)initWithFileURL:(NSURL *)fileURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// 选择当前账号的数据命名空间。App 进入主界面前必须调用；同一 SQLite 文件内按 owner_uid 强制隔离。
/// 每次调用都代表一次新账号激活并推进代次（即使 uid 相同），使上一登录周期上下文失效。
/// 子页面只应捕获 currentAccountContext，不应重复激活。空 uid 返回 nil 且不切换。
- (nullable IMDatabaseAccountContext *)useOwnerUserID:(NSString *)userID;

/// 当前账号上下文；尚未选择真实账号时返回 nil。异步任务应在发起时捕获该对象。
- (nullable IMDatabaseAccountContext *)currentAccountContext;

/// 仅当 context 仍是当前账号的同一激活代次时同步执行 block。
/// 校验与执行相对账号切换原子化；返回 NO 表示迟到/跨库 context，block 不会执行。
- (BOOL)performWithAccountContext:(IMDatabaseAccountContext *)context
                            block:(void (^)(IMDatabase *database))block;

/// 当前账号的本地会话快照（服务不可用时用于离线首屏）。
- (NSArray<IMConversation *> *)cachedConversations;

/// 当前账号已发送文件的本地缓存（按时间倒序）；用于文件面板离线首屏。
- (NSArray<NSDictionary *> *)cachedSentFiles;

/// 合并服务端分页结果（按 server_msg_id 去重），与其他账号严格隔离。
- (void)cacheSentFiles:(NSArray<NSDictionary *> *)files;

/// 原子替换当前账号的完整会话快照。空数组表示服务端权威列表为空。
- (void)replaceCachedConversations:(NSArray<IMConversation *> *)conversations;

// 好友 / 群组名册的本地快照（cachedFriends / cachedGroups 等四个方法）已移到
// IMDatabase+RosterCache.h —— 用它们的文件请 import 那个头。

/// 保存/更新一条消息：出站按 clientMsgID upsert（sending→sent 覆盖），入站按 conv_seq 去重。
/// 同一事务内同步会话最后一条、未读数和排序；新会话会建立可离线打开的最小摘要。
- (void)saveMessage:(IMMessageModel *)message;

/// 把乐观发送时的临时 client_msg_id 就地换成真实 ID。
/// 消息行是按 client_msg_id 认的：不改键直接以新 ID 保存会**插出重复行**，
/// 留下一条永远失败的孤儿气泡（临时键那条）。
- (void)replaceClientMsgID:(NSString *)oldClientMsgID
           withClientMsgID:(NSString *)newClientMsgID
                    inConv:(NSString *)convID;
/// 接收/补拉路径：消息、会话摘要与连续同步位置在同一事务提交。返回 NO 时调用方不得推进内存游标。
- (BOOL)saveIncomingMessage:(IMMessageModel *)message advancingSyncedConvSeq:(int64_t)syncedConvSeq;

/// 单调推进本地会话已读位点，并按缓存中的消息重新计算未读数。
- (void)markConversation:(NSString *)convID readUpToConvSeq:(int64_t)convSeq;

/// 用户在会话列表显式选择“设为已读”时，清零摘要未读并推进到指定位置。
- (void)markConversationFullyRead:(NSString *)convID upToConvSeq:(int64_t)convSeq;

/// 持久化对端已读位点（单聊列表的已读双勾）。
- (void)markConversation:(NSString *)convID peerReadUpToConvSeq:(int64_t)convSeq;

/// 应用服务端 conv_update 的完整会话设置；会话不存在时等待下一次权威列表补齐。
- (void)applyCachedSettingsForConversation:(NSString *)convID
                                  pinnedAt:(int64_t)pinnedAt
                                     muted:(BOOL)muted
                              markedUnread:(BOOL)markedUnread;

/// 单独把会话备注（G1，仅本人可见）写进本地缓存；与三开关解耦。
- (void)applyCachedRemarkForConversation:(NSString *)convID remark:(nullable NSString *)remark;

/// 把好友备注名（仅本人可见）写进本地缓存：同时更新该好友的单聊会话行与好友快照行，
/// 使冷启动首屏（本地快路）直接显备注、不闪真实昵称。remark 传 nil/空串=清除。
- (void)applyCachedRemark:(nullable NSString *)remark forPeer:(NSString *)peerID;

/// 删除当前账号的一条本地会话摘要（消息记录仍按服务端“仅清会话”语义保留）。
- (void)deleteCachedConversation:(NSString *)convID;

/// 取某会话的全部消息（按存入顺序，约等于时间顺序）。
///
/// ⚠️ **聊天页不再用它**（改走下面的窗口查询，见 MESSAGE_WINDOW_DESIGN §1.1）：一次读全部在
/// 聊了很久的会话里会把几十万行全构造成对象。仍留给「一次就要全量」的调用方（会话详情页按类型
/// 归档媒体/文件/链接、单测）。新代码要分页请用窗口查询，别再往这里加调用点。
- (NSArray<IMMessageModel *> *)messagesForConv:(NSString *)convID;

#pragma mark - 消息窗口（分页与定位的本地一半，见 IMServer/docs/design/MESSAGE_WINDOW_DESIGN.md §4）

/// 一窗默认条数（与服务端 window_req 单侧上限、im-web 的 RENDER_WINDOW_STEP 同量级）。
FOUNDATION_EXPORT const NSInteger kIMMessageWindowPageSize;

/// 取会话**最新一窗**：最后 limit 条（升序）。**含待发/失败消息**（conv_seq==0，排序上恒在末尾）。
- (NSArray<IMMessageModel *> *)latestMessagesForConv:(NSString *)convID limit:(NSInteger)limit;

/// 取 conv_seq < beforeConvSeq 的**最后** limit 条（升序）。向上翻页用；不含待发消息。
/// 返回**升序**——与 latest/around 三者返回序一致。这三个返回序若不一致，拼窗口时极易静默把顺序弄反。
- (NSArray<IMMessageModel *> *)messagesForConv:(NSString *)convID
                                 beforeConvSeq:(int64_t)beforeConvSeq
                                         limit:(NSInteger)limit;

/// 以 anchorConvSeq 开一窗（升序）：conv_seq ≤ anchor 的**最后** before 条 + conv_seq > anchor 的**最前** after 条。
///
/// anchor 是**位点不是行**——这是刻意的：进会话要用「已读位点」开窗，而那个值未必对应任何一行
/// （它可能指向一条已删除、或对我不可见的消息）。跳转到第 X 条时传 anchor=X，X 自己落在 before 段末尾。
- (NSArray<IMMessageModel *> *)messagesForConv:(NSString *)convID
                                 aroundConvSeq:(int64_t)anchorConvSeq
                                        before:(NSInteger)before
                                         after:(NSInteger)after;

/// 取本地这一条（不存在返回 nil）。分页后内存里只有当前一窗，"这条是不是已撤回"之类的判定
/// 不能再靠遍历内存数组——目标多半根本不在窗口里。
- (nullable IMMessageModel *)messageInConv:(NSString *)convID convSeq:(int64_t)convSeq;

/// 按 client_msg_id 取本会话的发件行（不存在返回 nil）。
/// 发送结果回来时目标可能已不在当前窗口（发完立刻跳去看历史），那时只能从库里取出来改状态，
/// 否则那条会永远停在「发送中」——分页之前内存里有全部消息，不会出现这种情况。
- (nullable IMMessageModel *)messageInConv:(NSString *)convID clientMsgID:(NSString *)clientMsgID;

/// 本会话的图片/视频消息（升序，排除撤回与空内容）。
/// 媒体查看器左右翻页、会话媒体库共用：它们的语义是「整个会话的媒体时间线」，不是「当前窗口里的」。
- (NSArray<IMMessageModel *> *)mediaMessagesForConv:(NSString *)convID;

#pragma mark - 会话内搜索 / 日历 / 发件人候选（都必须查库，不能扫内存窗口）
// 分页之前这三件事都是遍历 `messages` 内存数组算出来的——那时它就是"本会话全部消息"。
// 分页之后内存里只剩一窗，再扫内存会让「会话内搜索」悄悄变成「只搜看得见的这 200 条」、
// 日历只点亮这一窗覆盖的几天、「来自」只列出最近发过言的人。**静默降级最难发现**，故一律改查库。

/// 会话内搜索命中的 conv_seq（**升序**，排除撤回）。
/// keyword 为空且 fromUID 非空=只按发件人过滤；两者都空返回空。
/// 命中口径与全局搜索一致：text 的 content / 任意消息的 caption / 文件名。
- (NSArray<NSNumber *> *)searchConvSeqsInConv:(NSString *)convID
                                      keyword:(nullable NSString *)keyword
                                      fromUID:(nullable NSString *)fromUID
                                        limit:(NSInteger)limit;

/// 本会话中 timestamp ≥ ms 的第一条（按显示序）的 conv_seq；没有返回 0。排除撤回。
/// ms 传 0 即「最早一条」——日历的"跳到最早"与"跳到某天"共用这一个查询。
- (int64_t)firstConvSeqInConv:(NSString *)convID atOrAfterTimestamp:(int64_t)ms;

/// 本会话有消息的**本地日**（每天 0 点的 epoch 毫秒，升序）。日历打点用。
/// utcOffsetMs 传当前时区偏移：SQLite 里没有可靠的本地时区，故把偏移当常量下推做整除分桶。
/// ⚠️ 代价：跨夏令时的历史消息，若落在午夜前后一小时内可能算进相邻那天。日历打点可接受。
- (NSArray<NSNumber *> *)activeLocalDayStartsInConv:(NSString *)convID utcOffsetMs:(int64_t)utcOffsetMs;

/// 本会话每个发件人的一条代表消息（各取其**最新**一条，按时间倒序）。
/// 「来自」候选面板用：要拿发件人 uid，也要拿那条消息上的昵称/头像来显示。
- (NSArray<IMMessageModel *> *)distinctSenderSamplesInConv:(NSString *)convID limit:(NSInteger)limit;


/// 本地全文搜索（搜索功能 P0，纯本地）。convID 传 nil = 跨全部会话（首页全局搜索）；否则限该会话（会话内搜索）。
/// 命中口径同后端 G4：text 消息 content 或任意消息 caption 子串（大小写不敏感）；排除撤回。
/// 按 timestamp 倒序（新在前），limit<=0 用默认上限。
- (NSArray<IMMessageModel *> *)searchMessagesMatching:(NSString *)keyword
                                               inConv:(nullable NSString *)convID
                                                limit:(NSInteger)limit;

/// 本地删除一条消息（出站按 client_msg_id 匹配，入站按 conv_seq 匹配）。仅本端，不影响对端。
- (void)deleteMessage:(IMMessageModel *)message;

/// 本地清空某会话的全部消息（仅本端，不影响对端；对应详情页「清空聊天记录」）。返回删除条数。
- (NSInteger)clearMessagesForConv:(NSString *)convID;

/// 该会话已存消息的最大 conv_seq（仅供本地数据查询，不能作为连续同步游标）。
- (int64_t)maxConvSeqForConv:(NSString *)convID;

/// 服务端历史已经连续同步完成的位置。与“本地最大消息序号”分离，避免有 7、8、9 时误认为 1～6 也已同步。
- (int64_t)syncedConvSeqForConv:(NSString *)convID;

/// 单调推进当前账号该会话的连续同步位置；普通接收路径优先用消息+游标原子接口。
- (void)advanceSyncedConvSeqForConv:(NSString *)convID toConvSeq:(int64_t)convSeq;

/// 把一次消息操作（撤回/编辑/置顶，M4）就地应用到已落库消息（按 conv_seq 定位）。目标不存在则忽略。
/// recalledAt/editedAt 传 0 表示不改该项；**pinnedAt >0=置顶 / <0=取消置顶（写回 0）/ 0=不改**；
/// newContent 非 nil 时改 content（编辑）。
- (void)applyMsgOpForConv:(NSString *)convID
            targetConvSeq:(int64_t)targetConvSeq
               recalledAt:(int64_t)recalledAt
               recalledBy:(nullable NSString *)recalledBy
                 editedAt:(int64_t)editedAt
                 pinnedAt:(int64_t)pinnedAt
               newContent:(nullable NSString *)newContent;
/// sync 中的操作事件：操作派生状态与事件连续位置同事务提交；失败时调用方不得推进内存游标。
- (BOOL)applyMsgOpForConv:(NSString *)convID
            targetConvSeq:(int64_t)targetConvSeq
               recalledAt:(int64_t)recalledAt
               recalledBy:(nullable NSString *)recalledBy
                 editedAt:(int64_t)editedAt
                 pinnedAt:(int64_t)pinnedAt
               newContent:(nullable NSString *)newContent
    advancingSyncedConvSeq:(int64_t)syncedConvSeq;

/// 任务2：物理删除某会话内 conv_seq 定位的一条消息（为所有人删除 / 仅为我删除共用），
/// 并可选原子推进连续同步位置（syncedConvSeq>0 时），避免同一批 sync 重新拉回。返回是否删到行。
- (BOOL)deleteLocalMessageForConv:(NSString *)convID
                          convSeq:(int64_t)convSeq
           advancingSyncedConvSeq:(int64_t)syncedConvSeq;

/// 任务2：当前账号全局未读总数（各会话 unread 之和；exclude 非空时排除该会话）。用于聊天页返回按钮徽标。
- (NSInteger)totalUnreadExcludingConv:(nullable NSString *)excludeConvID;

@end

NS_ASSUME_NONNULL_END
