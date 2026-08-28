//  IMUserCard.h
//  通讯录用户项：既承载找人结果（profile.Card：含 tags），也承载好友/申请项（friend.Entry：含 status）。
//  对应后端 GET /api/v1/users/search 的 data.users 与 GET /api/v1/friends 的 data.friends。

#import <Foundation/Foundation.h>
#import "IMPresence.h"

NS_ASSUME_NONNULL_BEGIN

/// 我与该用户的关系（对齐后端 store.Friend* 状态字符串）。
typedef NS_ENUM(NSInteger, IMFriendStatus) {
    IMFriendStatusNone = 0,   // 无关系（搜索结果默认）
    IMFriendStatusRequested,  // 我已申请、待对方同意
    IMFriendStatusPending,    // 对方申请我、待我同意
    IMFriendStatusAccepted,   // 已是好友
    IMFriendStatusBlocked,    // 我已拉黑
};

/// status 字符串 ↔ 枚举互转（脏数据安全）。
IMFriendStatus IMFriendStatusFromString(NSString *_Nullable s);

@interface IMUserCard : NSObject

@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy) NSString *nickname;
/// 我给他起的备注名（仅自己可见，显示优先级高于 nickname）。好友列表 / 资料卡下发；找人结果为空。
@property (nonatomic, copy, nullable) NSString *remark;
@property (nonatomic, copy) NSString *avatarURL;
@property (nonatomic, copy) NSString *phone;               // 仅本人资料(GET /users/me)有；他人/搜索结果为空
@property (nonatomic, strong) NSArray<NSString *> *tags;   // 找人结果/本人资料有；好友项为空
@property (nonatomic, assign) IMFriendStatus status;       // 仅好友/申请列表有意义；找人结果为 None
@property (nonatomic, assign) BOOL blocked;                // 我是否拉黑了对方（与 status 正交）；拉黑的好友 status 仍 accepted
@property (nonatomic, assign) int64_t updatedAt;           // 好友关系更新时间（毫秒）；找人结果 0
@property (nonatomic, strong) IMPresence *presence;        // 在线态快照；仅 GET /users/{id} 与 /users/me 有，找人/好友列表为空态

/// 展示名：备注名 > 昵称 > uid（全端统一口径）。备注取 IMRemarkStore 实时值，不读本对象的
/// remark 快照——后者只负责把服务端值喂进 store，见 IMRemarkStore.h。
@property (nonatomic, readonly) NSString *displayName;

/// 从 data.users / data.friends 数组解析（脏数据安全）。
+ (NSArray<IMUserCard *> *)cardsFromArray:(nullable NSArray *)array;

@end

NS_ASSUME_NONNULL_END
