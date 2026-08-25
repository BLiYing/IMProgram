//  IMChatViewController+Private.h
//  聊天页的**私有类扩展**（原内联在 IMChatViewController.m）。抽到共享私有头后，聊天页的实现可拆成
//  多个分文件 category（+Media / +Menu / +Selection …）共享同一份私有属性与协议声明——纯粹为控制单文件
//  体积与可导航性，不改变类结构：仍是同一个类、同一批方法，只是分散到多个 translation unit。
//
//  约定：跨 category 互调的私有方法在文末 (Private) 分类里声明；ivar 直接访问（_downloads / init /
//  dealloc）只在主实现文件里，category 一律走 self.property 访问器。

#import <UIKit/UIKit.h>
#import <QuickLook/QuickLook.h>
#import "IMChatViewController.h"
#import "IMSocketManager.h"      // IMSocketManagerDelegate / IMSocketState
#import "IMChatBannerStack.h"    // IMChatBannerStackDelegate

#import "IMGroupInfo.h"          // IMGroupInfo / IMGroupRole（senderRoleForMessage: 返回枚举）

@class IMMediaDownloadCoordinator;
@class IMChatSearchState;
@class IMChatSelectionState;
@class IMDatabaseAccountContext;
@class IMMentionPickerViewController;
@class IMMessageModel;
@class IMPresence;
@class IMDatabase;

NS_ASSUME_NONNULL_BEGIN

// 说明：带**必需方法**的协议（UITableViewDataSource / QLPreviewControllerDataSource /
// UIContextMenuInteractionDelegate）的 conformance 不放这里，而是挂到**真正实现其必需方法的那个 category**
// 上（见文末），否则主实现 @implementation 所在 TU 看不到那些方法体、会报 -Wprotocol「does not conform」。
// 这里只留**纯可选方法**协议（无必需方法，不触发该告警）。
@interface IMChatViewController () <IMSocketManagerDelegate, UITableViewDelegate, UITextFieldDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate>

// 指定初始化器收进类扩展（原在 .h）：外部只能走 +openInNavigationController: 统一入口，
// 无法直接 alloc+push，从结构上杜绝绕过导航去重/折叠的回归（曾靠头注释约束、无强制）。
/// host 形如 "localhost:8080"；userID 我方 uid；peerID 对方 uid。readSeq/unread/peerReadSeq 见 +open 文档。
- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID peerID:(NSString *)peerID
                     readSeq:(int64_t)readSeq unread:(NSInteger)unread
                 peerReadSeq:(int64_t)peerReadSeq NS_DESIGNATED_INITIALIZER;
/// 群聊入口：convID=群 topic_id，name 可空（进入后拉群资料刷新）；groupReadSeq=全员已读位点。
- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID
                 groupConvID:(NSString *)convID groupName:(nullable NSString *)name
                     readSeq:(int64_t)readSeq unread:(NSInteger)unread
                groupReadSeq:(int64_t)groupReadSeq;

/// 收到的图片/视频/文件的下载编排（门控态 + 点击路由 + 自动预取，M4-7）。与会话详情页共用同一实现。
@property (nonatomic, strong) IMMediaDownloadCoordinator *downloads;
@property (nonatomic, strong, nullable) NSURL *quickLookURL; // QuickLook 预览中的本地文件
// 长按菜单预览快照：highlight 时光栅化一次并缓存，dismissal 复用同一张（避免菜单存续期间整表 reload
// 后 cell 复用换绑、收起动画截到错误消息/空白）。willEnd 收起动画完成后清空。
@property (nonatomic, strong, nullable) UIImage *cachedMenuSnapshot;
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, strong) IMDatabaseAccountContext *databaseContext;
@property (nonatomic, copy) NSString *peerID;         // 单聊对端 uid；群聊为空串
@property (nonatomic, assign) BOOL isGroupChat;        // YES=群聊（convID 为群 topic_id）
@property (nonatomic, copy, nullable) NSString *groupName;     // 群名（进入时用会话项的，拉到群资料后刷新）
@property (nonatomic, strong, nullable) IMGroupInfo *groupInfo; // 群资料缓存（标题成员数/气泡昵称回退）
// 顶部三横幅栈（G0 置顶 / G1 公告 / G3 入群申请）：视图/布局/高度→内边距/收起持久化全归它，
// 点击导航经 IMChatBannerStackDelegate 回本页处理。进会话拉一次置顶，之后靠 msg_op 帧重拉。
@property (nonatomic, strong, nullable) IMChatBannerStack *bannerStack;
@property (nonatomic, assign) BOOL composerMuteLocked; ///< G2：被禁言（成员级或全员）时锁输入栏
// @提及（M4-8，仅群聊）：候选表 uid→显示名，发送时按输入框里是否还留着 `@显示名` 复核。
@property (nonatomic, strong, nullable) NSMutableDictionary<NSString *, NSString *> *mentionCandidates;
@property (nonatomic, assign) BOOL mentionAllPending; // 已选过 @所有人（仍需文本里留着 token 才生效）
@property (nonatomic, strong, nullable) IMMentionPickerViewController *mentionPanel; // 输入栏上方内联 @面板（child VC）
@property (nonatomic, strong, nullable) NSLayoutConstraint *mentionPanelHeight;
/// 中长文本"展开全文"记忆（按消息 key）：Long 档气泡点击在折叠/展开间切换。
@property (nonatomic, strong) NSMutableSet<NSString *> *expandedTextKeys;
@property (nonatomic, strong) NSMutableArray<IMMessageModel *> *messages;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *seenConvSeqs; // 按 conv_seq 去重，避免推送+同步重复
@property (nonatomic, copy) NSString *convID;
@property (nonatomic, assign) int64_t entryReadSeq;   // 进入前已读位点（定位未读分割线，进会话锁定一次）
@property (nonatomic, assign) NSInteger entryUnread;   // 进入时未读数
@property (nonatomic, assign) int64_t maxReadReported; // 已上报的最大已读 conv_seq（可见即读，单调不回退）
@property (nonatomic, assign) int64_t pendingReadSeq;  // 已滚入视口的最大 conv_seq（节流后上报）
@property (nonatomic, assign) int64_t peerReadSeq;     // 对端已读位点（用于「已读」双勾）
@property (nonatomic, strong) IMPresence *peerPresence; // 对端在线态（快照 + presence 帧增量更新）
@property (nonatomic, strong, nullable) NSTimer *presenceTickTimer; // 在线态定时重算（租约到期无事件，须自己叫醒，见 startPresenceTick）
@property (nonatomic, assign) IMSocketState connState; // 连接态（与在线点共同决定标题）
@property (nonatomic, assign) BOOL didInitialPosition; // 已做进会话定位（只定位一次）
@property (nonatomic, assign) BOOL didInitialSettle;   // 进场动画后已做过一次落定校正（防从子页返回时被强拉贴底）
@property (nonatomic, assign) NSTimeInterval selfSendScrollGuardUntil; ///< 自己发消息触发的贴底动作在此时刻前抑制"↓N"箭头显示（防插入→贴底过渡窗口里 isNearBottom 短暂 false 使箭头闪一下）
@property (nonatomic, assign) BOOL needsRowHeightSettle; // 滚动中媒体尺寸落定 → 延迟到滚动停止再重排行高
@property (nonatomic, assign) NSTimeInterval lastTypingSent; // typing 节流
@property (nonatomic, copy, nullable) NSString *peerTypingUid; // 对端 typing 发送方 uid（覆盖式，最新一位）；空=无人打字。副标题渲染时群聊拼「{昵称} 正在输入」，单聊拼「正在输入」
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UITextField *inputField;
@property (nonatomic, strong) NSLayoutConstraint *inputBottom;
@property (nonatomic, strong) UIButton *jumpButton;   // 右下角"↓N"回到最新
@property (nonatomic, strong) UILabel *jumpBadge;     // 按钮上的未读计数（=视口下方未读数）
@property (nonatomic, strong) UIView *inputBar;       // 输入栏容器
@property (nonatomic, strong, nullable) IMMessageModel *replyingTo; // 正在引用回复的目标（M4-2）
@property (nonatomic, strong, nullable) IMMessageModel *editingMessage; // 正在编辑的目标（M4-5）
@property (nonatomic, assign) BOOL selecting;                 // 多选态（#2）
@property (nonatomic, strong, nullable) UIView *selectionBar; // 多选底部工具栏（转发/收藏/删除；缓存复用，跨进出）
@property (nonatomic, strong, nullable) NSLayoutConstraint *jumpButtonBottom; // 向下钮底边约束：默认贴 replyBar 顶，多选/搜索态贴选择栏/搜索栏顶（堆叠不重叠）
@property (nonatomic, strong, nullable) IMChatSelectionState *selectionState; // 多选态状态袋（逐格勾选集/表底约束/选择栏底边，进入创建退出置 nil，见 IMChatSelectionState.h）
@property (nonatomic, strong, nullable) UIBarButtonItem *savedRightItem; // 多选前的右上按钮，退出恢复
@property (nonatomic, copy, nullable) NSString *savedTitle;   // 多选前标题
@property (nonatomic, strong, nullable) UIView *attachPanel; // 附件面板（M4-6，加号弹出，展开时顶起输入栏、显示在其下方）
@property (nonatomic, assign) BOOL attachPanelVisible;       // 面板是否展开（与键盘互斥，共同决定 inputBottom）
@property (nonatomic, assign) CGFloat kbInset;              // 键盘遮挡输入栏的高度（已减 safeArea），随 keyboardWillChange 更新
// emojiButton 不提为 property（内嵌 inputField.rightView 后无跨 TU 访问，2026-08-25 语音 P1 时去掉）。
@property (nonatomic, strong) UIButton *plusButton;   // 加号（附件面板，左）—— PinnedBanner 会禁用/半透明
@property (nonatomic, strong) UIButton *voiceButton;  // 语音（右，与 sendButton 同槽互斥）
@property (nonatomic, strong) UIButton *sendButton;   // 发送
@property (nonatomic, strong) NSLayoutConstraint *inputTrailToEmoji; // 无内容：输入框贴表情按钮
@property (nonatomic, strong) NSLayoutConstraint *inputTrailToSend;  // 有内容：输入框贴发送按钮
@property (nonatomic, strong) UIView *replyBar;       // 引用预览条（输入栏上方）
@property (nonatomic, strong) UILabel *replyTitleLabel;   // 上行「回复X」/「编辑消息」（accent 色）
@property (nonatomic, strong) UILabel *replySnippetLabel; // 下行内容摘要（secondary 色，单行截断）
@property (nonatomic, strong) UIImageView *replyThumb; // 左侧 36×36 槽：媒体缩略图 / 文件·语音等类型图标
@property (nonatomic, strong) NSLayoutConstraint *replyTextLeadingNoThumb; // 无缩略图/图标时文本堆贴竖条
@property (nonatomic, strong) NSLayoutConstraint *replyTextLeadingThumb;   // 有缩略图/图标时文本堆贴槽位
@property (nonatomic, strong) NSLayoutConstraint *replyBarHeight;
// 粘贴图片预览条（Telegram 式，#2 重设计）：粘贴不直接发，缩略图 chip 攒在输入栏上方（可多张、逐张 ✕），
// 发送键统一发出（≥2 张成宫格）；与引用条纵向堆叠（引用条在上）。
@property (nonatomic, strong) NSMutableArray<UIImage *> *pendingPasteImages;
@property (nonatomic, strong) UIView *pasteBar;
@property (nonatomic, strong) UIStackView *pasteChipsStack;
@property (nonatomic, strong) NSLayoutConstraint *pasteBarHeight;
// 正在后台解码缩略图的待发件，避免同一行反复触发解码。
@property (nonatomic, strong) NSMutableSet<NSString *> *pendingPreviewLoading;
@property (nonatomic, assign) BOOL backBadgeRefreshPending; ///< 返回徽标合并刷新的在途标记（0.12s 窗口内只跑一次）
@property (nonatomic, assign) BOOL readFlushPending;        ///< 已读位点上报的在途标记（0.3s 窗口内只发一次，§8 范式）
@property (nonatomic, copy, nullable) NSString *convRemark; ///< 群会话备注（G1，仅本人可见、多端同步）：非空替代群名作标题

// 会话内搜索（+Search.m）：20 项搜索状态收进协作对象 IMChatSearchState（共享头属性数预算，CODING_STYLE §7）。
// 进入搜索创建、退出置 nil 整体释放；searchState.searching 经 nil 消息天然为 NO。
@property (nonatomic, strong, nullable) IMChatSearchState *searchState;

@end

@class IMDatabase;
@class IMMediaAttributes;
@class IMMenuAction;
@class IMUploadProgress;
@class IMDownloadProgress;

/// 长按预览光栅化时按此 tag 临时隐藏高亮蒙层（主实现里定义，+Menu.m 引用）。
FOUNDATION_EXPORT const NSInteger kIMFlashOverlayTag;

/// 附件面板高度（顶起输入栏的量）。+Media.m 里定义，主实现 updateInputBottom 引用。
FOUNDATION_EXPORT const CGFloat kIMAttachPanelHeight;

/// 跨分文件 category 互调的私有方法：主实现与各 category 都 import 本头，故都能看到彼此的私有方法签名。
/// 一个方法只要被**定义它的那个 translation unit 以外**的地方调用，就在此登记（否则 ARC 因不知返回类型报错）。
/// 下面按**业务概念**粗分组，仅便于查阅；**刻意不标注定义文件**——方法会在 category 间搬家，硬写 +X.m
/// 归属会随之失真（本已发生过：cancelReply/favoriteMessage 搬进 +Compose、showAttachPanel 在 +Media，
/// 旧注释却仍写在「主实现」）。定义位置一律以「跳转到定义」为准。
@interface IMChatViewController (Private)

// 发件箱预览 / 数据库 / 导航栏 / 发送结果等基础能力：
- (NSMutableDictionary<NSString *, UIImage *> *)outboxPreviews;   // 转发自 IMMediaSendService 单例，供 cellForRow dot 语法读取
- (NSMutableDictionary<NSString *, IMUploadProgress *> *)outboxProgress;
- (BOOL)performDatabaseOperation:(void (^)(IMDatabase *database))operation;
- (void)appendReloadAndScroll;
- (void)applySelectionStyleForCell:(UITableViewCell *)cell;
- (void)buildReplyBar;
- (void)cancelReply;
- (void)replyBarTapped;
- (void)favoriteMessage:(IMMessageModel *)message;
- (BOOL)isMediaExpiredForForward:(IMMessageModel *)m;
- (void)refreshUnifiedNavigationBar;
- (NSString *)senderNameForMessage:(IMMessageModel *)m;
- (void)showAttachPanel:(BOOL)visible;
- (void)handleSendResult:(BOOL)success convSeq:(int64_t)convSeq error:(nullable NSError *)error forClientMsgID:(NSString *)clientMsgID;

// 引用 / 编辑 / 翻译 / 收藏 / 复制 / 转发 / 删除等消息动作：
- (void)beginReplyTo:(IMMessageModel *)message;
- (void)beginEditMessage:(IMMessageModel *)message;
- (void)cancelEdit;
- (void)translateMessage:(IMMessageModel *)message;
- (void)copyMessageToPasteboard:(IMMessageModel *)message;
- (void)forwardMessage:(IMMessageModel *)message;
/// 相册查看器/媒体库视角的转发：与气泡长按 forwardMessage: 语义相同，但**不带**源消息的 caption/mentions。
/// 全屏媒体视角下用户看不到 caption（气泡下方那段附言不在视野内），透传反而把原发件人当时的
/// 「@xxx 附言」意外带到目标会话（对齐资料页文件 tab forwardFileMessage: 的取舍）。
- (void)forwardMediaFromViewerMessage:(IMMessageModel *)message;
- (void)cancelPendingMessage:(IMMessageModel *)m;
- (BOOL)canPinMessages;
- (BOOL)isAlbumMember:(IMMessageModel *)m;
- (void)openMemberProfileForUID:(NSString *)uid;
- (void)reportTargetType:(NSString *)targetType targetID:(NSString *)targetID title:(NSString *)title;

// 长按菜单：构建 / 删除路径：
- (void)attachMessageContextMenuToCell:(UITableViewCell *)cell;
- (NSArray<IMMenuAction *> *)messageActionsForMessage:(IMMessageModel *)message mine:(BOOL)mine;
- (BOOL)canDeleteForEveryone:(IMMessageModel *)message;
- (IMMenuAction *)deleteMenuActionForMessage:(IMMessageModel *)message;
- (void)deleteMessage:(IMMessageModel *)message;
- (void)deleteMessageForEveryone:(IMMessageModel *)message;
- (void)hideMessageForSelf:(IMMessageModel *)message;

// 顶部三横幅栈（G0 置顶 / G1 公告 / G2 禁言锁 / G3 入群申请，+PinnedBanner.m）：主实现与 +Menu 互调：
- (void)reloadPinnedBanner;
- (NSInteger)approvalPendingCount;
- (void)maybeAutoPopAnnouncement;
- (void)refreshComposerMuteState;
// 群聊 M3-5（+Group.m）：reloadGroupInfo 被 +PinnedBanner 入群审批回调调；loadConvRemark 被主实现
// viewDidLoad 调；onGroupEvent:/onConvUpdatedForRemark: 由 viewDidLoad @selector 接线：
- (void)reloadGroupInfo;
- (void)loadConvRemark;
- (void)onConvUpdatedForRemark:(NSNotification *)note;
- (void)onGroupEvent:(NSNotification *)note;

// 右上圆头像按钮 / 资料页入口（+Nav.m）：安装钮由主实现与 reloadGroupInfo 调，头像点击 selector 需可见：
- (void)installInfoAvatarButtonWithURL:(nullable NSString *)url seed:(NSString *)seed
                                  name:(nullable NSString *)name action:(SEL)action;
- (void)groupInfoTapped;
- (void)singleInfoTapped;

// 列表渲染 / 相册聚簇：cell 取数、发送者身份、媒体门控、行布局：
- (BOOL)isFirstInSenderRun:(NSInteger)row;
- (BOOL)isLastInSenderRun:(NSInteger)row;
- (NSInteger)firstUnreadRow;
- (BOOL)isNearBottom;
- (void)scrollToAbsoluteBottom;
- (void)refreshRowHeightsWithoutAnimation;
- (void)updateSendButtonVisibility;
- (void)openChatRecord:(IMMessageModel *)message;
- (void)openLink:(NSString *)urlString;
- (void)sendFriendRequestFromRejectedNote;
- (NSString *)senderAvatarURLForMessage:(IMMessageModel *)m;
- (IMGroupRole)senderRoleForMessage:(IMMessageModel *)m;
- (NSString *)fullMediaURL:(NSString *)content;
- (UIImage *)pendingPreviewForMessage:(IMMessageModel *)m;
- (void)handlePendingMediaTap:(IMMessageModel *)m;
- (void)presentMediaViewerForMessage:(IMMessageModel *)m preloaded:(nullable UIImage *)image;
- (BOOL)isTextExpandedForMessage:(IMMessageModel *)m;
- (NSDictionary<NSString *, NSString *> *)mentionMapForMessage:(IMMessageModel *)m;
- (NSDictionary<NSString *, NSString *> *)mentionMapForCaption:(IMMessageModel *)m; // 图说 caption 的 @高亮映射
- (NSString *)replyFromNameForUID:(NSString *)uid;
- (IMMessageModel *)messageForClientMsgID:(NSString *)clientMsgID;
- (BOOL)isAlbumFollowerAtRow:(NSInteger)row;
- (NSUInteger)visibleRowForMessage:(IMMessageModel *)m;
- (NSArray<IMMessageModel *> *)albumMembersForGroupID:(NSString *)gid; // 多选态整组勾选展开用（Selection 调）

// 滚动 / 键盘 / 进会话定位 / 已读上报 / 在线态：
- (void)updateInputBottomAnimated:(BOOL)animated;
- (void)runAfterKeyboardHidden:(void (^)(void))block;
- (void)scrollToBottomAnimated:(BOOL)animated;
- (void)markVisibleRowsRead;
- (void)flushReadPosition;               // +Position.m；主实现 viewWillDisappear 退出前同步落已读（节流窗口未到也保证不丢）
- (void)positionInitialIfNeeded;
- (void)anchorRowToTop:(NSInteger)row;   // +Position.m；主实现 viewDidAppear 落定校正也调
- (void)refreshPeerPresence;
- (void)updatePeerWatch:(BOOL)watch;
- (void)startPresenceTick;   // +Presence.m；主实现生命周期 viewWillAppear/viewWillDisappear 调
- (void)stopPresenceTick;
- (void)observeKeyboard;
- (void)updateJumpButton;

// 下载编排回调：
- (void)updateDownloadProgressForMessage:(IMMessageModel *)m state:(IMDownloadProgress *)state;
- (void)refreshRowForMessage:(IMMessageModel *)m;

// 附件面板 / 粘贴图 / 上传回填：
- (void)appendPastedImage:(UIImage *)image;
- (void)refreshPasteBar;
- (void)reattachRunningUploads;
- (void)refreshVisibleCellForMessage:(IMMessageModel *)m;
- (void)updateUploadProgressForMessage:(IMMessageModel *)m;
- (void)uploadAndSendPastedImage:(UIImage *)image groupID:(NSString *)groupID;
- (void)uploadAndSendPastedImage:(UIImage *)image groupID:(nullable NSString *)groupID
                         caption:(nullable NSString *)caption mentions:(nullable NSArray<NSString *> *)mentions mentionAll:(BOOL)mentionAll; // 图说合并发送

// 标题 / 排序（socket 回调广泛调用）：
- (void)updateTitle;
- (void)sortMessagesInPlace;

// @提及：面板与发送前的 token 解析（sendTapped 在 +Compose，发送时回调这些解析本条 mentions）：
- (void)maybePresentMentionPicker;
- (void)dismissMentionPanel;
- (NSArray<NSString *> *)resolvedMentionsInText:(NSString *)text;
- (BOOL)resolvedMentionAllInText:(NSString *)text;
- (void)clearPendingMentions;

// 文本发送（发送按钮 / 回车触发；主实现 setupUI 接线，textFieldShouldReturn 也调）：
- (void)sendTapped;

// 多选 / 转发：
- (void)enterSelectionWithMessage:(IMMessageModel *)message;
- (void)toggleAlbumMemberSelection:(IMMessageModel *)member; // 相册逐格勾选切换（2a，DataSource 的格点击块调）
- (void)extendTableBottomForSelection; // 多选期间壁纸铺到底（Search 退出时若仍在多选需接管调用）
- (void)updateSelectionBarBottomAnchor; // 选择栏底边随搜索态重定位（Search 进/出时若在多选需重排堆叠）
- (void)updateJumpButtonBottomAnchor;   // 向下钮底边随 多选/搜索 态重定位（堆叠不重叠、间距一致）
- (void)updateSelectionUI;
- (IMMediaAttributes *)forwardAttributesForMessage:(IMMessageModel *)message stripCaption:(BOOL)stripCaption;
- (void)forwardEchoContent:(NSString *)content contentType:(NSString *)ct forwardFrom:(NSString *)origin
                  fileName:(nullable NSString *)fileName fileSize:(int64_t)fileSize
                    toConv:(NSString *)convID toUser:(NSString *)toUser;
- (void)forwardEchoContent:(NSString *)content contentType:(NSString *)ct forwardFrom:(NSString *)origin
                  fileName:(nullable NSString *)fileName fileSize:(int64_t)fileSize
                attributes:(nullable IMMediaAttributes *)attributes toConv:(NSString *)convID toUser:(NSString *)toUser;

// 常驻发送服务通知（IMMediaSendService 发件箱对账 / msg_op 应用 / 徽标节流，+SendService.m）：
// 主实现 viewDidLoad 用 @selector 接线故需在此可见；refreshBackUnreadBadge 另被 viewWillAppear 直接调。
- (void)onMediaSendCancelled:(NSNotification *)note;
- (void)onMediaSendProgress:(NSNotification *)note;
- (void)onMediaSendMetaChanged:(NSNotification *)note;
- (void)onMediaSendDispatched:(NSNotification *)note;
- (void)onMediaSendFailed:(NSNotification *)note;
- (void)onMediaSendAck:(NSNotification *)note;
- (void)onConversationCleared:(NSNotification *)note;
- (void)appearanceChanged;
- (void)onMsgOpApplied:(NSNotification *)note;
- (void)onMsgOpRejected:(NSNotification *)note;
- (void)onMessageRemoved:(NSNotification *)note;
- (void)scheduleBackUnreadBadgeRefresh;
- (void)refreshBackUnreadBadge;

// target-action 选择器：主实现 setupUI 用 @selector(...) 接线，方法体在各 category（+Media/+Scroll/+MediaFlow），
// 在此登记让主 TU 见到声明（否则 -Wundeclared-selector）：
- (void)handleReplyJumpTap:(UITapGestureRecognizer *)gr;
- (void)voiceTapped;
- (void)emojiTapped;
- (void)toggleAttachPanel;
- (void)jumpTapped;
@end

// 带必需方法的协议 conformance 挂在实现其必需方法的 category 上（避免主 TU 的 -Wprotocol）：
// 声明放在共享私有头，让赋值点（如主实现 setupUI 的 tableView.dataSource=self）也看得到 conformance。
/// UITableViewDataSource 必需的 numberOfRowsInSection / cellForRowAtIndexPath 都在 +DataSource.m。
@interface IMChatViewController (DataSource) <UITableViewDataSource>
@end
/// QLPreviewControllerDataSource 必需的两个方法与 ql.dataSource=self 赋值都在 +MediaFlow.m。
@interface IMChatViewController (MediaFlow) <QLPreviewControllerDataSource>
@end
/// UIContextMenuInteractionDelegate 必需的 configurationForMenuAtLocation 与 initWithDelegate:self 都在 +Menu.m。
@interface IMChatViewController (Menu) <UIContextMenuInteractionDelegate>
@end
/// IMChatBannerStackDelegate 的 5 个方法均为**必需**（无 @optional），实现全在 +PinnedBanner.m，故 conformance
/// 挂这里而非类扩展（否则主 @implementation 所在 TU 看不到方法体，报 -Wprotocol「does not conform」）。
@interface IMChatViewController (PinnedBanner) <IMChatBannerStackDelegate>
@end

NS_ASSUME_NONNULL_END
