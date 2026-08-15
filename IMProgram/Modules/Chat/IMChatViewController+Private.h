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
@class IMDatabaseAccountContext;
@class IMMentionPickerViewController;
@class IMMessageModel;
@class IMPresence;
@class IMDatabase;

NS_ASSUME_NONNULL_BEGIN

@interface IMChatViewController () <IMSocketManagerDelegate, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate, QLPreviewControllerDataSource, UIContextMenuInteractionDelegate, IMChatBannerStackDelegate>

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
@property (nonatomic, strong) NSTimer *presenceTickTimer; // 在线态定时重算（租约到期无事件，须自己叫醒，见 startPresenceTick）
@property (nonatomic, assign) IMSocketState connState; // 连接态（与在线点共同决定标题）
@property (nonatomic, assign) BOOL didInitialPosition; // 已做进会话定位（只定位一次）
@property (nonatomic, assign) BOOL didInitialSettle;   // 进场动画后已做过一次落定校正（防从子页返回时被强拉贴底）
@property (nonatomic, assign) BOOL needsRowHeightSettle; // 滚动中媒体尺寸落定 → 延迟到滚动停止再重排行高
@property (nonatomic, assign) NSTimeInterval lastTypingSent; // typing 节流
@property (nonatomic, assign) BOOL peerTyping; // 对端 typing 短暂覆盖聊天页副标题
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UITextField *inputField;
@property (nonatomic, strong) NSLayoutConstraint *inputBottom;
@property (nonatomic, strong) UIButton *jumpButton;   // 右下角"↓N"回到最新
@property (nonatomic, strong) UILabel *jumpBadge;     // 按钮上的未读计数（=视口下方未读数）
@property (nonatomic, strong) UIView *inputBar;       // 输入栏容器
@property (nonatomic, strong, nullable) IMMessageModel *replyingTo; // 正在引用回复的目标（M4-2）
@property (nonatomic, strong, nullable) IMMessageModel *editingMessage; // 正在编辑的目标（M4-5）
@property (nonatomic, assign) BOOL selecting;                 // 多选态（#2）
@property (nonatomic, strong, nullable) UIView *selectionBar; // 多选底部工具栏（转发/收藏/删除）
@property (nonatomic, strong, nullable) UIBarButtonItem *savedRightItem; // 多选前的右上按钮，退出恢复
@property (nonatomic, copy, nullable) NSString *savedTitle;   // 多选前标题
@property (nonatomic, strong, nullable) UIView *attachPanel; // 附件面板（M4-6，加号弹出，展开时顶起输入栏、显示在其下方）
@property (nonatomic, assign) BOOL attachPanelVisible;       // 面板是否展开（与键盘互斥，共同决定 inputBottom）
@property (nonatomic, assign) CGFloat kbInset;              // 键盘遮挡输入栏的高度（已减 safeArea），随 keyboardWillChange 更新
@property (nonatomic, strong) UIButton *emojiButton;  // 表情（占位）
@property (nonatomic, strong) UIButton *plusButton;   // 加号（附件面板）
@property (nonatomic, strong) UIButton *sendButton;   // 发送
@property (nonatomic, strong) NSLayoutConstraint *inputTrailToEmoji; // 无内容：输入框贴表情按钮
@property (nonatomic, strong) NSLayoutConstraint *inputTrailToSend;  // 有内容：输入框贴发送按钮
@property (nonatomic, strong) UIView *replyBar;       // 引用预览条（输入栏上方）
@property (nonatomic, strong) UILabel *replyLabel;
@property (nonatomic, strong) UIImageView *replyThumb; // 引用媒体时的小缩略图（#5，图片/视频）
@property (nonatomic, strong) NSLayoutConstraint *replyLabelLeadingNoThumb; // 无缩略图时 label 贴竖条
@property (nonatomic, strong) NSLayoutConstraint *replyLabelLeadingThumb;   // 有缩略图时 label 贴缩略图
@property (nonatomic, strong) NSLayoutConstraint *replyBarHeight;
// 粘贴图片预览条（Telegram 式，#2 重设计）：粘贴不直接发，缩略图 chip 攒在输入栏上方（可多张、逐张 ✕），
// 发送键统一发出（≥2 张成宫格）；与引用条纵向堆叠（引用条在上）。
@property (nonatomic, strong) NSMutableArray<UIImage *> *pendingPasteImages;
@property (nonatomic, strong) UIView *pasteBar;
@property (nonatomic, strong) UIStackView *pasteChipsStack;
@property (nonatomic, strong) NSLayoutConstraint *pasteBarHeight;
// 正在后台解码缩略图的待发件，避免同一行反复触发解码。
@property (nonatomic, strong) NSMutableSet<NSString *> *pendingPreviewLoading;

@end

@class IMDatabase;
@class IMMediaAttributes;
@class IMMenuAction;
@class IMUploadProgress;

/// 长按预览光栅化时按此 tag 临时隐藏高亮蒙层（主实现里定义，+Menu.m 引用）。
FOUNDATION_EXPORT const NSInteger kIMFlashOverlayTag;

/// 附件面板高度（顶起输入栏的量）。+Media.m 里定义，主实现 updateInputBottom 引用。
FOUNDATION_EXPORT const CGFloat kIMAttachPanelHeight;

/// 跨分文件 category 互调的私有方法：主实现与各 category 都 import 本头，故都能看到彼此的私有方法签名。
/// 一个方法只要被**定义它的那个 translation unit 以外**的地方调用，就在此登记（否则 ARC 因不知返回类型报错）。
@interface IMChatViewController (Private)

// —— 主实现文件中、被 category 调用者 ——
// 发件箱缩略/进度（转发自 IMMediaSendService 单例；以 getter 形式暴露，供 cellForRow 等 dot 语法读取）。
- (NSMutableDictionary<NSString *, UIImage *> *)outboxPreviews;
- (NSMutableDictionary<NSString *, IMUploadProgress *> *)outboxProgress;
- (BOOL)performDatabaseOperation:(void (^)(IMDatabase *database))operation;
- (void)appendReloadAndScroll;
- (void)applySelectionStyleForCell:(UITableViewCell *)cell;
- (void)cancelReply;
- (void)favoriteMessage:(IMMessageModel *)message;
- (BOOL)isMediaExpiredForForward:(IMMessageModel *)m;
- (void)refreshUnifiedNavigationBar;
- (NSString *)senderNameForMessage:(IMMessageModel *)m;
- (void)showAttachPanel:(BOOL)visible;

// 长按菜单动作会调进主实现的这些业务方法（+Menu.m → 主实现）：
- (void)beginReplyTo:(IMMessageModel *)message;
- (void)beginEditMessage:(IMMessageModel *)message;
- (void)translateMessage:(IMMessageModel *)message;
- (void)copyMessageToPasteboard:(IMMessageModel *)message;
- (void)forwardMessage:(IMMessageModel *)message;
- (void)cancelPendingMessage:(IMMessageModel *)m;
- (BOOL)canPinMessages;
- (BOOL)isAlbumMember:(IMMessageModel *)m;
- (void)openMemberProfileForUID:(NSString *)uid;
- (void)reportTargetType:(NSString *)targetType targetID:(NSString *)targetID title:(NSString *)title;

// —— +Menu.m 中、被主实现/其它 category 调用者 ——
- (void)attachMessageContextMenuToCell:(UITableViewCell *)cell;
- (NSArray<IMMenuAction *> *)messageActionsForMessage:(IMMessageModel *)message mine:(BOOL)mine;
- (BOOL)canDeleteForEveryone:(IMMessageModel *)message;
- (IMMenuAction *)deleteMenuActionForMessage:(IMMessageModel *)message;
- (void)deleteMessage:(IMMessageModel *)message;
- (void)deleteMessageForEveryone:(IMMessageModel *)message;
- (void)hideMessageForSelf:(IMMessageModel *)message;

// 列表渲染（+DataSource.m）会调进主实现的这些方法：
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
- (NSString *)replyFromNameForUID:(NSString *)uid;
- (IMMessageModel *)messageForClientMsgID:(NSString *)clientMsgID;
- (void)handleSendResult:(BOOL)success convSeq:(int64_t)convSeq error:(nullable NSError *)error forClientMsgID:(NSString *)clientMsgID;
- (void)updateInputBottomAnimated:(BOOL)animated;

// —— +DataSource.m 中、被主实现/其它 category 调用者 ——
- (BOOL)isAlbumFollowerAtRow:(NSInteger)row;
- (NSUInteger)visibleRowForMessage:(IMMessageModel *)m;

// —— +Media.m 中、被主实现/其它 category 调用者 ——
- (void)appendPastedImage:(UIImage *)image;
- (void)refreshPasteBar;
- (void)reattachRunningUploads;
- (void)refreshVisibleCellForMessage:(IMMessageModel *)m;
- (void)updateUploadProgressForMessage:(IMMessageModel *)m;
- (void)uploadAndSendPastedImage:(UIImage *)image groupID:(NSString *)groupID;

// —— +Selection.m 中、被主实现/其它 category 调用者 ——
- (void)enterSelectionWithMessage:(IMMessageModel *)message;
- (void)updateSelectionUI;
- (IMMediaAttributes *)forwardAttributesForMessage:(IMMessageModel *)message;
- (void)forwardEchoContent:(NSString *)content contentType:(NSString *)ct forwardFrom:(NSString *)origin
                  fileName:(nullable NSString *)fileName fileSize:(int64_t)fileSize
                    toConv:(NSString *)convID toUser:(NSString *)toUser;
- (void)forwardEchoContent:(NSString *)content contentType:(NSString *)ct forwardFrom:(NSString *)origin
                  fileName:(nullable NSString *)fileName fileSize:(int64_t)fileSize
                attributes:(nullable IMMediaAttributes *)attributes toConv:(NSString *)convID toUser:(NSString *)toUser;

@end

NS_ASSUME_NONNULL_END
