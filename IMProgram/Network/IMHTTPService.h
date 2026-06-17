//  IMHTTPService.h
//  非实时 HTTP 接口（登录、会话列表）。实时收发走 IMSocketManager。

#import <Foundation/Foundation.h>

@class IMConversation;
@class IMUserCard;

NS_ASSUME_NONNULL_BEGIN

/// 该错误码是否"鉴权失败"类（用户不存在/密码错/封禁/token 失效）→ 调用方应退回登录页。
/// 失败 NSError 的 code 即业务错误码（登录接口已带）；网络/未知为 -1。
BOOL IMIsAuthErrorCode(NSInteger code);

@interface IMHTTPService : NSObject

+ (instancetype)sharedService;

/// 服务器地址 host:port（如 192.168.1.3:8080）。
@property (nonatomic, copy) NSString *host;

/// 当前登录密码（登录成功后由登录页设入；为空=走后端开发期免密直签）。
/// 全局共享：会话列表/通讯录等内部再登录、以及 IMSocketManager 换 token 都读它，无需逐处透传。
@property (nonatomic, copy, nullable) NSString *password;

/// 最近一次登录成功缓存的 JWT（只读）。供聊天页等无需重新登录即可发起 HTTP（如举报）。
@property (atomic, copy, readonly, nullable) NSString *currentToken;

/// 登录换取 JWT：带 password 走真账号校验，password 为空走开发期免密。completion 在主线程回调。
- (void)loginWithUserID:(NSString *)userID
             completion:(void (^)(NSString *_Nullable token, NSError *_Nullable error))completion;

/// 注册账号：POST /api/v1/register {username, password}（密码 ≥ 6 位由后端校验）。completion 在主线程回调。
- (void)registerWithUsername:(NSString *)username
                    password:(NSString *)password
                  completion:(void (^)(NSError *_Nullable error))completion;

/// 拉取会话列表（Bearer token）。completion 在主线程回调。
- (void)conversationsWithToken:(NSString *)token
                    completion:(void (^)(NSArray<IMConversation *> *_Nullable conversations, NSError *_Nullable error))completion;

#pragma mark - 通讯录（M2.5 找人 / 好友关系）

/// 找人：按 query 搜索用户（昵称/手机号/uid/标签，后端去 phone、排除自己）。completion 在主线程回调。
- (void)searchUsersWithToken:(NSString *)token
                       query:(NSString *)query
                  completion:(void (^)(NSArray<IMUserCard *> *_Nullable users, NSError *_Nullable error))completion;

/// 好友/申请列表（status 为空=全部：accepted/pending/requested/blocked）。completion 在主线程回调。
- (void)friendsWithToken:(NSString *)token
                  status:(nullable NSString *)status
              completion:(void (^)(NSArray<IMUserCard *> *_Nullable friends, NSError *_Nullable error))completion;

/// 好友动作（action ∈ request/accept/reject/block/unblock），body {user_id:peerID}。completion 在主线程回调。
- (void)friendActionWithToken:(NSString *)token
                       action:(NSString *)action
                       peerID:(NSString *)peerID
                   completion:(void (^)(NSError *_Nullable error))completion;

/// 删除好友（DELETE /api/v1/friends/{peerID}）。completion 在主线程回调。
- (void)removeFriendWithToken:(NSString *)token
                       peerID:(NSString *)peerID
                   completion:(void (^)(NSError *_Nullable error))completion;

#pragma mark - 我的资料（M2.5 编辑资料）

/// 读取本人资料（GET /api/v1/users/me，含 phone）。completion 在主线程回调。
- (void)myProfileWithToken:(NSString *)token
                completion:(void (^)(IMUserCard *_Nullable profile, NSError *_Nullable error))completion;

/// 整体更新本人资料（PUT /api/v1/users/me）。tags 传字符串数组。completion 在主线程回调。
- (void)updateProfileWithToken:(NSString *)token
                      nickname:(NSString *)nickname
                     avatarURL:(NSString *)avatarURL
                         phone:(NSString *)phone
                          tags:(NSArray<NSString *> *)tags
                    completion:(void (^)(IMUserCard *_Nullable profile, NSError *_Nullable error))completion;

#pragma mark - 举报（AG-3）

/// 举报（POST /api/v1/reports）。targetType=message|user|group；convID 可空。completion 在主线程回调。
- (void)reportWithToken:(NSString *)token
             targetType:(NSString *)targetType
               targetID:(NSString *)targetID
                 convID:(nullable NSString *)convID
                 reason:(NSString *)reason
             completion:(void (^)(NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
