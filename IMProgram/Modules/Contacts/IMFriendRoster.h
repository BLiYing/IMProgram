//  IMFriendRoster.h
//  好友名单的「拉取 → 拆 pending / accepted → 落本地快照」，通讯录首页与「我的好友」页共用。
//  两页以前各抄一份 login → friendsWithToken → 拆分 → 持久化（2026-11-13 改版时复制出来的），收在这里。

#import <Foundation/Foundation.h>

@class IMUserCard, IMDatabaseAccountContext;

NS_ASSUME_NONNULL_BEGIN

/// 一次权威好友名单，按关系拆好。
@interface IMFriendRoster : NSObject
/// 对方申请我、待我处理（「新的朋友」徽标 / Tab 角标）。
@property (nonatomic, copy, readonly) NSArray<IMUserCard *> *pending;
/// 已是好友（「我的好友」列表 / 好友数；落本地快照的也是它）。
@property (nonatomic, copy, readonly) NSArray<IMUserCard *> *accepted;

/// 从 GET /friends 的全量关系里拆出 pending / accepted；其它状态（requested / blocked …）两边都不进。
+ (instancetype)rosterWithFriends:(NSArray<IMUserCard *> *)friends;
- (instancetype)init NS_UNAVAILABLE;

/// 登录换票 → 拉全量关系 → 拆分 → accepted 交 IMFriendCacheWriter 落库（变了才写）。completion 在主线程：
/// 成功给 roster + token（「我的好友」页左滑操作要用）；登录或拉取失败 roster 为 nil（已打日志，调用方保留当前内容）。
/// source 只用于日志，区分是哪个页面发起的。
+ (void)fetchWithHost:(NSString *)host
               userID:(NSString *)userID
              context:(nullable IMDatabaseAccountContext *)context
               source:(NSString *)source
           completion:(void (^)(IMFriendRoster *_Nullable roster, NSString *_Nullable token))completion;

@end

NS_ASSUME_NONNULL_END
