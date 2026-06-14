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
@property (nonatomic, assign) int64_t timestamp;       // 最后一条时间（毫秒）
@property (nonatomic, assign) NSInteger unread;        // M2 前恒为 0

/// 从 data.conversations 数组解析（脏数据安全）。
+ (NSArray<IMConversation *> *)conversationsFromArray:(nullable NSArray *)array;

@end

NS_ASSUME_NONNULL_END
