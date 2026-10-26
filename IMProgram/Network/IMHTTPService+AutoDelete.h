//  IMHTTPService+AutoDelete.h
//  自动删除消息的 REST（PROTOCOL §6.8.1）：会话设置 PUT 带 auto_delete_sec + 账号默认档位 GET/PUT /users/me/privacy。

#import "IMHTTPService.h"
#import "IMPrivacyVisibility.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMHTTPService (AutoDelete)

/// 同 updateConversationSettingsWithToken:…，但显式控制 auto_delete_sec：
/// 传 nil = **省略**该字段（服务端保留原值，PROTOCOL §6.8.1；置顶/免打扰/标未读一律如此）；传值（含 @0）= 改成该档位，仅档位选择路径使用
/// （v2：会话级共享，群里非群主/管理员改档位会被 300204 拒绝，error.code 保留业务码）。
/// completion 回主线程；成功时 data 是回包 data（含 auto_delete_sec + auto_delete_from，可能为空字典）。
- (void)updateConversationSettingsWithToken:(NSString *)token
                                     convID:(NSString *)convID
                                   pinnedAt:(int64_t)pinnedAt
                                      muted:(BOOL)muted
                                  muteUntil:(nullable NSNumber *)muteUntil
                               markedUnread:(BOOL)markedUnread
                              autoDeleteSec:(nullable NSNumber *)autoDeleteSec
                                 completion:(void (^)(NSDictionary *_Nullable data, NSError *_Nullable error))completion;

/// GET /api/v1/users/me/privacy → auto_delete_default_sec。completion 主线程。
- (void)fetchAutoDeleteDefaultWithToken:(NSString *)token
                             completion:(void (^)(int64_t sec, NSError *_Nullable error))completion;

/// PUT /api/v1/users/me/privacy {auto_delete_default_sec}。completion 主线程。
- (void)saveAutoDeleteDefault:(int64_t)sec token:(NSString *)token
                   completion:(void (^)(NSError *_Nullable error))completion;

/// GET /api/v1/users/me/privacy 完整对象（自动删除默认档 + 谁能看到两项）。completion 主线程；失败时 settings 为 nil。
- (void)fetchPrivacySettingsWithToken:(NSString *)token
                           completion:(void (^)(IMPrivacySettings *_Nullable settings, NSError *_Nullable error))completion;

/// PUT /api/v1/users/me/privacy，**只带被改的那一项**（部分更新，不覆盖 auto_delete_default_sec 与另一项）。completion 主线程。
- (void)saveVisibility:(NSString *)level forKind:(IMPrivacyVisibilityKind)kind token:(NSString *)token
            completion:(void (^)(NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
