//  IMConversation.h
//  会话列表项，对应后端 conversation.Summary（GET /api/v1/conversations）。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMConversation : NSObject

@property (nonatomic, copy) NSString *convID;
@property (nonatomic, assign) BOOL isGroup;            // YES=群聊（用 name/avatarURL/memberCount），NO=单聊（用 peer*）
@property (nonatomic, copy, nullable) NSString *name;         // 群名（仅群聊）
@property (nonatomic, copy, nullable) NSString *avatarURL;    // 群头像（仅群聊，空回退群名首字母圈）
@property (nonatomic, assign) NSInteger memberCount;   // 群成员数（仅群聊）
@property (nonatomic, copy) NSString *peer;            // 单聊对端 uid（群聊为空）
@property (nonatomic, copy, nullable) NSString *peerNickname;  // 对端昵称（显示名/首字母，空回退 uid）
@property (nonatomic, copy, nullable) NSString *peerAvatarURL; // 对端头像（data:/http，空回退首字母圈）
@property (nonatomic, copy, nullable) NSString *lastContent;
@property (nonatomic, copy, nullable) NSString *lastFrom;
@property (nonatomic, copy, nullable) NSString *lastFromNickname; // 最后发送者昵称（仅群聊：列表预览"昵称: 内容"）
@property (nonatomic, assign) int64_t latestConvSeq;
@property (nonatomic, assign) int64_t readSeq;         // 本人已读位点（首条未读 = conv_seq > readSeq）
@property (nonatomic, assign) int64_t peerReadSeq;     // 单聊对端已读位点（判断"我发的最后一条"是否已读；群聊 0）
@property (nonatomic, assign) int64_t timestamp;       // 最后一条时间（毫秒）
@property (nonatomic, assign) NSInteger unread;        // 未读数（服务端 cap 999）

/// 从 data.conversations 数组解析（脏数据安全）。
+ (NSArray<IMConversation *> *)conversationsFromArray:(nullable NSArray *)array;

@end

NS_ASSUME_NONNULL_END
