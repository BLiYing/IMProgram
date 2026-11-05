//  IMShareTargetDirectory.h
//  分享选择页的「好友 + 我的群」名录：一次拉取、三页共用（主页搜索 / 好友子页 / 群聊子页）。
//  好友 = GET /friends?status=accepted 里可分享的（IMShareSelection isShareableFriend:）；
//  群 = GET /groups（我加入的群，**包括会话已被删掉的群**——这正是只列会话时漏掉的那批）。
//  两路都回来（成败皆可）才回调；同一时刻多处等待只发一次请求。

#import <Foundation/Foundation.h>

@class IMConversation;
@class IMUserCard;

NS_ASSUME_NONNULL_BEGIN

@interface IMShareTargetDirectory : NSObject

/// excludedUserIDs：不列入好友名录的 uid（分享某人名片时排除他本人）；
/// excludedConvIDs：不列入的会话（分享群邀请时排除该群本身）。
- (instancetype)initWithToken:(NSString *)token selfUID:(NSString *)selfUID
              excludedUserIDs:(nullable NSSet<NSString *> *)excludedUserIDs
              excludedConvIDs:(nullable NSSet<NSString *> *)excludedConvIDs NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly) BOOL loaded;
/// 请求在途（此时再调 loadIfNeeded: 只会排队等同一次结果）。
@property (nonatomic, readonly) BOOL loading;
/// 任一路失败（加载完成后才有意义）。
@property (nonatomic, readonly) BOOL friendsFailed;
@property (nonatomic, readonly) BOOL groupsFailed;
/// 可分享的好友卡片（好友子页做 A–Z 分组用）。
@property (nonatomic, readonly) NSArray<IMUserCard *> *friendCards;
@property (nonatomic, readonly) NSArray<IMConversation *> *groupTargets;

/// 已加载过直接（同步）回调；否则发请求，completion 在主线程。
- (void)loadIfNeeded:(void (^)(void))completion;
/// 卡片 → 会话目标（查缓存，查不到现合成）。
- (nullable IMConversation *)targetForFriend:(IMUserCard *)card;

@end

NS_ASSUME_NONNULL_END
