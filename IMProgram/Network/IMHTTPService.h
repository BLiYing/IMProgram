//  IMHTTPService.h
//  非实时 HTTP 接口（登录、会话列表）。实时收发走 IMSocketManager。

#import <Foundation/Foundation.h>

@class IMConversation;
@class IMUserCard;
@class IMGroupInfo;

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

/// 拉取账号级自动下载策略（M4-7）：GET /api/v1/download-settings，回 data 字典 `{version, settings:{...}}`。
/// completion 在主线程回调；失败 data=nil。
- (void)downloadSettingsWithToken:(NSString *)token
                       completion:(void (^)(NSDictionary *_Nullable data, NSError *_Nullable error))completion;

/// 保存自动下载策略（M4-7）：PUT /api/v1/download-settings，body=`{cellular,wifi}`；回 data `{version, settings}`。
- (void)updateDownloadSettingsWithToken:(NSString *)token
                               settings:(NSDictionary *)settings
                             completion:(void (^)(NSDictionary *_Nullable data, NSError *_Nullable error))completion;

/// 恢复出厂默认（M4-7）：POST /api/v1/download-settings/reset；回 data `{version, settings}`。
- (void)resetDownloadSettingsWithToken:(NSString *)token
                            completion:(void (^)(NSDictionary *_Nullable data, NSError *_Nullable error))completion;

/// 我发送的文件：服务端游标分页，默认 50 条。cursor 为空取第一页。
- (void)sentFilesWithToken:(NSString *)token
                     cursor:(nullable NSString *)cursor
                 completion:(void (^)(NSArray<NSDictionary *> *_Nullable files,
                                      NSString *_Nullable nextCursor,
                                      BOOL hasMore,
                                      NSError *_Nullable error))completion;

/// 「仅为我删除」（任务2）：POST /api/v1/messages/hide {conv_id, conv_seq}。落 per-user 隐藏表 + 多设备同步。
- (void)hideMessageWithToken:(NSString *)token
                      convID:(NSString *)convID
                     convSeq:(int64_t)convSeq
                  completion:(void (^)(NSError *_Nullable error))completion;

/// 登录 catch-up（任务2）：GET /api/v1/messages/hidden → 隐藏消息全集 `[{conv_id, conv_seq}]`。completion 主线程回调。
- (void)fetchHiddenWithToken:(NSString *)token
                  completion:(void (^)(NSArray<NSDictionary *> *_Nullable items, NSError *_Nullable error))completion;

#pragma mark - 通讯录（M2.5 找人 / 好友关系）

/// 找人：按 query 搜索用户（昵称/手机号/uid/标签，后端去 phone、排除自己）。completion 在主线程回调。
- (void)searchUsersWithToken:(NSString *)token
                       query:(NSString *)query
                  completion:(void (^)(NSArray<IMUserCard *> *_Nullable users, NSError *_Nullable error))completion;

/// 好友/申请列表（status 为空=全部：accepted/pending/requested/blocked）。completion 在主线程回调。
- (void)friendsWithToken:(NSString *)token
                  status:(nullable NSString *)status
              completion:(void (^)(NSArray<IMUserCard *> *_Nullable friends, NSError *_Nullable error))completion;

/// 发好友申请（POST /api/v1/friends/request）。completion 在主线程回调。
/// becameFriend=YES 表示**已直接成为好友、无需对方确认**（对方先申请过我；或我曾单向删除对方而对方仍视我为好友）。
/// 调用方据此**不要提示「已发送好友申请」**——那会让用户误以为还要等对方通过；刷新界面即可。
- (void)requestFriendWithToken:(NSString *)token
                        peerID:(NSString *)peerID
                    completion:(void (^)(BOOL becameFriend, NSError *_Nullable error))completion;

/// 好友动作（action ∈ request/accept/reject/block/unblock），body {user_id:peerID}。completion 在主线程回调。
/// ⚠️ 发申请请改用上面的 `requestFriendWithToken:` —— 它能区分「已发申请」与「已直接成为好友」。
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

/// 读取他人名片（GET /api/v1/users/{id}，无 phone，含在线态快照 presence）。
/// presence 帧只报**变化**，进入聊天页/资料页时的在线态初始值须由此处取。completion 在主线程回调。
- (void)userProfileWithToken:(NSString *)token
                      userID:(NSString *)userID
                  completion:(void (^)(IMUserCard *_Nullable profile, NSError *_Nullable error))completion;

/// 整体更新本人资料（PUT /api/v1/users/me）。tags 传字符串数组。completion 在主线程回调。
- (void)updateProfileWithToken:(NSString *)token
                      nickname:(NSString *)nickname
                     avatarURL:(NSString *)avatarURL
                         phone:(NSString *)phone
                          tags:(NSArray<NSString *> *)tags
                    completion:(void (^)(IMUserCard *_Nullable profile, NSError *_Nullable error))completion;

#pragma mark - 群聊（M3）

/// 建群：owner=自己（token 决定），memberIDs=初始成员。completion 回新建群资料（含成员），主线程。
- (void)createGroupWithToken:(NSString *)token
                        name:(NSString *)name
                   memberIDs:(NSArray<NSString *> *)memberIDs
                  completion:(void (^)(IMGroupInfo *_Nullable group, NSError *_Nullable error))completion;

/// 我的群列表（不含成员明细）。completion 在主线程回调。
- (void)groupsWithToken:(NSString *)token
             completion:(void (^)(NSArray<IMGroupInfo *> *_Nullable groups, NSError *_Nullable error))completion;

/// 群资料 + 成员（须为群成员，否则 300203）。completion 在主线程回调。
- (void)groupInfoWithToken:(NSString *)token
                    convID:(NSString *)convID
                completion:(void (^)(IMGroupInfo *_Nullable group, NSError *_Nullable error))completion;

/// 群消息已读/未读名单（M4-8）：GET /conversations/{id}/messages/{seq}/read-by。
/// **仅消息发送者本人**可调（他人调用服务端回 403）。`enabled=NO` 表示群规模超上限（>2000 人），
/// 此时 read/unread 为空，调用方应隐藏入口而非报错。completion 在主线程回调。
- (void)readReceiptsWithToken:(NSString *)token
                       convID:(NSString *)convID
                      convSeq:(int64_t)convSeq
                   completion:(void (^)(NSArray<NSString *> *_Nullable readUIDs,
                                        NSArray<NSString *> *_Nullable unreadUIDs,
                                        BOOL enabled,
                                        NSError *_Nullable error))completion;

/// 改群资料（群名/头像；群主或管理员）。completion 在主线程回调。
- (void)updateGroupWithToken:(NSString *)token
                      convID:(NSString *)convID
                        name:(NSString *)name
                   avatarURL:(NSString *)avatarURL
                  completion:(void (^)(NSError *_Nullable error))completion;

/// 邀请入群（任意成员可邀）。completion 在主线程回调。
- (void)inviteToGroupWithToken:(NSString *)token
                        convID:(NSString *)convID
                     memberIDs:(NSArray<NSString *> *)memberIDs
                    completion:(void (^)(NSError *_Nullable error))completion;

/// 退群（群主须先转让，否则 300204 带服务端原因）。completion 在主线程回调。
- (void)leaveGroupWithToken:(NSString *)token
                     convID:(NSString *)convID
                 completion:(void (^)(NSError *_Nullable error))completion;

/// 移除成员（须权限严格高于对方）。completion 在主线程回调。
- (void)removeGroupMemberWithToken:(NSString *)token
                            convID:(NSString *)convID
                            userID:(NSString *)userID
                        completion:(void (^)(NSError *_Nullable error))completion;

/// 设/撤管理员（仅群主）：role ∈ admin|member。completion 在主线程回调。
- (void)setGroupRoleWithToken:(NSString *)token
                       convID:(NSString *)convID
                       userID:(NSString *)userID
                         role:(NSString *)role
                   completion:(void (^)(NSError *_Nullable error))completion;

/// 转让群主（仅群主；原群主降为普通成员）。completion 在主线程回调。
- (void)transferGroupWithToken:(NSString *)token
                        convID:(NSString *)convID
                        userID:(NSString *)userID
                    completion:(void (^)(NSError *_Nullable error))completion;

/// 解散群组（仅群主）：DELETE /api/v1/groups/{id}。删群并广播 dissolve 群事件。completion 在主线程回调。
- (void)dissolveGroupWithToken:(NSString *)token
                        convID:(NSString *)convID
                    completion:(void (^)(NSError *_Nullable error))completion;

#pragma mark - 会话管理（M4.5）

/// 更新会话级设置（置顶/免打扰/标未读，整体替换）：PUT /api/v1/conversations/{id}/settings。completion 主线程回调。
- (void)updateConversationSettingsWithToken:(NSString *)token
                                     convID:(NSString *)convID
                                   pinnedAt:(int64_t)pinnedAt
                                      muted:(BOOL)muted
                               markedUnread:(BOOL)markedUnread
                                 completion:(void (^)(NSError *_Nullable error))completion;

/// 删除会话（仅本人，记 cleared_at 不删消息）：DELETE /api/v1/conversations/{id}。completion 主线程回调。
- (void)deleteConversationWithToken:(NSString *)token
                             convID:(NSString *)convID
                         completion:(void (^)(NSError *_Nullable error))completion;

#pragma mark - 举报（AG-3）

/// 举报（POST /api/v1/reports）。targetType=message|user|group；convID 可空。completion 在主线程回调。
- (void)reportWithToken:(NSString *)token
             targetType:(NSString *)targetType
               targetID:(NSString *)targetID
                 convID:(nullable NSString *)convID
                 reason:(NSString *)reason
             completion:(void (^)(NSError *_Nullable error))completion;

/// 收藏（M4-4）：POST /api/v1/favorites（内容快照）。completion 主线程回调。
- (void)addFavoriteWithToken:(NSString *)token
                 contentType:(NSString *)contentType
                     content:(NSString *)content
                sourceConvID:(nullable NSString *)sourceConvID
               sourceConvSeq:(int64_t)sourceConvSeq
                  sourceFrom:(nullable NSString *)sourceFrom
                  completion:(void (^)(NSError *_Nullable error))completion;
/// 我的收藏列表：GET /api/v1/favorites。返回 favorites 数组（原始字典，含 id/content/content_type/...）。
- (void)favoritesWithToken:(NSString *)token
                completion:(void (^)(NSArray<NSDictionary *> *_Nullable favorites, NSError *_Nullable error))completion;
/// 删收藏：DELETE /api/v1/favorites/{id}。completion 主线程回调。
- (void)deleteFavoriteWithToken:(NSString *)token
                     favoriteID:(int64_t)favoriteID
                     completion:(void (^)(NSError *_Nullable error))completion;

/// 翻译（M4-5）：POST /api/v1/translate {text, target_lang}。回调返回译文（主线程）。
- (void)translateWithToken:(NSString *)token
                      text:(NSString *)text
                targetLang:(nullable NSString *)targetLang
                completion:(void (^)(NSString *_Nullable translation, NSError *_Nullable error))completion;

/// 链接富预览（OG 抓取）：GET /api/v1/link-preview?url=。回调返回 @{title,description,image,site_name}（主线程；失败 error）。
- (void)linkPreviewWithToken:(NSString *)token
                          url:(NSString *)url
                   completion:(void (^)(NSDictionary *_Nullable preview, NSError *_Nullable error))completion;

/// 上传图片/文件（M4-6）：multipart POST /api/v1/upload。回调返回 url + content_type（主线程）。
- (void)uploadData:(NSData *)data
          fileName:(NSString *)fileName
          mimeType:(NSString *)mimeType
             token:(NSString *)token
        completion:(void (^)(NSString *_Nullable url, NSString *_Nullable contentType, NSError *_Nullable error))completion;

/// 带真实字节进度的上传（批量发图/视频的居中进度用）：progress 主线程回调 0..1。
- (void)uploadData:(NSData *)data
          fileName:(NSString *)fileName
          mimeType:(NSString *)mimeType
             token:(NSString *)token
          progress:(nullable void (^)(double fraction))progress
        completion:(void (^)(NSString *_Nullable url, NSString *_Nullable contentType, NSError *_Nullable error))completion;

/// 头像专用上传（方案 C）：multipart POST /api/v1/avatar（独立目录、内容寻址、永不清理）。
/// data 应为裁切并缩到 256×256 的 JPEG。回调返回 /avatars/<hash>.jpg 相对 URL（主线程）。
- (void)uploadAvatarData:(NSData *)data
                   token:(NSString *)token
              completion:(void (^)(NSString *_Nullable url, NSError *_Nullable error))completion;

/// error 是否服务端**业务拒绝**（HTTP 层成功但 code>0，如「上传会话不存在或已过期」）——
/// 与网络失败（超时/断网，code=-1 或 NSURLErrorDomain）相对：前者重试同一请求必然再失败。
+ (BOOL)isBusinessError:(nullable NSError *)error;

/// 分片上传四端点的公共通道（供 IMChunkedUploader 使用，不直接给业务层用）。
/// body 为 nil=无请求体；PUT 分片时 body 即原始字节（非 multipart）。
/// 回调在**主线程**（与其余 HTTP 通道一致）；调用方若要做读盘等重活务必自行切到后台队列。
/// 返回底层 task（非法地址时 nil）：暂停/放弃传输链时应 cancel 它，否则 8MB 请求体会继续传完。
- (nullable NSURLSessionTask *)performUploadAPI:(NSString *)path
                  method:(NSString *)method
                    body:(nullable NSData *)body
                   token:(NSString *)token
              completion:(void (^)(NSDictionary *_Nullable data, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
