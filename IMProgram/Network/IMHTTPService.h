//  IMHTTPService.h
//  非实时 HTTP 接口（登录、会话列表）。实时收发走 IMSocketManager。

#import <Foundation/Foundation.h>

@class IMConversation;
@class IMUserCard;

NS_ASSUME_NONNULL_BEGIN

@interface IMHTTPService : NSObject

+ (instancetype)sharedService;

/// 服务器地址 host:port（如 192.168.1.3:8080）。
@property (nonatomic, copy) NSString *host;

/// 当前登录密码（登录成功后由登录页设入；为空=走后端开发期免密直签）。
/// 全局共享：会话列表/通讯录等内部再登录、以及 IMSocketManager 换 token 都读它，无需逐处透传。
@property (nonatomic, copy, nullable) NSString *password;

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

@end

NS_ASSUME_NONNULL_END
