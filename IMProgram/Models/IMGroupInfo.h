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
@property (nonatomic, copy) NSString *nickname;
@property (nonatomic, copy) NSString *avatarURL;
@property (nonatomic, assign) IMGroupRole role;
@property (nonatomic, assign) int64_t joinedAt;
/// 展示名：有昵称用昵称，否则回退 uid。
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
