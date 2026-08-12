//  IMGroupInfo.h
//  群资料 + 成员（M3）。对应后端 group.Info / group.MemberView / group.Summary
//  （POST/GET /api/v1/groups、GET /api/v1/groups/{id}）。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 群成员角色（对齐后端 store.GroupRole*）。
typedef NS_ENUM(NSInteger, IMGroupRole) {
    IMGroupRoleMember = 0, ///< 普通成员
    IMGroupRoleAdmin,      ///< 管理员
    IMGroupRoleOwner,      ///< 群主
};

/// role 字符串 → 枚举（脏数据安全，未知按 member）。
IMGroupRole IMGroupRoleFromString(NSString *_Nullable s);

/// 群内一个成员。
@interface IMGroupMember : NSObject
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy) NSString *nickname;                        ///< 全局昵称
@property (nonatomic, copy, nullable) NSString *groupNickname;         ///< 我在本群的昵称（G1，空=未设置）
@property (nonatomic, copy) NSString *avatarURL;
@property (nonatomic, assign) IMGroupRole role;
@property (nonatomic, assign) int64_t joinedAt;
@property (nonatomic, assign) int64_t muteUntil;                       ///< 成员级禁言到期毫秒（G2；0=未禁言）
/// 展示名：**群昵称优先** → 全局昵称 → uid（G1；与后端 from_nickname 下发口径一致）。
@property (nonatomic, readonly) NSString *displayName;
@end

/// 群资料 + 成员列表。convID 即群 topic_id（g_xxx），与消息层 conv_id 同名同值。
@interface IMGroupInfo : NSObject
@property (nonatomic, copy) NSString *convID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *owner;
@property (nonatomic, copy) NSString *avatarURL;
@property (nonatomic, assign) int64_t createdAt;
@property (nonatomic, assign) IMGroupRole myRole;                      ///< 我在群里的角色
@property (nonatomic, strong) NSArray<IMGroupMember *> *members;       ///< 群主在前，其次管理员，再成员
// G1 群资料闭环字段（随 GET /groups/{id} 一次下发）。
@property (nonatomic, copy) NSString *intro;                           ///< 群简介
@property (nonatomic, copy) NSString *announcement;                    ///< 群公告正文（空=未发布/已撤下）
@property (nonatomic, copy, nullable) NSString *announcementBy;        ///< 公告最后发布者 uid
@property (nonatomic, assign) int64_t announcementAt;                  ///< 公告最后发布时间（端上据此判断"这版我看过没"）
@property (nonatomic, assign) NSInteger memberCount;                   ///< 群成员数
@property (nonatomic, copy, nullable) NSString *myNickname;            ///< 我在本群的昵称（便于直接回填编辑框）
@property (nonatomic, assign) int64_t muteUntil;                       ///< 全员禁言到期毫秒（0=未禁言；端上据此显示自助开关，G1）
// G2 群治理开关组（GET /groups/{id} 下发；仅群主/管理员能改）。
@property (nonatomic, assign) BOOL joinApproval;                       ///< 进群确认
@property (nonatomic, assign) BOOL permInvite;                         ///< YES=仅群主/管理员可邀请
@property (nonatomic, assign) BOOL permEditInfo;                       ///< YES=仅群主/管理员可改群资料
@property (nonatomic, assign) BOOL permPin;                            ///< YES=仅群主/管理员可置顶
@property (nonatomic, assign) BOOL historyVisible;                     ///< YES=新成员仅可见入群后历史
@property (nonatomic, assign) int64_t myMuteUntil;                     ///< 我的成员级禁言到期（G2；端上据此禁用输入栏）
/// 我是否群主/管理员（公告/资料/禁言等管理权限判定，与后端权限矩阵一致）。
@property (nonatomic, readonly) BOOL canManage;

/// 从 GET /groups/{id} 的 data 解析（脏数据安全；members 缺省为空数组）。
+ (nullable instancetype)groupFromDictionary:(nullable NSDictionary *)dict;

/// 从 GET /groups 的 data.groups 解析我的群列表（不含成员明细，members 为空）。
+ (NSArray<IMGroupInfo *> *)groupsFromArray:(nullable NSArray *)array;

/// 按 uid 查成员昵称（无该成员/无昵称返回 nil）。群聊气泡/正在输入的昵称回退用。
- (nullable NSString *)nicknameOfMember:(NSString *)userID;

/// 按 uid 查成员头像 URL（无该成员/无头像返回 nil）。群聊气泡头像列用。
- (nullable NSString *)avatarURLOfMember:(NSString *)userID;

@end

NS_ASSUME_NONNULL_END
