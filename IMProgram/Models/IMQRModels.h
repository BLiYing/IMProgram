//  IMQRModels.h
//  二维码体系（QRCODE P0）解析结果 + 入群申请（G3）模型 + 扫码结果→动作的纯映射。
//  语义判定全在服务端 /qr/resolve；本层只把返回字典解析成类型 + 把 relation/joinable 映射成按钮态。
//  映射函数是纯函数（无 UIKit 依赖），供 IMProgramTests 单测。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, IMQRKind) {
    IMQRKindUnknown = 0,
    IMQRKindUser,
    IMQRKindGroup,
};

/// 名片码扫后展示的对方资料。
@interface IMQRUserCard : NSObject
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy) NSString *nickname;
@property (nonatomic, copy) NSString *avatarURL;
@property (nonatomic, copy) NSString *relation;   ///< stranger | friend | self | blocked
+ (nullable instancetype)fromDictionary:(nullable NSDictionary *)dict;
@end

/// 群码扫后的群预览 + 准入判定。
@interface IMQRGroupCard : NSObject
@property (nonatomic, copy) NSString *groupID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *avatarURL;
@property (nonatomic, copy) NSString *intro;      ///< 群简介（加群预览页展示，可空）
@property (nonatomic, assign) NSInteger memberCount;
@property (nonatomic, copy) NSString *inviterNickname;
@property (nonatomic, assign) BOOL joined;
@property (nonatomic, assign) BOOL joinable;
@property (nonatomic, copy) NSString *reason;     ///< "" 可加入 | approval 需审批 | joined | full | banned
+ (nullable instancetype)fromDictionary:(nullable NSDictionary *)dict;
@end

/// POST /qr/resolve 的 data（{kind, data}）解析结果。
@interface IMQRResolved : NSObject
@property (nonatomic, assign) IMQRKind kind;
@property (nonatomic, strong, nullable) IMQRUserCard *user;
@property (nonatomic, strong, nullable) IMQRGroupCard *group;
@property (nonatomic, copy, nullable) NSString *unknownText;   ///< kind=unknown 时的原文
+ (instancetype)fromDictionary:(nullable NSDictionary *)dict;
@end

/// 一条待审入群申请（G3）。
@interface IMJoinRequest : NSObject
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy) NSString *nickname;
@property (nonatomic, copy) NSString *avatarURL;
@property (nonatomic, copy) NSString *hello;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, assign) int64_t createdAt;
+ (nullable instancetype)fromDictionary:(nullable NSDictionary *)dict;
+ (NSArray<IMJoinRequest *> *)fromArray:(nullable NSArray *)arr;
@end

#pragma mark - 扫码结果 → 动作映射（纯函数，可单测）

typedef NS_ENUM(NSInteger, IMQRUserAction) {
    IMQRUserActionAdd = 0,    ///< 陌生人：加好友
    IMQRUserActionMessage,    ///< 好友：发消息
    IMQRUserActionSelf,       ///< 扫自己：只看资料
    IMQRUserActionBlocked,    ///< 已拉黑：只看资料（不给加好友后门）
};

typedef NS_ENUM(NSInteger, IMQRGroupAction) {
    IMQRGroupActionJoin = 0,  ///< 可直接加入
    IMQRGroupActionApply,     ///< 需审批：申请加入（可带附言）
    IMQRGroupActionEnter,     ///< 已在群：进入群聊
    IMQRGroupActionDisabled,  ///< 满/黑名单：不可加入
};

/// relation → 名片码主按钮动作。
FOUNDATION_EXPORT IMQRUserAction IMQRUserActionForRelation(NSString *_Nullable relation);
/// 名片码主按钮文案。
FOUNDATION_EXPORT NSString *IMQRUserActionLabel(IMQRUserAction action);
/// 群码 → 群主按钮动作。
FOUNDATION_EXPORT IMQRGroupAction IMQRGroupActionForCard(IMQRGroupCard *_Nullable card);
/// 群码主按钮文案。
FOUNDATION_EXPORT NSString *IMQRGroupActionLabel(IMQRGroupAction action);
/// 群码不可加入/需审批时的说明文案（可空）。
FOUNDATION_EXPORT NSString *_Nullable IMQRGroupActionNote(IMQRGroupCard *_Nullable card);
/// 外来码原文是否 http(s) URL；是则回域名主体（供二次确认高亮），否则回 nil。
FOUNDATION_EXPORT NSString *_Nullable IMQRUnknownDomain(NSString *_Nullable text);

NS_ASSUME_NONNULL_END
