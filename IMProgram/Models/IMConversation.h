//  IMConversation.h
//  会话列表项，对应后端 conversation.Summary（GET /api/v1/conversations）。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMConversation : NSObject

@property (nonatomic, copy) NSString *convID;
@property (nonatomic, copy) NSString *peer;            // 单聊对端 uid
@property (nonatomic, copy, nullable) NSString *lastContent;
@property (nonatomic, copy, nullable) NSString *lastFrom;
@property (nonatomic, assign) int64_t latestConvSeq;
@property (nonatomic, assign) int64_t readSeq;         // 本人已读位点（首条未读 = conv_seq > readSeq）
@property (nonatomic, assign) int64_t peerReadSeq;     // 单聊对端已读位点（判断"我发的最后一条"是否已读；群聊 0）
@property (nonatomic, assign) int64_t timestamp;       // 最后一条时间（毫秒）
@property (nonatomic, assign) NSInteger unread;        // 未读数（服务端 cap 999）

/// 从 data.conversations 数组解析（脏数据安全）。
+ (NSArray<IMConversation *> *)conversationsFromArray:(nullable NSArray *)array;

@end

NS_ASSUME_NONNULL_END
