//  IMDatabase.h
//  客户端本地消息落库：App 重启秒显历史、按已存最大 conv_seq 断点续传。
//  实现：FMDB + SQLite（FMDatabaseQueue 线程安全）。需经 CocoaPods 引入 FMDB，用 .xcworkspace 打开。

#import <Foundation/Foundation.h>

@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

@interface IMDatabase : NSObject

/// 默认库（Documents/im_store.archive）。
+ (instancetype)sharedDatabase;

/// 指定文件（供测试用临时路径）。
- (instancetype)initWithFileURL:(NSURL *)fileURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// 保存/更新一条消息：出站按 clientMsgID upsert（sending→sent 覆盖），入站按 conv_seq 去重。
- (void)saveMessage:(IMMessageModel *)message;

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
