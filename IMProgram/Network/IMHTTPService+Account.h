//  IMHTTPService+Account.h
//  账号注销 / 恢复（IMServer/docs/design/DELETE_ACCOUNT_DESIGN.md §3 §5）。
//  契约来源：设计稿 §5；PROTOCOL.md 的「账号注销」章节落地后须对账（尤其 owned_groups / delete_at 的字段形态与
//  AccountPendingDeletion 的码值）。

#import "IMHTTPService.h"

NS_ASSUME_NONNULL_BEGIN

/// 冷静期内登录返回的业务码（设计稿建议 200005；CONVENTIONS §2 一经发布永不改）。待与 PROTOCOL.md 对账。
FOUNDATION_EXPORT NSInteger const IMErrCodeAccountPendingDeletion;
/// 通用无权限；注销时附 owned_groups 表示「你还是群主」。
FOUNDATION_EXPORT NSInteger const IMErrCodeNoPermission;
/// NSError.userInfo 键：删除生效时间（NSDate），来自响应 data.delete_at。
FOUNDATION_EXPORT NSString * const IMErrorDeleteAtKey;
/// NSError.userInfo 键：我是群主的群，NSArray<NSDictionary>，每项 @{@"id": 群 topic_id, @"name": 群名}。
FOUNDATION_EXPORT NSString * const IMErrorOwnedGroupsKey;

/// 解析 delete_at：数字（秒或毫秒，>1e11 视为毫秒）或 ISO8601 字符串；无法解析返回 nil。
FOUNDATION_EXPORT NSDate *_Nullable IMParseDeleteAt(id _Nullable raw);

/// 解析 owned_groups：元素可为 {id|group_id|conv_id|topic_id, name} 字典或纯字符串（当群名）；脏数据安全。
FOUNDATION_EXPORT NSArray<NSDictionary<NSString *, NSString *> *> *IMParseOwnedGroups(id _Nullable raw);

/// 「X月X日」式的生效日显示串（按 App 语言 locale，模板 MMMd）；date 为 nil 时回退为「7 天后」语义的空串由调用方兜底——
/// 这里 nil 返回 @"-"，避免弹窗里出现空洞。
FOUNDATION_EXPORT NSString *IMDeleteAtDisplayString(NSDate *_Nullable date);

/// 把响应 `data` 里的 delete_at / owned_groups 附到错误的 userInfo（码与文案不变）。body 里没有就原样返回。
FOUNDATION_EXPORT NSError *IMErrorByAttachingAccountInfo(NSError *error, NSDictionary *_Nullable body);

@interface IMHTTPService (Account)

/// POST /api/v1/account/delete {password}（Bearer）。成功回 nil；
/// 群主阻断回 NoPermission(100103) 且 userInfo[IMErrorOwnedGroupsKey] 有值；密码错回 200002。主线程回调。
- (void)deleteAccountWithToken:(NSString *)token
                      password:(NSString *)password
                    completion:(void (^)(NSError *_Nullable error))completion;

/// POST /api/v1/account/restore {username,password}（免鉴权，等同登录）。成功回 nil。主线程回调。
- (void)restoreAccountWithUsername:(NSString *)username
                          password:(NSString *)password
                        completion:(void (^)(NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
