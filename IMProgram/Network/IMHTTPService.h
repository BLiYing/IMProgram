//  IMHTTPService.h
//  非实时 HTTP 接口（登录、会话列表）。实时收发走 IMSocketManager。

#import <Foundation/Foundation.h>

@class IMConversation;
@class IMUserCard;
@class IMGroupInfo;
@class IMPinnedMessage;
@class IMDeviceSession;

NS_ASSUME_NONNULL_BEGIN

/// 该错误码是否"鉴权失败"类（用户不存在/密码错/封禁/token 失效）→ 调用方应退回登录页。
/// 失败 NSError 的 code 即业务错误码（登录接口已带）；网络/未知为 -1。
BOOL IMIsAuthErrorCode(NSInteger code);

/// 业务错误码 → 友好中文（对齐 internal/errcode）。未收录返回 nil，回退服务端原文。
/// HTTP 路径已在服务内部调用；WS `send_msg` 拒收路径（IMSocketManager handleSendRejected）
/// 也需同一映射，把 300004/300206/300208 等英文默认文案改成中文，让气泡系统行/toast 有可读文本。
NSString *_Nullable IMFriendlyMessageForCode(NSInteger code);

@interface IMHTTPService : NSObject

+ (instancetype)sharedService;

/// 服务器地址 host:port（如 192.168.1.3:8080）。
@property (nonatomic, copy) NSString *host;

/// 当前登录用的**公开句柄 username**（登录页设入 / 冷启动由 IMSessionStore 恢复）。
/// 登录接口只认 username，**不认内部 ID**——App 内各处 loginWithUserID: 传的是内部 ID（作缓存键），
/// 真正发出去的用户名取自这里。为空时回退用传入的 userID（仅兼容早期调用路径）。
@property (nonatomic, copy, nullable) NSString *username;

/// 当前登录密码（登录成功后由登录页设入；为空=走后端开发期免密直签）。
/// 全局共享：会话列表/通讯录等内部再登录、以及 IMSocketManager 换 token 都读它，无需逐处透传。
@property (nonatomic, copy, nullable) NSString *password;

/// 最近一次登录成功缓存的 JWT（只读）。供聊天页等无需重新登录即可发起 HTTP（如举报）。
@property (atomic, copy, readonly, nullable) NSString *currentToken;

/// **我自己的公开显示名**（昵称）缓存，只读。登录成功后由本服务异步拉一次 `/users/me` 填上；
/// 取不到 / 还没回来时为 nil，调用方必须能降级（别拿它当必得值）。
///
/// 为什么要缓存：合并转发卡片标题要写「对方和我的聊天记录」（微信式），而打包是**同步**的
/// JSON 构造，等不了一次网络往返；而此前 App 里根本没有"我叫什么"的进程内缓存——只有
/// 设置页/资料编辑页各自拉一次自用。空值时标题按 IMChatRecordTitle 的降级链退成「对方的聊天记录」。
@property (atomic, copy, readonly, nullable) NSString *currentNickname;

/// 登录换取 JWT：带 password 走真账号校验，password 为空走开发期免密。completion 在主线程回调。
/// userID 是**内存缓存键与在途合并键**（内部 ID）；真正发给后端的用户名取 self.username。
- (void)loginWithUserID:(NSString *)userID
             completion:(void (^)(NSString *_Nullable token, NSError *_Nullable error))completion;

/// 登录页专用：用 username + password 登录，回调同时给出服务端分配的**内部 ID**。
/// 首次登录时 App 还不知道自己的内部 ID，只能从这里拿——之后一切业务参数都用它。
- (void)loginWithUsername:(NSString *)username
               completion:(void (^)(NSString *_Nullable token, NSString *_Nullable userID, NSError *_Nullable error))completion;

/// 作废内存缓存的 token（退出登录 / 被踢下线时调用）：避免 TTL 内继续复用已失效的旧 token。
/// 不动持久化会话（那由 IMSessionStore 负责）；下次 loginWithUserID 会强制重新 POST /login。
- (void)invalidateToken;

/// 注册账号：POST /api/v1/register {username, password, nickname}。三者必填，规则由后端权威校验
/// （username `^[a-z0-9_]{5,32}$` 且大小写不敏感唯一；password ≥6；nickname ≤32 字）。
/// **nickname 必填**：全端显示名回退链止于它，留空会让界面露出 10 位数字内部 ID。
- (void)registerWithUsername:(NSString *)username
                    password:(NSString *)password
                    nickname:(NSString *)nickname
                  completion:(void (^)(NSError *_Nullable error))completion;

/// 修改公开句柄：POST /api/v1/users/me/username {username}。成功回 nil。
/// 不影响登录态（服务端不吊销会话），但调用方须把新 username 写回 IMSessionStore，否则下次冷启动重登会用旧名。
- (void)updateUsername:(NSString *)username
                 token:(NSString *)token
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

/// 语音转文字（服务端识别）：POST /api/v1/voice/transcripts {conv_id, conv_seq}。
/// **只传消息坐标不传音频路径**（服务端自己反查 content 并过路径白名单）。
/// status = pending（已入队，等 WS voice_transcript 帧）/ done（带 text）/ failed。
/// 失败时 error.code 为业务码：500101 未启用 / 500102 识别失败 / 500103 队列满 / 100002 限流。
- (void)transcribeVoiceWithToken:(NSString *)token
                          convID:(NSString *)convID
                         convSeq:(int64_t)convSeq
                      completion:(void (^)(NSString *_Nullable status, NSString *_Nullable text, NSError *_Nullable error))completion;

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

/// 设置好友备注名（POST /api/v1/friends/remark，仅本人可见、多端同步）。留空即清除。
/// 服务端上限 32 字（超出回 100001）、非好友回 200103；error 保留业务码（读 error.code 分支）。
/// 成功后服务端会给**本人其它在线设备**推 friend(event=remark) 帧，本端自己做乐观更新。
- (void)setFriendRemarkWithToken:(NSString *)token
                          peerID:(NSString *)peerID
                          remark:(NSString *)remark
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

/// 修改密码（POST /api/v1/users/me/password）。旧密错回 200002 WrongPassword，
/// 新密 <6 位回 100002 ParamInvalid，账号被封回 200003 AccountBanned。completion 在主线程回调。
- (void)changePasswordWithToken:(NSString *)token
                    oldPassword:(NSString *)oldPassword
                    newPassword:(NSString *)newPassword
                     completion:(void (^)(NSError *_Nullable error))completion;

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

/// 会话当前置顶消息（G0）：GET /conversations/{id}/pinned。须为会话成员；服务端按 pinned_at 倒序、
/// 最多 50 条，且已排除撤回/为所有人删除/本人「仅为我删除」的。进会话拉一次回填横幅，
/// 之后靠实时 msg_op 帧增量维护，**不轮询**。completion 在主线程回调。
- (void)pinnedMessagesWithToken:(NSString *)token
                         convID:(NSString *)convID
                     completion:(void (^)(NSArray<IMPinnedMessage *> *_Nullable items, NSError *_Nullable error))completion;

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
                       intro:(NSString *)intro
                  completion:(void (^)(NSError *_Nullable error))completion;

/// 发布/撤下群公告（G1，群主/管理员）：text 空即撤下。completion 在主线程回调。
- (void)setGroupAnnouncementWithToken:(NSString *)token
                               convID:(NSString *)convID
                                 text:(NSString *)text
                           completion:(void (^)(NSError *_Nullable error))completion;

/// 群主/管理员自助全员禁言（G1）：until=0 解除 / -1 永久 / 其余到期毫秒时间戳。completion 在主线程回调。
- (void)setGroupMuteWithToken:(NSString *)token
                       convID:(NSString *)convID
                        until:(int64_t)until
                   completion:(void (^)(NSError *_Nullable error))completion;

/// 我在本群的昵称（G1，任意成员）：nickname 空串=清除回退全局昵称。completion 在主线程回调。
- (void)setGroupMyNicknameWithToken:(NSString *)token
                             convID:(NSString *)convID
                           nickname:(NSString *)nickname
                         completion:(void (^)(NSError *_Nullable error))completion;

/// 群治理开关组（G2，群主/管理员整体替换）。completion 在主线程回调。
- (void)setGroupSettingsWithToken:(NSString *)token
                           convID:(NSString *)convID
                     joinApproval:(BOOL)joinApproval
                       permInvite:(BOOL)permInvite
                     permEditInfo:(BOOL)permEditInfo
                          permPin:(BOOL)permPin
                   historyVisible:(BOOL)historyVisible
                       completion:(void (^)(NSError *_Nullable error))completion;

/// 单独禁言成员（G2）：until=0 解禁 / -1 永久 / 其余到期毫秒。completion 在主线程回调。
- (void)muteGroupMemberWithToken:(NSString *)token
                          convID:(NSString *)convID
                          userID:(NSString *)userID
                           until:(int64_t)until
                      completion:(void (^)(NSError *_Nullable error))completion;

/// 移出成员带封禁档（G2）：ban=none|cooldown|forever。completion 在主线程回调。
- (void)removeGroupMemberWithToken:(NSString *)token
                            convID:(NSString *)convID
                            userID:(NSString *)userID
                               ban:(NSString *)ban
                        completion:(void (^)(NSError *_Nullable error))completion;

/// 群黑名单列表（G2，群主/管理员）→ [{user_id,banned_by,banned_at,expires_at}]。completion 在主线程回调。
- (void)groupBansWithToken:(NSString *)token
                    convID:(NSString *)convID
                completion:(void (^)(NSArray<NSDictionary *> *_Nullable bans, NSError *_Nullable error))completion;

/// 解除拉黑（G2，群主/管理员）。completion 在主线程回调。
- (void)unbanGroupMemberWithToken:(NSString *)token
                           convID:(NSString *)convID
                           userID:(NSString *)userID
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

#pragma mark - 二维码体系（QRCODE P0）+ 入群路径（G3）

/// 我的名片码（懒生成，长期有效）→ data 字典 {url, token, expires_at}。completion 在主线程回调。
- (void)qrMyCardWithToken:(NSString *)token
               completion:(void (^)(NSDictionary *_Nullable card, NSError *_Nullable error))completion;

/// 重置名片码（旧码立即失效）→ 同上结构。completion 在主线程回调。
- (void)qrResetMyCardWithToken:(NSString *)token
                    completion:(void (^)(NSDictionary *_Nullable card, NSError *_Nullable error))completion;

/// 群二维码（须成员；perm_invite=1 时仅群主/管理员；7 天复用）→ {url, token, expires_at, inviter}。completion 在主线程回调。
- (void)groupQRWithToken:(NSString *)token convID:(NSString *)convID
              completion:(void (^)(NSDictionary *_Nullable card, NSError *_Nullable error))completion;

/// 重置群码（群主/管理员）。completion 在主线程回调。
- (void)groupQRResetWithToken:(NSString *)token convID:(NSString *)convID
                   completion:(void (^)(NSDictionary *_Nullable card, NSError *_Nullable error))completion;

/// 扫码解析管道：raw=扫到的原文（URL 或裸 token）→ {kind, data}。失效码 error.code=200110。completion 在主线程回调。
- (void)qrResolveWithToken:(NSString *)token raw:(NSString *)raw
                completion:(void (^)(NSDictionary *_Nullable resolved, NSError *_Nullable error))completion;

/// 凭群码入群（code 可为完整 URL 或裸 token）。成功回群资料；需审批时 error.code=300210。completion 在主线程回调。
- (void)joinGroupWithToken:(NSString *)token
                      code:(NSString *)code
                     hello:(NSString *)hello
                completion:(void (^)(IMGroupInfo *_Nullable group, NSError *_Nullable error))completion;

/// 待审入群申请（群主/管理员）→ [{user_id,nickname,avatar_url,hello,status,created_at,...}]。completion 在主线程回调。
- (void)joinRequestsWithToken:(NSString *)token convID:(NSString *)convID
                   completion:(void (^)(NSArray<NSDictionary *> *_Nullable requests, NSError *_Nullable error))completion;

/// 审批一条入群申请（accept=YES→approve / NO→reject）。completion 在主线程回调。
- (void)decideJoinRequestWithToken:(NSString *)token convID:(NSString *)convID
                            userID:(NSString *)userID accept:(BOOL)accept
                        completion:(void (^)(NSError *_Nullable error))completion;

#pragma mark - 扫码登录（QR P1，手机确认端）

/// 手机端已扫登录码：ticket → data {ticket, device, ip, location} 供确认页展示。
/// error.code=200110 表示码已失效。completion 在主线程回调。
- (void)qrLoginScanWithToken:(NSString *)token ticket:(NSString *)ticket
                  completion:(void (^)(NSDictionary *_Nullable info, NSError *_Nullable error))completion;

/// 手机端确认登录（网页版据此换 JWT）。error.code=200110 表示码已过期/被拒。completion 在主线程回调。
- (void)qrLoginConfirmWithToken:(NSString *)token ticket:(NSString *)ticket
                     completion:(void (^)(NSError *_Nullable error))completion;

/// 手机端拒绝登录（"不是我"）。completion 在主线程回调。
- (void)qrLoginRejectWithToken:(NSString *)token ticket:(NSString *)ticket
                    completion:(void (^)(NSError *_Nullable error))completion;

#pragma mark - 已登录设备（多设备管理，QR P2）

/// 本账号全部有效登录会话（本机置顶，在线优先）。completion 在主线程回调。
- (void)devicesWithToken:(NSString *)token
              completion:(void (^)(NSArray<IMDeviceSession *> *_Nullable devices, NSError *_Nullable error))completion;

/// 踢下线某设备（吊销 sid + 断其活连接）。踢本机=退出登录。completion 在主线程回调。
- (void)revokeDeviceWithToken:(NSString *)token sessionID:(NSString *)sessionID
                   completion:(void (^)(NSError *_Nullable error))completion;

/// 退出除本机外的全部设备（当前 sid 由 token 推导，无需入参）。completion 在主线程回调。
- (void)revokeOtherDevicesWithToken:(NSString *)token
                         completion:(void (^)(NSError *_Nullable error))completion;

#pragma mark - 会话管理（M4.5）

/// 读取本人对某会话的会话级设置：GET /api/v1/conversations/{id}/settings →
/// data.{pinned_at,muted,marked_unread,remark}。详情页单会话拉取（免为两个布尔拉整张会话列表）。
- (void)conversationSettingsWithToken:(NSString *)token
                               convID:(NSString *)convID
                           completion:(void (^)(NSDictionary *_Nullable data, NSError *_Nullable error))completion;

/// 设置会话备注（G1，仅本人可见、多端同步）：PUT /api/v1/conversations/{id}/remark。留空即清除。
/// 与设置三开关解耦（各走各的端点，互不覆盖）。completion 主线程回调。
- (void)setConversationRemarkWithToken:(NSString *)token
                                convID:(NSString *)convID
                                remark:(NSString *)remark
                            completion:(void (^)(NSError *_Nullable error))completion;

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
/// fileName/fileSize 仅文件收藏有意义（供收藏页展示与转发保真），非文件传 nil/0。
- (void)addFavoriteWithToken:(NSString *)token
                 contentType:(NSString *)contentType
                     content:(NSString *)content
                     caption:(nullable NSString *)caption
                    fileName:(nullable NSString *)fileName
                    fileSize:(int64_t)fileSize
                    duration:(int64_t)duration
                    waveform:(nullable NSString *)waveform
                       thumb:(nullable NSString *)thumb
                      poster:(nullable NSString *)poster
                      mediaW:(NSInteger)mediaW
                      mediaH:(NSInteger)mediaH
                sourceConvID:(nullable NSString *)sourceConvID
               sourceConvSeq:(int64_t)sourceConvSeq
                  sourceFrom:(nullable NSString *)sourceFrom
                  completion:(void (^)(NSError *_Nullable error))completion;
/// 收藏列表每页条数（滚到底自动加载下一页）。
FOUNDATION_EXPORT const NSInteger IMFavoritesPageSize;

/// 我的收藏列表：GET /api/v1/favorites?limit&offset。返回本页 favorites 数组（原始字典）与**服务端总数**。
///
/// total 用于判断"还有没有下一页"与显示总条数——只按本页条数判断，会在总数恰好是页大小整数倍时
/// 多发一次空请求才知道到底了。老服务端不返回 page 时 total 退化为本页条数（即"就这一页"）。
- (void)favoritesWithToken:(NSString *)token
                    offset:(NSInteger)offset
                completion:(void (^)(NSArray<NSDictionary *> *_Nullable favorites, NSInteger total, NSError *_Nullable error))completion;
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

/// 语音专用上传（voice P0）：multipart POST /api/v1/upload?as=voice。
/// 服务端按 voice 白名单校验（.m4a/.aac/.caf/.opus/.ogg/.webm/.mp4）+ 16MB 上限；
/// 用普通 /upload 传 .mp3 仍映射 file（音乐 ≠ 语音条，语义严格分开）。回调返回 /uploads/<id>.m4a（主线程）。
- (void)uploadVoiceData:(NSData *)data
               fileName:(NSString *)fileName
               mimeType:(NSString *)mimeType
                  token:(NSString *)token
               progress:(nullable void (^)(double fraction))progress
             completion:(void (^)(NSString *_Nullable url, NSError *_Nullable error))completion;

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
