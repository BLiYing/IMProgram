//  IMHTTPService+Private.h
//  IMHTTPService 的**共享内部接口**：把请求构造与响应解包暴露给同类的分文件 category
//  （CODING_STYLE §7 ②：一组内聚方法 → 分文件 category），套路与 IMSocketManager+Private.h 一致。
//
//  拆分的直接原因是体量红线（IMHTTPService.m 已逼近 1500 行），但选择**沿"整会话查询"这条线**切：
//  会话内检索 / 日历聚合是离线积压方案里新长出来的一族接口（OFFLINE_BACKLOG_DESIGN §4.9），
//  与登录、上传、好友等既有接口没有共享状态，天然独立。

#import "IMHTTPService.h"

NS_ASSUME_NONNULL_BEGIN

// 存储属性放**类扩展 `()`** 而不是 category `(Private)`：category 不能合成 ivar，
// 写进去的话 `self.foo = …` 编译能过、运行到那行才 unrecognized selector（CODING_STYLE §3）。
@interface IMHTTPService ()
@property (atomic, copy, nullable) NSString *currentToken; // 对外只读，内部可写
@property (atomic, copy, nullable) NSString *currentNickname; // 同上；登录后异步预热，见 warmUpMyNickname
@property (atomic, copy, nullable) NSString *tokenUserID;      // 缓存 token 归属的 uid（切账号即失效）
@property (atomic, assign) CFAbsoluteTime tokenFetchedAt;      // 取得时刻：TTL 内直接复用，不重复 POST /login
// 合并在途登录（同 @synchronized(self) 保护）：冷启动缓存尚空时 socket 与会话列表等会并发调 loginWithUserID，
// 若各发一次 POST /login，同 device_id 的多次登录会互相顶替并踢掉 sid（后注册吊销先注册），先注册者的 token
// 若最后写回缓存，socket 便拿着已吊销 token 握手吃 401 被误判"被踢"回登录页。故同账号在途只真发一次。
@property (nonatomic, strong, nullable) NSMutableArray *pendingLoginCompletions;
@property (nonatomic, assign) BOOL loginInFlight;
@property (nonatomic, copy, nullable) NSString *loginInFlightUserID;
/// 最近一次登录成功时服务端返回的**内部 ID**。登录页据此拿到自己的身份（首次登录前 App 并不知道）。
@property (atomic, copy, nullable) NSString *lastLoginUserID;
@end


@interface IMHTTPService (Private)

/// 构造带 Bearer 的请求；body 非空时序列化为 JSON 并补 Content-Type。服务器地址非法时返回 nil。
- (nullable NSMutableURLRequest *)authedRequestForPath:(NSString *)path
                                                method:(NSString *)method
                                                 token:(NSString *)token
                                                  body:(nullable NSDictionary *)body;

/// 发请求并解包 `{code,message,data}`：code != 0 时用 fallback 造错误；回调已在主线程。
- (void)runDataRequest:(nullable NSMutableURLRequest *)request
              fallback:(NSString *)fallback
            completion:(void (^)(NSDictionary *_Nullable data, NSError *_Nullable error))completion;

/// URL 路径段转义（conv_id 里有下划线与字母数字，但别假设，统一走它）。
- (NSString *)pathEscape:(NSString *)raw;

/// 主线程回调（内部网络回调在会话队列上）。
- (void)callOnMain:(dispatch_block_t)block;

/// 造一个带文案的 NSError（domain/code 与既有一致）。
- (NSError *)errorWithMessage:(NSString *)message;

/// 造一个**带业务码**的 NSError。按码分支的调用方（如"登录已失效"）必须用它，
/// 别用 errorWithMessage:（那个把码拍成 -1，见 CODING_STYLE §5）。
- (NSError *)errorWithCode:(NSInteger)code message:(NSString *)message;

/// 免鉴权 POST（登录 / 续期 / 注册）。服务器地址非法时返回 nil。
- (nullable NSMutableURLRequest *)postRequestToPath:(NSString *)path body:(NSDictionary *)body;

/// 发请求并回 `{code,message,data}` 整包（不解 code）；回调线程不保证，调用方自行 callOnMain:。
- (void)runRequest:(NSURLRequest *)request
        completion:(void (^)(NSDictionary *_Nullable body, NSError *_Nullable error))completion;

/// 从响应体取 message，缺失时回 fallback。
- (NSString *)messageFrom:(nullable NSDictionary *)body fallback:(NSString *)fallback;

/// 发请求、只关心成不成（`{code}`），失败用 fallback 造错误；回调已在主线程。
- (void)runOKRequest:(nullable NSMutableURLRequest *)request
            fallback:(NSString *)fallback
          completion:(void (^)(NSError *_Nullable error))completion;

@end

/// 登录 / token 生命周期（IMHTTPService+Auth.m）。
@interface IMHTTPService (Auth)

/// 取一枚可用 access token；forceCredentialLogin=YES 强制走密码登录而非续期。见实现处注释。
- (void)obtainTokenForUserID:(NSString *)userID
        forceCredentialLogin:(BOOL)forceCredentialLogin
                  completion:(void (^)(NSString *_Nullable token, NSError *_Nullable error))completion;

/// 收束一次登录：owner=YES 时 fan-out 共享队列里排队的 completion，否则只回 soloCompletion。
- (void)finishLogin:(BOOL)owner
             userID:(NSString *)userID
              token:(nullable NSString *)token
              error:(nullable NSError *)error
     soloCompletion:(void (^)(NSString *_Nullable token, NSError *_Nullable error))soloCompletion;

/// 登录后异步拉一次本人资料，缓存公开显示名（供合并转发标题等同步场景取用）。失败静默。
- (void)warmUpMyNicknameWithToken:(NSString *)token;

@end

NS_ASSUME_NONNULL_END
