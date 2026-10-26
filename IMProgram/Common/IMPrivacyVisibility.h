//  IMPrivacyVisibility.h
//  隐私「谁能看到」的纯逻辑（PRIVACY_VISIBILITY_DESIGN §2/§4）：档位解析、行名 / 页脚键、PUT 只带被改项。
//  与账号默认自动删除档位共用 GET/PUT /users/me/privacy（IMHTTPService+AutoDelete）。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 「谁能看到」的项目（本期两项）。
typedef NS_ENUM(NSInteger, IMPrivacyVisibilityKind) {
    IMPrivacyVisibilityKindLastSeen = 0, ///< 上次上线（整个在线态）
    IMPrivacyVisibilityKindAvatar,       ///< 头像
};

extern NSString *const IMPrivacyVisibilityEveryone; ///< @"everyone"
extern NSString *const IMPrivacyVisibilityContacts; ///< @"contacts"
extern NSString *const IMPrivacyVisibilityNobody;   ///< @"nobody"

/// 三档，展示顺序：所有人 / 我的联系人 / 无人。
NSArray<NSString *> *IMPrivacyVisibilityLevels(void);
/// 服务端字段名：last_seen_visibility / avatar_visibility。
NSString *IMPrivacyVisibilityJSONKey(IMPrivacyVisibilityKind kind);
/// 默认档位（= 设置上线前的既有行为）：上次上线 contacts，头像 everyone。
NSString *IMPrivacyVisibilityDefault(IMPrivacyVisibilityKind kind);
/// 解析服务端值：三值之一原样返回，其余（缺失 / 空串 / 未知 / 非字符串）落到该项默认档。
NSString *IMPrivacyVisibilityParse(IMPrivacyVisibilityKind kind, id _Nullable raw);
/// 档位显示名（i18n）：ps.visibility.everyone / contacts / nobody。
NSString *IMPrivacyVisibilityTitle(NSString *level);
/// 行名 / 页标题 i18n 键与页脚 i18n 键。
NSString *IMPrivacyVisibilityRowTitleKey(IMPrivacyVisibilityKind kind);
NSString *IMPrivacyVisibilityFooterKey(IMPrivacyVisibilityKind kind);
/// PUT body：**只含被改的那一项**（部分更新，不覆盖 auto_delete_default_sec 与另一项）。
NSDictionary *IMPrivacyVisibilityPutBody(IMPrivacyVisibilityKind kind, NSString *level);

/// GET /users/me/privacy 的完整对象。
@interface IMPrivacySettings : NSObject
@property (nonatomic, assign) int64_t autoDeleteDefaultSec;
@property (nonatomic, copy) NSString *lastSeenVisibility;
@property (nonatomic, copy) NSString *avatarVisibility;
+ (instancetype)settingsFromJSON:(nullable NSDictionary *)data;
- (NSString *)visibilityForKind:(IMPrivacyVisibilityKind)kind;
- (void)setVisibility:(NSString *)level forKind:(IMPrivacyVisibilityKind)kind;
@end

NS_ASSUME_NONNULL_END
