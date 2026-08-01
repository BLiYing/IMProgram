//  IMDatabase.h
//  客户端本地消息落库：App 重启秒显历史、按已存最大 conv_seq 断点续传。
//  实现：FMDB + SQLite（FMDatabaseQueue 线程安全）。需经 CocoaPods 引入 FMDB，用 .xcworkspace 打开。

#import <Foundation/Foundation.h>

@class IMConversation;
@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

@interface IMDatabase : NSObject

/// 默认库（Documents/im.sqlite）。
+ (instancetype)sharedDatabase;

/// 指定文件（供测试用临时路径）。
- (instancetype)initWithFileURL:(NSURL *)fileURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// 选择当前账号的数据命名空间。App 进入主界面前必须调用；同一 SQLite 文件内按 owner_uid 强制隔离。
- (void)useOwnerUserID:(NSString *)userID;

/// 当前账号的本地会话快照（服务不可用时用于离线首屏）。
- (NSArray<IMConversation *> *)cachedConversations;

/// 当前账号已发送文件的本地缓存（按时间倒序）；用于文件面板离线首屏。
- (NSArray<NSDictionary *> *)cachedSentFiles;

/// 合并服务端分页结果（按 server_msg_id 去重），与其他账号严格隔离。
- (void)cacheSentFiles:(NSArray<NSDictionary *> *)files;

/// 原子替换当前账号的完整会话快照。空数组表示服务端权威列表为空。
- (void)replaceCachedConversations:(NSArray<IMConversation *> *)conversations;

/// 保存/更新一条消息：出站按 clientMsgID upsert（sending→sent 覆盖），入站按 conv_seq 去重。
/// 同一事务内同步会话最后一条、未读数和排序；新会话会建立可离线打开的最小摘要。
- (void)saveMessage:(IMMessageModel *)message;

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

/// 删除当前账号的一条本地会话摘要（消息记录仍按服务端“仅清会话”语义保留）。
- (void)deleteCachedConversation:(NSString *)convID;

/// 取某会话的全部消息（按存入顺序，约等于时间顺序）。
- (NSArray<IMMessageModel *> *)messagesForConv:(NSString *)convID;

/// 本地删除一条消息（出站按 client_msg_id 匹配，入站按 conv_seq 匹配）。仅本端，不影响对端。
- (void)deleteMessage:(IMMessageModel *)message;

/// 本地清空某会话的全部消息（仅本端，不影响对端；对应详情页「清空聊天记录」）。返回删除条数。
- (NSInteger)clearMessagesForConv:(NSString *)convID;

/// 该会话已存消息的最大 conv_seq（派生的同步位点，0 表示无）。
- (int64_t)maxConvSeqForConv:(NSString *)convID;

/// 把一次消息操作（撤回/编辑/置顶，M4）就地应用到已落库消息（按 conv_seq 定位）。目标不存在则忽略。
/// recalledAt/editedAt/pinnedAt 传 0 表示不改该项；newContent 非 nil 时改 content（编辑）。
- (void)applyMsgOpForConv:(NSString *)convID
            targetConvSeq:(int64_t)targetConvSeq
               recalledAt:(int64_t)recalledAt
               recalledBy:(nullable NSString *)recalledBy
                 editedAt:(int64_t)editedAt
                 pinnedAt:(int64_t)pinnedAt
               newContent:(nullable NSString *)newContent;

@end

NS_ASSUME_NONNULL_END
