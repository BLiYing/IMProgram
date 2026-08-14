//  IMChatViewController.m

#import "IMChatViewController.h"
#import "IMMainTabBarController.h" // im_refreshNavigationBar / kIMLiquidBarHeight
#import "IMChatBackgroundView.h"
#import "IMAlbumCell.h"
#import "IMBubbleCell.h"
#import "IMChatRecordCell.h"
#import "IMImageCell.h"
#import "IMLinkCardCell.h"
#import "IMSystemCell.h"
#import "IMSocketManager.h"
#import "IMHTTPService.h"
#import "IMConversation.h"
#import "IMImageLoader.h"
#import "IMVideoThumbnailLoader.h"
#import "IMMediaPlaceholder.h"   // 引用缩略 / 媒体库统一门控取图（真帧>thumb磨砂>图标）
#import "IMMediaViewerViewController.h"
#import "IMMediaPagerViewController.h"
#import "IMTextReaderViewController.h" // 超长文本全屏阅读器
#import "IMConversationMediaViewController.h"
#import "IMQRResultRouter.h" // 层3：本站邀请链接（/q/u、/q/g）App 内拦截走原生流程
#import "IMForwardPickerViewController.h"
#import "IMChatRecordViewController.h"
#import "IMMentionPickerViewController.h"
#import "IMReadReceiptViewController.h"
#import "IMMediaPicker.h"
#import "IMMediaExpiryRegistry.h" // 转发/保存失效守卫：曾可用媒体被服务端清理(404)→转出去对端必 404
#import "IMMediaUtil.h"
#import "IMMediaDownloadCoordinator.h" // 下载编排（门控/进度/落地，与详情页共用）
#import "IMDownloadProgress.h"
#import <QuickLook/QuickLook.h>
#import "IMPendingMediaStore.h"
#import "IMChunkedUploader.h"
#import "IMMediaSendService.h"
#import "UILabel+IMAvatar.h"
#import "IMFilePickerViewController.h"
#import "IMUserCard.h"
#import "IMGroupInfo.h"
#import "IMGroupInfoViewController.h"
#import "IMChatDetailViewController.h"
#import "IMGroupTextViewController.h"
#import "IMJoinRequestsViewController.h"
#import "IMProtocol.h"
#import "IMMessageModel.h"
#import "IMUploadProgress.h"
#import "IMDatabase.h"
#import "IMMenuAction.h"
#import "IMPinnedBannerView.h"
#import "IMPinnedMessage.h"
#import "UIViewController+IMToast.h"
#import "UIViewController+IMDeleteSheet.h" // 两档删除 sheet（与详情页共用）
#import "IMTheme.h"
#import "IMAppearance.h"
#import "IMLog.h"
#import "IMGlass.h"
#import <Photos/Photos.h>
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <SafariServices/SafariServices.h>
#import "IMPopoverCard.h"

NSNotificationName const IMChatConversationClearedNotification = @"IMChatConversationClearedNotification";

#pragma mark - 引用/预览媒体占位辅助（M4-2 / #5）

/// 媒体消息在「引用/预览」场景的简短占位（本地生成，用于输入预览条与本端即时快照）。
static NSString *IMReplySnippet(IMMessageModel *m) {
    if ([m.contentType isEqualToString:@"image"]) { return @"[图片]"; }
    if ([m.contentType isEqualToString:@"video"]) { return @"[视频]"; }
    if ([m.contentType isEqualToString:@"file"]) {
        NSString *fn = m.fileName.length > 0 ? m.fileName : IMMediaFileName(m.content);
        return fn.length > 0 ? [@"[文件] " stringByAppendingString:fn] : @"[文件]";
    }
    if ([m.contentType isEqualToString:@"chat_record"]) { return IMChatRecordSnippet(m.content); } // [聊天记录] 标题
    NSString *c = m.content ?: @"";
    return c.length > 60 ? [[c substringToIndex:60] stringByAppendingString:@"…"] : c;
}

#define IMFileNameFromContent(c) IMMediaFileName(c)
#define IMLooksLikeURL(s) IMMediaLooksLikeURL(s)
#pragma mark - 支持粘贴图片的输入框（#2）

/// UITextField 默认不接受图片粘贴；剪贴板有图片时放开 paste 菜单并回调图片（文本粘贴走原生路径）。
@interface IMPasteImageTextField : UITextField
@property (nonatomic, copy, nullable) void (^onPasteImage)(UIImage *image);
@end

@implementation IMPasteImageTextField
- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    if (action == @selector(paste:) && UIPasteboard.generalPasteboard.hasImages) { return YES; }
    return [super canPerformAction:action withSender:sender];
}
- (void)paste:(id)sender {
    if (UIPasteboard.generalPasteboard.hasImages) {
        UIImage *img = UIPasteboard.generalPasteboard.image;
        if (img && self.onPasteImage) { self.onPasteImage(img); return; }
    }
    [super paste:sender];
}
@end

#pragma mark - 聊天页

/// 本地待发文件的缩略图（在后台队列调用）：视频抽首帧，图片按目标尺寸降采样，绝不整图解码。
static UIImage *IMPendingVideoThumbnail(NSString *path) {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
    AVAssetImageGenerator *gen = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    gen.appliesPreferredTrackTransform = YES;
    gen.maximumSize = CGSizeMake(600, 600);
    CGImageRef cg = [gen copyCGImageAtTime:CMTimeMakeWithSeconds(0.1, 600) actualTime:NULL error:NULL];
    if (!cg) { return nil; }
    UIImage *thumb = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    return thumb;
}

/// 该 content_type 是否计入未读——**与服务端 conversation.unreadCount 同口径**（M4-8）：
/// `msg_op` 事件行（撤回/编辑/置顶）是操作、`system` 系统消息（改名/入群/禁言）是群内留痕，
/// 两者都不是"有人跟我说话了"，均不计未读。未读分割线与 ↓N 的定位必须照此排除，
/// 否则分割线会落在不计数的行上、与角标数字对不上。
/// 文本里是否存在一个**完整的** `@名字` token（M4-8）。
///
/// 必须按 token 边界判定、不能用裸 containsString:：昵称互为前缀时（「小美」/「小美丽」），
/// `@小美丽 开会` 会把根本没被提及的「小美」也算进 mentions，让他收到一条穿透免打扰的错误强提醒。
/// 判定规则：token 后面必须紧跟**空白或字符串结尾**。与 Web `containsMentionToken` 同一套。
BOOL IMChatTextContainsMentionToken(NSString *_Nullable text, NSString *_Nullable displayName) {
    if (text.length == 0 || displayName.length == 0) { return NO; }
    NSString *needle = [@"@" stringByAppendingString:displayName];
    NSUInteger from = 0;
    while (from <= text.length - MIN(text.length, 1)) {
        NSRange scan = NSMakeRange(from, text.length - from);
        if (scan.length < needle.length) { return NO; }
        NSRange hit = [text rangeOfString:needle options:0 range:scan];
        if (hit.location == NSNotFound) { return NO; }
        NSUInteger after = hit.location + hit.length;
        if (after >= text.length) { return YES; } // 到结尾即完整 token
        unichar next = [text characterAtIndex:after];
        if ([NSCharacterSet.whitespaceAndNewlineCharacterSet characterIsMember:next]) { return YES; }
        from = hit.location + 1; // 命中的是更长名字的前缀，继续往后找
    }
    return NO;
}

BOOL IMContentTypeCountsAsUnread(NSString *_Nullable contentType) {
    NSString *ct = contentType ?: @"";
    return !([ct isEqualToString:@"system"] || [ct isEqualToString:@"msg_op"]);
}

static UIImage *IMPendingImageThumbnail(NSString *path) {
    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
    if (!src) { return nil; }
    CGImageRef cg = CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)@{
        (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (id)kCGImageSourceShouldCacheImmediately: @YES,
        (id)kCGImageSourceThumbnailMaxPixelSize: @(1024),
    });
    CFRelease(src);
    if (!cg) { return nil; }
    UIImage *thumb = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    return thumb;
}

@interface IMChatViewController () <IMSocketManagerDelegate, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate, QLPreviewControllerDataSource>

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
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, strong) IMDatabaseAccountContext *databaseContext;
@property (nonatomic, copy) NSString *peerID;         // 单聊对端 uid；群聊为空串
@property (nonatomic, assign) BOOL isGroupChat;        // YES=群聊（convID 为群 topic_id）
@property (nonatomic, copy, nullable) NSString *groupName;     // 群名（进入时用会话项的，拉到群资料后刷新）
@property (nonatomic, strong, nullable) IMGroupInfo *groupInfo; // 群资料缓存（标题成员数/气泡昵称回退）
// 置顶消息横幅（G0）：进会话拉一次，之后靠 msg_op 帧重拉。pinnedIndex=横幅当前显示第几条（点条轮转）。
@property (nonatomic, strong, nullable) IMPinnedBannerView *pinnedBanner;
@property (nonatomic, strong) NSArray<IMPinnedMessage *> *pinnedItems;
@property (nonatomic, assign) NSInteger pinnedIndex;
@property (nonatomic, strong, nullable) NSLayoutConstraint *pinnedBannerHeight;
// 群公告横幅（G1）：黄条，排在置顶横幅之上（优先级 公告 > 置顶）。文本随群资料下发。
@property (nonatomic, strong, nullable) IMPinnedBannerView *announcementBanner;
@property (nonatomic, strong, nullable) NSLayoutConstraint *announcementBannerHeight;
@property (nonatomic, copy, nullable) NSString *announcementText;
// 入群申请横幅（G3，仅群主/管理员）：蓝条，置于最顶，pending_count>0 才显。点=进审批列表。
@property (nonatomic, strong, nullable) IMPinnedBannerView *approvalBanner;
@property (nonatomic, strong, nullable) NSLayoutConstraint *approvalBannerHeight;
// 横幅本地收起（✕，非破坏性）持久化到 NSUserDefaults（键含 userID+convID，退出重进/换账号均正确）：
// 记「收起时的内容签名」，签名一致才隐藏；内容变化（新置顶/改公告/申请数变）签名变→自动复现。见 bannerDismissKey:。
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

@implementation IMChatViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID peerID:(NSString *)peerID
                     readSeq:(int64_t)readSeq unread:(NSInteger)unread peerReadSeq:(int64_t)peerReadSeq {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.hidesBottomBarWhenPushed = YES; // 进聊天页隐藏底部 TabBar（push 时全屏）
        _host = [host copy];
        _userID = [userID copy];
        _peerID = [peerID copy];
        _convID = IMConversationID(userID, peerID);
        IMDatabaseAccountContext *context = IMDatabase.sharedDatabase.currentAccountContext;
        if (![context.ownerUserID isEqualToString:userID]) {
            IMLogDatabase(@"聊天页账号与当前数据库上下文不一致 page_uid=%@ db_uid=%@",
                          userID, context.ownerUserID ?: @"(none)");
        }
        _databaseContext = [context.ownerUserID isEqualToString:userID] ? context : nil;
        _entryReadSeq = readSeq;
        _entryUnread = unread;
        _peerReadSeq = peerReadSeq;   // 进会话即用服务端已知对端已读位点播种（实时回执再往上推进）
        _maxReadReported = readSeq;   // 已读起点=进入前位点，仅在可见消息超过它时才上报
        _pendingReadSeq = readSeq;
        // 本地落库：进入即秒显历史。
        __block NSArray<IMMessageModel *> *cachedMessages = @[];
        [IMDatabase.sharedDatabase performWithAccountContext:_databaseContext block:^(IMDatabase *database) {
            cachedMessages = [database messagesForConv:_convID];
        }];
        _messages = [cachedMessages mutableCopy];
        _seenConvSeqs = [NSMutableSet set];
        for (IMMessageModel *m in _messages) {
            if (m.convSeq > 0) { [_seenConvSeqs addObject:@(m.convSeq)]; }
        }
        _pendingPreviewLoading = [NSMutableSet set];
    }
    return self;
}

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID
                 groupConvID:(NSString *)convID groupName:(NSString *)name
                     readSeq:(int64_t)readSeq unread:(NSInteger)unread
                groupReadSeq:(int64_t)groupReadSeq {
    // 复用单聊指定初始化器（peerID 空），再覆写会话标识为群 topic_id。
    // 群聊没有单一对端，用「全员已读位点」播种 peerReadSeq：仅当 conv_seq ≤ 该位点（人人都读过）
    // 才显绿✓✓（双勾语义在群里的诚实版）。非实时——didReadConv 群聊分支直接 return，不靠回执推进。
    self = [self initWithHost:host userID:userID peerID:@"" readSeq:readSeq unread:unread peerReadSeq:groupReadSeq];
    if (self) {
        _isGroupChat = YES;
        _groupName = [name copy];
        _convID = [convID copy];
        // 指定初始化器按 IMConversationID(uid,"") 预载了错误会话，这里按群 convID 重载本地历史。
        __block NSArray<IMMessageModel *> *cachedMessages = @[];
        [IMDatabase.sharedDatabase performWithAccountContext:_databaseContext block:^(IMDatabase *database) {
            cachedMessages = [database messagesForConv:convID];
        }];
        _messages = [cachedMessages mutableCopy];
        [_seenConvSeqs removeAllObjects];
        for (IMMessageModel *m in _messages) {
            if (m.convSeq > 0) { [_seenConvSeqs addObject:@(m.convSeq)]; }
        }
    }
    return self;
}

#pragma mark - 统一进会话入口（导航去重 + 折叠）

/// 计算「打开新聊天页」后的目标导航栈：截掉栈中**最底部**的聊天页及其之上的所有页（资料页等），
/// 把新聊天页接到它原来的位置——于是同一栈内至多一个聊天页，从聊天页返回直达其下方（通常是会话列表）。
/// 栈中无聊天页时即等价普通 push（返回原栈 + 新页）。isChatController 判定某页是否聊天页
/// （生产传 isKindOfClass:IMChatViewController；单测可注入假谓词，故抽为文件级纯函数便于回归）。
NSArray<UIViewController *> *IMChatCollapsedStack(NSArray<UIViewController *> *stack,
                                                 UIViewController *newChat,
                                                 BOOL (^isChatController)(UIViewController *vc)) {
    NSUInteger cut = NSNotFound;
    for (NSUInteger i = 0; i < stack.count; i++) {
        if (isChatController(stack[i])) { cut = i; break; }
    }
    NSMutableArray<UIViewController *> *result = [NSMutableArray array];
    [result addObjectsFromArray:(cut == NSNotFound ? stack : [stack subarrayWithRange:NSMakeRange(0, cut)])];
    if (newChat) { [result addObject:newChat]; }
    return result;
}

+ (nullable instancetype)existingChatForConvID:(NSString *)convID
                        inNavigationController:(nullable UINavigationController *)nav {
    if (convID.length == 0 || !nav) { return nil; }
    for (UIViewController *vc in nav.viewControllers.reverseObjectEnumerator) {
        if ([vc isKindOfClass:IMChatViewController.class]
            && [((IMChatViewController *)vc).convID isEqualToString:convID]) {
            return (IMChatViewController *)vc;
        }
    }
    return nil;
}

/// 统一去重/折叠核心：命中同会话则 pop 复用并刷新；否则折叠中间聊天页后落新页。
/// build 造新实例；seed 播种显示字段（复用与新建都调用，故对既有实例只覆盖 caller 提供的非空值，
/// 不清空已有好值）。位点参数（readSeq/unread/peerReadSeq…）在复用路径刻意忽略：旧实例自维护已读
/// 与位点，prepareForReuseEntry 会重锚到底部并标已读，比用可能过期的入参覆盖更可靠。
+ (nullable instancetype)openConvID:(NSString *)convID
              inNavigationController:(UINavigationController *)nav
                               build:(IMChatViewController *(^)(void))build
                                seed:(void (^)(IMChatViewController *chat))seed {
    if (!nav || convID.length == 0) { return nil; }
    IMChatViewController *existing = [self existingChatForConvID:convID inNavigationController:nav];
    if (existing) {
        seed(existing);
        [existing prepareForReuseEntry];
        [nav popToViewController:existing animated:YES];
        return existing;
    }
    IMChatViewController *chat = build();
    seed(chat);
    NSArray<UIViewController *> *target = IMChatCollapsedStack(nav.viewControllers, chat,
                                                              ^BOOL(UIViewController *vc) {
        return [vc isKindOfClass:IMChatViewController.class];
    });
    // 无聊天页可折叠 → 走标准 push（保留系统入场动画/手势）；否则整体替换栈（新页在顶，push 式动画）。
    if (target.count == nav.viewControllers.count + 1) {
        [nav pushViewController:chat animated:YES];
    } else {
        [nav setViewControllers:target animated:YES];
    }
    return chat;
}

+ (nullable instancetype)openInNavigationController:(nullable UINavigationController *)nav
                                               host:(NSString *)host
                                             userID:(NSString *)userID
                                             peerID:(NSString *)peerID
                                            readSeq:(int64_t)readSeq
                                             unread:(NSInteger)unread
                                        peerReadSeq:(int64_t)peerReadSeq
                                       peerNickname:(NSString *)peerNickname
                                      peerAvatarURL:(NSString *)peerAvatarURL {
    if (!nav || peerID.length == 0) { return nil; }
    return [self openConvID:IMConversationID(userID, peerID) inNavigationController:nav build:^{
        return [[self alloc] initWithHost:host userID:userID peerID:peerID
                                  readSeq:readSeq unread:unread peerReadSeq:peerReadSeq];
    } seed:^(IMChatViewController *chat) {
        if (peerNickname.length > 0) { chat.peerNickname = peerNickname; }
        if (peerAvatarURL.length > 0) { chat.peerAvatarURL = peerAvatarURL; }
    }];
}

+ (nullable instancetype)openInNavigationController:(nullable UINavigationController *)nav
                                               host:(NSString *)host
                                             userID:(NSString *)userID
                                        groupConvID:(NSString *)convID
                                          groupName:(NSString *)name
                                            readSeq:(int64_t)readSeq
                                             unread:(NSInteger)unread
                                       groupReadSeq:(int64_t)groupReadSeq
                                     groupAvatarURL:(NSString *)groupAvatarURL {
    if (!nav || convID.length == 0) { return nil; }
    return [self openConvID:convID inNavigationController:nav build:^{
        return [[self alloc] initWithHost:host userID:userID groupConvID:convID groupName:name
                                  readSeq:readSeq unread:unread groupReadSeq:groupReadSeq];
    } seed:^(IMChatViewController *chat) {
        if (name.length > 0) { chat.groupName = name; }              // 修：旧实例群名不再被丢弃
        if (groupAvatarURL.length > 0) { chat.groupAvatarURL = groupAvatarURL; }
    }];
}

/// 复用已在栈中的旧实例前的刷新：①按最新播种值重装标题/头像按钮（否则 seed 落在无人再读的属性上）；
/// ②从库合并被压期间（尤其跨 Tab、别的聊天页占用 delegate 时）错过的消息，修复内存空洞；
/// ③清定位标志，让 pop 回来时像重新进入一样重锚到底部/未读，而非停在旧滚动位。
- (void)prepareForReuseEntry {
    if (self.isViewLoaded) {
        [self refreshDisplayIdentity];
        [self mergeMissedMessagesFromStore];
    }
    self.didInitialPosition = NO;
    self.didInitialSettle = NO;
}

/// 按当前 peer*/group* 值重装标题与右上头像按钮（viewDidLoad 与复用刷新共用同一口径，避免漂移）。
- (void)refreshDisplayIdentity {
    [self updateTitle];
    if (self.isGroupChat) {
        [self installInfoAvatarButtonWithURL:self.groupAvatarURL seed:self.convID name:self.groupName action:@selector(groupInfoTapped)];
    } else {
        NSString *name = self.peerNickname.length ? self.peerNickname : self.peerID;
        [self installInfoAvatarButtonWithURL:self.peerAvatarURL seed:self.peerID name:name action:@selector(singleInfoTapped)];
    }
}

/// 从 SQLite 合并本会话里内存尚无的消息（按 conv_seq 去重，保留未上号的乐观发件 conv_seq==0）。
/// 仅在检测到落后时调用，避免每次 appear 全量重排。返回是否有新增。
- (BOOL)mergeMissedMessagesFromStore {
    NSString *convID = self.convID;
    __block NSArray<IMMessageModel *> *dbMessages = @[];
    if (![self performDatabaseOperation:^(IMDatabase *database) {
        dbMessages = [database messagesForConv:convID];
    }]) { return NO; }
    BOOL added = NO;
    for (IMMessageModel *m in dbMessages) {
        if (m.convSeq <= 0 || [self.seenConvSeqs containsObject:@(m.convSeq)]) { continue; }
        [self.seenConvSeqs addObject:@(m.convSeq)];
        [self.messages addObject:m];
        added = YES;
    }
    if (!added) { return NO; }
    [self sortMessagesInPlace];
    [self.tableView reloadData];
    return YES;
}

/// 内存里已上号消息的最大 conv_seq（乐观发件 conv_seq==0 不计）。用于与 DB synced 游标比对判断是否落后。
- (int64_t)maxInMemoryConvSeq {
    int64_t maxSeq = 0;
    for (IMMessageModel *m in self.messages) {
        if (m.convSeq > maxSeq) { maxSeq = m.convSeq; }
    }
    return maxSeq;
}

- (BOOL)performDatabaseOperation:(void (^)(IMDatabase *database))operation {
    return [IMDatabase.sharedDatabase performWithAccountContext:self.databaseContext block:operation];
}

// 待发预览/进度归常驻发送服务持有（key=clientMsgID 全局唯一）：页面销毁重建后引用即接上状态。
- (NSMutableDictionary<NSString *, UIImage *> *)outboxPreviews { return IMMediaSendService.shared.previews; }
- (NSMutableDictionary<NSString *, IMUploadProgress *> *)outboxProgress { return IMMediaSendService.shared.progressMap; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    // 标题 + 右上头像按钮：与复用刷新共用 refreshDisplayIdentity 同一口径（列表透传的头像立即显真图、
    // 免闪首字母；群资料加载后再由 reloadGroupInfo 补正）。
    [self refreshDisplayIdentity];
    if (self.isGroupChat) {
        [self reloadGroupInfo];
        // 群变更（邀请/移除/退群/转让/改名）→ 刷新标题/群资料；被移出 → 提示并退出本页。
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onGroupEvent:)
                                                   name:IMSocketDidReceiveGroupEventNotification object:nil];
    }
    [self setupUI];
    [self reloadPinnedBanner]; // 置顶横幅（G0）：进会话拉一次，之后靠 msg_op 帧增量维护，不轮询
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appearanceChanged)
                                               name:IMAppearanceDidChangeNotification object:nil];
    [self observeKeyboard];
    // 消息操作（撤回/编辑/置顶，M4）：应用到本会话某条 → 就地刷新；我方操作被拒（超窗）→ 吐司。
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onMsgOpApplied:)
                                               name:IMSocketDidApplyMsgOpNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onMsgOpRejected:)
                                               name:IMSocketDidRejectMsgOpNotification object:nil];
    // 任务2：消息被物理移除（为所有人删除 / 仅为我删除）→ 本会话则从列表删掉该条。
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onMessageRemoved:)
                                               name:IMSocketDidRemoveMessageNotification object:nil];
    // 任务2：返回按钮全局未读徽标——其它会话来新消息 / 已读位点变化时刷新数字（本会话已排除，不受影响）。
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshBackUnreadBadge)
                                               name:IMSocketDidReceiveMessageNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshBackUnreadBadge)
                                               name:IMSocketDidReceiveReadNotification object:nil];
    // 资料页清空聊天记录 → 本会话清空内存并刷新（否则返回聊天页仍显旧消息）。
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onConversationCleared:)
                                               name:IMChatConversationClearedNotification object:nil];
    // 媒体/文件发送全程活在 IMMediaSendService（退出本页不中断）；本页只订阅它的通知渲染进度与结果。
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onMediaSendProgress:)
                                               name:IMMediaSendProgressDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onMediaSendMetaChanged:)
                                               name:IMMediaSendMetaDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onMediaSendDispatched:)
                                               name:IMMediaSendDidDispatchNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onMediaSendFailed:)
                                               name:IMMediaSendDidFailNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onMediaSendAck:)
                                               name:IMMediaSendAckNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onMediaSendCancelled:)
                                               name:IMMediaSendDidCancelNotification object:nil];
}

/// 用户取消发送：服务已删库行与本地副本，本页移除这行气泡。
- (void)onMediaSendCancelled:(NSNotification *)note {
    if (![self mediaSendNoteIsMine:note]) { return; }
    NSString *key = note.userInfo[kIMMediaSendClientMsgIDKey];
    IMMessageModel *mine = [self messageForClientMsgID:key];
    if (!mine) { return; }
    [self.messages removeObjectIdenticalTo:mine];
    [self.tableView reloadData];
}

#pragma mark - 常驻发送服务通知

/// userInfo 里的 convID 是否本会话。
- (BOOL)mediaSendNoteIsMine:(NSNotification *)note {
    return [note.userInfo[kIMMediaSendConvIDKey] isEqualToString:self.convID];
}

/// 按 clientMsgID 找本页消息模型（服务实例与本页实例可能不是同一个对象——重进会话后本页持有的是
/// 从库里读出的副本）。
- (IMMessageModel *)messageForClientMsgID:(NSString *)clientMsgID {
    if (clientMsgID.length == 0) { return nil; }
    for (IMMessageModel *m in self.messages) {
        if ([m.clientMsgID isEqualToString:clientMsgID]) { return m; }
    }
    return nil;
}

- (void)onMediaSendProgress:(NSNotification *)note {
    if (![self mediaSendNoteIsMine:note]) { return; }
    IMMessageModel *m = [self messageForClientMsgID:note.userInfo[kIMMediaSendClientMsgIDKey]];
    if (!m) { return; }
    if ([m.contentType isEqualToString:@"file"]) {
        // 文件气泡：圆环/状态行/文案随 configure 一次性布好，整行重渲染。
        // reload 若引起行高微变（如状态行出现/消失）会把底部顶走——原本贴底则重新贴底
        //（与 MetaChanged/Ack 回调对称；已精确贴底时 scrollToAbsoluteBottom 首轮即返回，无额外开销）。
        BOOL wasNearBottom = [self isNearBottom];
        [self refreshVisibleCellForMessage:m];
        if (wasNearBottom) { [self scrollToAbsoluteBottom]; }
    } else {
        [self updateUploadProgressForMessage:m]; // 只改覆盖层/环 strokeEnd，不 reload（无闪烁）
    }
}

/// 元数据/缩略图就绪：气泡从方形占位切到真实比例，行高变化后若原本贴底则重新贴底
/// （否则内容会被顶出屏幕，看起来像"列表突然滚动了一下"）。
- (void)onMediaSendMetaChanged:(NSNotification *)note {
    if (![self mediaSendNoteIsMine:note]) { return; }
    IMMessageModel *m = [self messageForClientMsgID:note.userInfo[kIMMediaSendClientMsgIDKey]];
    if (!m) { return; }
    BOOL wasNearBottom = [self isNearBottom];
    [self refreshVisibleCellForMessage:m];
    [self refreshRowHeightsWithoutAnimation];
    if (wasNearBottom) { [self scrollToAbsoluteBottom]; }
}

/// 上传完成、消息已发出、库里已换真实 ID：把本页模型同步过去（若持有的是旧副本）。
- (void)onMediaSendDispatched:(NSNotification *)note {
    if (![self mediaSendNoteIsMine:note]) { return; }
    IMMessageModel *serviceModel = note.userInfo[kIMMediaSendMessageKey];
    NSString *oldKey = note.userInfo[kIMMediaSendOldClientMsgIDKey];
    IMMessageModel *mine = [self messageForClientMsgID:oldKey] ?: [self messageForClientMsgID:serviceModel.clientMsgID];
    if (!mine) { return; }
    if (mine != serviceModel) {
        // 本页持有库副本：用服务实例整体替换（后续 ack/刷新都以它为准），避免两份模型漂移。
        NSUInteger idx = [self.messages indexOfObjectIdenticalTo:mine];
        if (idx != NSNotFound) { [self.messages replaceObjectAtIndex:idx withObject:serviceModel]; }
    }
    // 上传完成瞬间气泡内容切换（文件行状态区收敛、媒体角标变化）可能微调行高：原本贴底则重新贴底。
    BOOL wasNearBottom = [self isNearBottom];
    [self refreshVisibleCellForMessage:serviceModel];
    if (wasNearBottom) { [self scrollToAbsoluteBottom]; }
}

- (void)onMediaSendFailed:(NSNotification *)note {
    if (![self mediaSendNoteIsMine:note]) { return; }
    IMMessageModel *m = [self messageForClientMsgID:note.userInfo[kIMMediaSendClientMsgIDKey]];
    if (!m) { return; }
    m.status = IMMessageStatusFailed; // 服务实例已置位；本页若持有库副本在此对齐
    [self updateUploadProgressForMessage:m];
    [self refreshVisibleCellForMessage:m];
    [self im_showToast:@"发送失败，点击可重试"];
}

/// 服务端 ack（状态/conv_seq/note 已由服务落库）：只更新内存模型与界面。
- (void)onMediaSendAck:(NSNotification *)note {
    if (![self mediaSendNoteIsMine:note]) { return; }
    IMMessageModel *serviceModel = note.userInfo[kIMMediaSendMessageKey];
    IMMessageModel *mine = [self messageForClientMsgID:serviceModel.clientMsgID];
    if (!mine) { return; }
    BOOL wasNearBottom = [self isNearBottom];
    if (mine != serviceModel) {
        mine.status = serviceModel.status;
        mine.convSeq = serviceModel.convSeq;
        mine.note = serviceModel.note;
        mine.noteCode = serviceModel.noteCode; // 随 note 一起拷：决定系统行给不给恢复入口（200103 → 发好友申请）
    }
    if (mine.convSeq > 0) { [self.seenConvSeqs addObject:@(mine.convSeq)]; } // 防 sync 重复回显自己发的
    // 相册成员的 ACK 只定点刷宫格角标/状态胶囊；但**被拒收挂了系统行时行高会变**，
    // 定点刷新不重算高度（系统行会被裁掉），必须整表 reload 走下面的分支。
    if (mine.groupID.length > 0 && mine.note.length == 0) {
        [self refreshVisibleCellForMessage:mine];
        return;
    }
    [self.tableView reloadData];
    if (wasNearBottom) { [self scrollToBottomAnimated:YES]; } // 被拒收挂系统行后仍贴底可见
}

/// 会话历史被清空（资料页操作）：本会话则清空内存消息 + 刷新表。
- (void)onConversationCleared:(NSNotification *)note {
    if (![note.userInfo[kIMConvIDKey] isEqualToString:self.convID]) { return; }
    [self.messages removeAllObjects];
    [self.tableView reloadData];
}

/// 外观设置实时生效：刷新壁纸、消息 Cell、输入框与当前主题色，不需要重新进入聊天。
- (void)appearanceChanged {
    self.view.tintColor = IMTheme.accent;
    self.inputBar.backgroundColor = IMTheme.surface;
    self.inputField.backgroundColor = IMTheme.pageBackground;
    self.inputField.font = [UIFont systemFontOfSize:MAX(15, IMTheme.chatFontSize - 1)];
    self.inputField.layer.cornerRadius = IMAppearance.shared.bubbleRadius;
    self.inputField.layer.borderColor =
        [IMTheme.separator resolvedColorWithTraitCollection:self.traitCollection].CGColor;
    if ([self.tableView.backgroundView isKindOfClass:IMChatBackgroundView.class]) {
        [(IMChatBackgroundView *)self.tableView.backgroundView refreshAppearance];
    }
    [self.tableView reloadData];
}

/// 消息操作应用到某条消息：本会话则就地更新内存模型 + 刷新（撤回→墓碑，编辑→改文本）。
- (void)onMsgOpApplied:(NSNotification *)note {
    NSString *convID = note.userInfo[kIMConvIDKey];
    if (![convID isEqualToString:self.convID]) { return; }
    int64_t target = [note.userInfo[kIMMsgOpTargetSeqKey] longLongValue];
    NSString *op = note.userInfo[kIMMsgOpKey];
    NSString *newContent = note.userInfo[kIMMsgOpContentKey];
    int64_t nowMs = (int64_t)([NSDate date].timeIntervalSince1970 * 1000);
    for (IMMessageModel *m in self.messages) {
        if (m.convSeq != target) { continue; }
        if ([op isEqualToString:kIMMsgOpRecall]) { m.recalledAt = nowMs; }
        else if ([op isEqualToString:kIMMsgOpEdit]) { m.editedAt = nowMs; if (newContent) { m.content = newContent; } }
        else if ([op isEqualToString:kIMMsgOpPin]) {
            // 取消置顶与置顶共用 op=pin，必须看 pinned 标志（缺省视为置顶，兼容老服务端）。
            id flag = note.userInfo[kIMMsgOpPinnedKey];
            BOOL pinned = ![flag respondsToSelector:@selector(boolValue)] || [flag boolValue];
            m.pinnedAt = pinned ? nowMs : 0;
        }
        break;
    }
    [self.tableView reloadData];
    if ([op isEqualToString:kIMMsgOpPin]) { [self reloadPinnedBanner]; } // 含别人置顶/取消的实时同步
}

/// 我方发起的操作被拒（如撤回超时）：吐司提示（不改消息）。
- (void)onMsgOpRejected:(NSNotification *)note {
    NSString *msg = note.userInfo[@"message"];
    [self im_showToast:msg.length > 0 ? msg : @"操作失败"];
}

/// 任务2：某条消息被物理移除（为所有人删除 / 仅为我删除）→ 本会话则从消息列表删掉并刷新。
- (void)onMessageRemoved:(NSNotification *)note {
    NSString *convID = note.userInfo[kIMConvIDKey];
    if (![convID isEqualToString:self.convID]) { return; }
    int64_t target = [note.userInfo[kIMMsgOpTargetSeqKey] longLongValue];
    if (target <= 0) { return; }
    NSUInteger idx = NSNotFound;
    for (NSUInteger i = 0; i < self.messages.count; i++) {
        if (self.messages[i].convSeq == target) { idx = i; break; }
    }
    if (idx == NSNotFound) { return; }
    [self.messages removeObjectAtIndex:idx];
    [self.tableView reloadData];
    [self reloadPinnedBanner]; // 删掉的可能正是一条置顶消息，别让横幅指向已消失的消息
}

/// 任务2：刷新返回按钮的全局未读总数徽标（各会话 unread 之和，排除当前会话，微信式）。
- (void)refreshBackUnreadBadge {
    __block NSInteger total = 0;
    [self performDatabaseOperation:^(IMDatabase *database) {
        total = [database totalUnreadExcludingConv:self.convID];
    }];
    [self im_setBackBadgeCount:total];
}

#pragma mark - 群聊（M3-5）

/// 拉群资料：标题成员数 / 气泡昵称回退 / 群资料页数据源。best-effort。
- (void)reloadGroupInfo {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService groupInfoWithToken:token convID:self.convID completion:^(IMGroupInfo *group, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !group) { return; }
        self.groupInfo = group;
        self.groupName = group.name;
        [self updateTitle];
        // 群头像加载后刷新右上圆按钮。
        [self installInfoAvatarButtonWithURL:group.avatarURL seed:self.convID name:group.name action:@selector(groupInfoTapped)];
        self.announcementText = group.announcement.length ? group.announcement : nil; // G1 公告横幅
        [self applyAnnouncementBanner];
        [self applyApprovalBanner]; // G3：群主/管理员待审入群申请横幅
        [self maybeAutoPopAnnouncement]; // 进群/新版本自动弹一次公告卡（每版一次）
        [self refreshComposerMuteState]; // G2：被禁言则锁输入栏
        [self.tableView reloadData]; // 昵称回退可能变化（老消息无 from_nickname 时用成员表）
    }];
}

#pragma mark - 置顶消息横幅（G0）

/// 能否置顶：群内读 `perm_pin`——开(YES)=仅群主/管理员，关(NO)=全员可置顶（对齐服务端 hub.go 校验）；单聊任一方可。
- (BOOL)canPinMessages {
    if (!self.isGroupChat) { return YES; }
    if (!self.groupInfo.permPin) { return YES; } // 群主关闭「仅管理员可置顶」→ 全员可置顶
    return self.groupInfo.myRole == IMGroupRoleOwner || self.groupInfo.myRole == IMGroupRoleAdmin;
}

/// 重拉本会话置顶集合并刷新横幅。best-effort：拉不到就不显，绝不打断聊天。
- (void)reloadPinnedBanner {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0 || self.convID.length == 0) { return; }
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService pinnedMessagesWithToken:token convID:self.convID
                                             completion:^(NSArray<IMPinnedMessage *> *items, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || error) { return; }
        self.pinnedItems = items ?: @[];
        [self applyPinnedBanner];
    }];
}

/// 置顶横幅「内容签名」（条数 + 首条 conv_seq）：收起态按此记忆，签名变化即视为新内容、自动复现。
/// 收起处与刷新处共用同一算法，避免两处格式串分叉。
- (nullable NSString *)currentPinnedSig {
    NSInteger total = (NSInteger)self.pinnedItems.count;
    return total > 0 ? [NSString stringWithFormat:@"%ld:%lld", (long)total, (long long)self.pinnedItems.firstObject.convSeq] : nil;
}

/// 横幅收起状态的 NSUserDefaults 键：含 userID + convID，换账号/换会话互不影响。
- (NSString *)bannerDismissKey:(NSString *)kind {
    return [NSString stringWithFormat:@"im_banner_dismiss_%@_%@_%@", kind, self.userID ?: @"", self.convID ?: @""];
}

/// 把当前 pinnedItems/pinnedIndex 应用到横幅，并同步 tableView 顶部内边距。
- (void)applyPinnedBanner {
    NSInteger total = (NSInteger)self.pinnedItems.count;
    // 别人取消置顶会让列表变短，旧索引可能越界（横幅空白）→ 夹紧回 0。
    if (self.pinnedIndex < 0 || self.pinnedIndex >= total) { self.pinnedIndex = 0; }
    IMPinnedMessage *shown = total > 0 ? self.pinnedItems[self.pinnedIndex] : nil;
    // 收起态持久化：仅当当前内容签名与"收起时记下的签名"一致才隐藏；新置顶签名不同 → 自动复现。
    NSString *sig = [self currentPinnedSig];
    NSString *dismissedSig = [NSUserDefaults.standardUserDefaults stringForKey:[self bannerDismissKey:@"pin"]];
    if (sig.length > 0 && [sig isEqualToString:dismissedSig]) { shown = nil; }
    [self.pinnedBanner applyItem:shown index:self.pinnedIndex total:total isGroup:self.isGroupChat];
    self.pinnedBannerHeight.constant = shown ? [IMPinnedBannerView bannerHeight] : 0;
    [self updateBannerInset];
}

/// 应用群公告横幅（G1）：文本非空则显黄条。
- (void)applyAnnouncementBanner {
    NSString *text = self.announcementText;
    NSString *dismissedText = [NSUserDefaults.standardUserDefaults stringForKey:[self bannerDismissKey:@"ann"]];
    NSString *shownText = (text.length > 0 && [text isEqualToString:dismissedText]) ? nil : text; // 公告改了→签名不同→复现
    [self.announcementBanner applyAnnouncement:shownText];
    self.announcementBannerHeight.constant = shownText.length ? [IMPinnedBannerView bannerHeight] : 0;
    [self updateBannerInset];
}

/// 三条横幅（申请 + 公告 + 置顶）叠加后的总高，顶开消息表内容。放一处算，避免各方法各自覆盖 inset.top。
- (void)updateBannerInset {
    CGFloat top = self.approvalBannerHeight.constant + self.announcementBannerHeight.constant + self.pinnedBannerHeight.constant;
    UIEdgeInsets inset = self.tableView.contentInset;
    if (inset.top == top) { return; }
    inset.top = top;
    self.tableView.contentInset = inset;
}

/// 入群申请横幅（G3）：仅群主/管理员且 pending_count>0 才显。放在 reloadGroupInfo 后刷新（帧到达也走那条路）。
- (void)applyApprovalBanner {
    BOOL canManage = self.groupInfo.myRole == IMGroupRoleOwner || self.groupInfo.myRole == IMGroupRoleAdmin;
    NSInteger pending = (self.isGroupChat && canManage) ? self.groupInfo.pendingCount : 0;
    NSInteger dismissedCount = [NSUserDefaults.standardUserDefaults integerForKey:[self bannerDismissKey:@"approval"]];
    NSInteger shownPending = (pending > 0 && pending == dismissedCount) ? 0 : pending; // 申请数变→复现
    [self.approvalBanner applyApprovalCount:shownPending];
    self.approvalBannerHeight.constant = shownPending > 0 ? [IMPinnedBannerView bannerHeight] : 0;
    [self updateBannerInset];
}

/// 点入群申请横幅：进审批列表（同意/拒绝后回调重拉，角标随之更新）。
- (void)approvalBannerTapped {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    __weak typeof(self) ws = self;
    IMJoinRequestsViewController *vc = [[IMJoinRequestsViewController alloc] initWithToken:token convID:self.convID
                                                                                onChanged:^{ [ws reloadGroupInfo]; }];
    [self.navigationController pushViewController:vc animated:YES];
}

/// 进群/新版本自动弹一次公告卡（sketch §02②，决策 16）：`announcementAt` 比本地记录新才弹，每版一次。
/// 本地按 convID 存 last-seen（NSUserDefaults）；弹过即记录本版，之后 reloadGroupInfo 再进来不重复弹。
- (void)maybeAutoPopAnnouncement {
    NSString *text = self.announcementText;
    int64_t at = self.groupInfo.announcementAt;
    if (text.length == 0 || at <= 0) { return; }
    NSString *key = [NSString stringWithFormat:@"im_ann_seen_%@", self.convID ?: @""];
    int64_t seen = (int64_t)[NSUserDefaults.standardUserDefaults doubleForKey:key];
    if (at <= seen) { return; }
    // 仅在本页可见且无其他弹层时弹（被详情页盖住/已有 sheet 时先不弹，下次可见再弹）。
    if (self.navigationController.topViewController != self || self.presentedViewController != nil) { return; }
    [NSUserDefaults.standardUserDefaults setDouble:(double)at forKey:key];
    NSString *sub = [IMGroupTextViewController announceSubtitleForMillis:at];
    [IMGroupTextViewController presentFrom:self title:@"群公告" subtitle:sub body:text];
}

/// 点公告横幅：**直接开公告全文视图**（决策 16，不再跳群资料页——旧实现跳过去详情页却没公告卡，等于点了看不到）。
- (void)announcementBannerTapped {
    NSString *text = self.announcementText;
    if (text.length == 0) { return; }
    NSString *sub = [IMGroupTextViewController announceSubtitleForMillis:self.groupInfo.announcementAt];
    [IMGroupTextViewController presentFrom:self title:@"群公告" subtitle:sub body:text];
}

/// G2 输入栏禁言锁：成员级禁言(myMuteUntil)或全员禁言(且我是普通成员)时禁用输入并改占位文案。
/// 服务端仍是权威（发上来照样拒 300208/300206），这里只是提前告知、不给试错。
- (void)refreshComposerMuteState {
    if (!self.isGroupChat || !self.groupInfo) {
        if (self.composerMuteLocked) { [self setComposerLocked:NO reason:nil]; }
        return;
    }
    int64_t now = (int64_t)([NSDate date].timeIntervalSince1970 * 1000);
    BOOL memberMuted = self.groupInfo.myMuteUntil > now;
    BOOL allMuted = self.groupInfo.muteUntil > now && self.groupInfo.myRole == IMGroupRoleMember;
    NSString *reason = memberMuted ? @"你已被管理员禁言" : (allMuted ? @"本群已开启全员禁言" : nil);
    [self setComposerLocked:(reason != nil) reason:reason];
}

- (void)setComposerLocked:(BOOL)locked reason:(nullable NSString *)reason {
    self.composerMuteLocked = locked;
    self.inputField.enabled = !locked;
    self.inputField.placeholder = locked ? reason : @"输入消息…";
    if (locked) { [self.inputField resignFirstResponder]; }
}

/// 点横幅：跳到当前那条，并轮转到下一条（Telegram 式）。
- (void)pinnedBannerTapped {
    NSInteger total = (NSInteger)self.pinnedItems.count;
    if (total == 0) { return; }
    IMPinnedMessage *shown = self.pinnedItems[MIN(MAX(self.pinnedIndex, 0), total - 1)];
    [self jumpToConvSeq:shown.convSeq];
    self.pinnedIndex = (self.pinnedIndex + 1) % total;
    [self applyPinnedBanner];
}

/// 点右侧列表键：半屏列出全部置顶消息，点行跳转；有权限者可就地取消置顶。
- (void)pinnedBannerListTapped {
    if (self.pinnedItems.count == 0) { return; }
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"置顶消息"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) ws = self;
    BOOL canPin = [self canPinMessages];
    for (IMPinnedMessage *item in self.pinnedItems) {
        NSString *sender = [item senderLabelForGroup:self.isGroupChat];
        NSString *title = sender.length > 0
            ? [NSString stringWithFormat:@"%@：%@", sender, item.previewText]
            : item.previewText;
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            [ws jumpToConvSeq:item.convSeq];
        }]];
    }
    if (canPin) {
        IMPinnedMessage *shown = self.pinnedItems[MIN(MAX(self.pinnedIndex, 0), (NSInteger)self.pinnedItems.count - 1)];
        [sheet addAction:[UIAlertAction actionWithTitle:@"取消置顶当前这条" style:UIAlertActionStyleDestructive
                                               handler:^(UIAlertAction *action) {
            [IMSocketManager.sharedManager pinMessageInConv:(ws.convID ?: @"")
                                              targetConvSeq:shown.convSeq pinned:NO];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.pinnedBanner;
    sheet.popoverPresentationController.sourceRect = self.pinnedBanner.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

/// 右上圆头像按钮（单聊对方 / 群聊群头像），点击进资料页。
/// 44pt 官方 Glass 按钮直接承接点击和系统按压动画，内部 30pt 头像严格裁圆。
static UIImage *IMChatAvatarImage(UIImage *photo, NSString *seed, NSString *name, CGFloat diameter) {
    CGSize size = CGSizeMake(diameter, diameter);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    UIImage *avatar = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGRect rect = (CGRect){CGPointZero, size};
        UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:rect];
        [circle addClip];
        if (photo) {
            CGFloat scale = MAX(diameter / photo.size.width, diameter / photo.size.height);
            CGSize drawSize = CGSizeMake(photo.size.width * scale, photo.size.height * scale);
            CGRect drawRect = CGRectMake((diameter - drawSize.width) / 2,
                                         (diameter - drawSize.height) / 2,
                                         drawSize.width, drawSize.height);
            [photo drawInRect:drawRect];
        } else {
            [[IMTheme avatarColorForSeed:seed] setFill];
            UIRectFill(rect);
            NSString *display = name.length ? name : seed;
            display = display.length >= 2 ? [display substringFromIndex:display.length - 2] : display;
            NSDictionary *attrs = @{
                NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold],
                NSForegroundColorAttributeName: UIColor.whiteColor,
            };
            CGSize textSize = [display sizeWithAttributes:attrs];
            [display drawAtPoint:CGPointMake((diameter - textSize.width) / 2,
                                             (diameter - textSize.height) / 2) withAttributes:attrs];
        }
    }];
    // 导航项图片默认会被当成模板图着色，真实头像因此可能变成透明/纯色；头像必须保留原始像素。
    return [avatar imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

- (void)refreshUnifiedNavigationBar {
    [self im_refreshNavigationBar];
}

- (void)installInfoAvatarButtonWithURL:(nullable NSString *)url seed:(NSString *)seed
                                  name:(nullable NSString *)name action:(SEL)action {
    // 内圈头像直径。外圈=标题栏 44pt 玻璃圆钮；间隔/侧 = (44 - avatarD)/2。
    // 30→间隔 7pt；37→间隔 3.5pt（间隔减半）。想更贴边继续调大（≤44）。
    CGFloat avatarD = 37;
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:IMChatAvatarImage(nil, seed, name, avatarD)
                                                              style:UIBarButtonItemStylePlain
                                                             target:self action:action];
    item.accessibilityLabel = name.length ? [NSString stringWithFormat:@"%@的聊天详情", name] : @"聊天详情";
    self.navigationItem.rightBarButtonItem = item;
    [self refreshUnifiedNavigationBar];

    NSString *full = url.length ? [self fullMediaURL:url] : @"";
    if (full.length) {
        __weak UIBarButtonItem *weakItem = item;
        [[IMImageLoader shared] loadImageURL:full completion:^(UIImage *i) {
            if (!i) { return; }
            dispatch_async(dispatch_get_main_queue(), ^{
                UIBarButtonItem *barItem = weakItem;
                if (barItem) {
                    barItem.image = IMChatAvatarImage(i, seed, name, avatarD);
                    [self refreshUnifiedNavigationBar];
                }
            });
        }];
    }
}

- (void)groupInfoTapped {
    IMChatDetailViewController *detail = [[IMChatDetailViewController alloc] initGroupWithHost:self.host
                                                                                       userID:self.userID
                                                                                       convID:self.convID
                                                                                    groupName:self.groupName
                                                                               groupAvatarURL:self.groupInfo.avatarURL];
    [self.navigationController pushViewController:detail animated:YES];
}

/// 单聊右上信息 → 资料页（透传对端昵称/头像；备注名优先本地覆盖，由资料页读取）。
- (void)singleInfoTapped {
    IMChatDetailViewController *detail = [[IMChatDetailViewController alloc] initSingleWithHost:self.host
                                                                                        userID:self.userID
                                                                                        peerID:self.peerID
                                                                                  peerNickname:self.peerNickname
                                                                                 peerAvatarURL:self.peerAvatarURL];
    [self.navigationController pushViewController:detail animated:YES];
}

/// 点群聊气泡对方头像 → 进该成员资料页（复用单聊右上头像同一逻辑，微信式；showsMessagePill 显「消息」入口）。
- (void)openMemberProfileForUID:(NSString *)uid {
    if (uid.length == 0 || [uid isEqualToString:self.userID]) { return; }
    NSString *nick = [self.groupInfo nicknameOfMember:uid];
    IMChatDetailViewController *vc = [[IMChatDetailViewController alloc] initSingleWithHost:self.host userID:self.userID
                                                                                    peerID:uid
                                                                              peerNickname:(nick.length ? nick : uid)
                                                                             peerAvatarURL:[self.groupInfo avatarURLOfMember:uid]];
    vc.showsMessagePill = YES;
    [self.navigationController pushViewController:vc animated:YES];
}

/// 点拒收系统行的「发送好友申请」（非好友 200103 的恢复入口，微信式）。
/// 服务端 Request 对「我侧陈旧 accepted」已放行（单向删除后被删方的唯一恢复路径）。
- (void)sendFriendRequestFromRejectedNote {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0 || self.peerID.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService requestFriendWithToken:token peerID:self.peerID
                                             completion:^(BOOL becameFriend, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) { [self im_showToast:error.localizedDescription ?: @"好友申请发送失败"]; return; }
        // 已直接成为好友（对方仍视我为好友）→ 不说"已发送申请"（会误导要等对方通过），直接告知可继续聊。
        [self im_showToast:becameFriend ? @"已重新成为好友" : @"已发送好友申请"];
    }];
}

/// 群变更事件：本群则刷新资料；自己被移出 → 提示并退出本页。
- (void)onGroupEvent:(NSNotification *)note {
    NSString *convID = note.userInfo[kIMConvIDKey];
    if (![convID isEqualToString:self.convID]) { return; }
    NSString *event = note.userInfo[kIMGroupEventKey];
    NSString *target = note.userInfo[kIMGroupTargetKey];
    // 被移出（remove 且 target=自己）或群被解散（dissolve，管理端处置，对全体生效）→ 提示并退出本页。
    BOOL removedMe = [event isEqualToString:@"remove"] && [target isEqualToString:self.userID];
    BOOL dissolved = [event isEqualToString:@"dissolve"];
    if (removedMe || dissolved) {
        [self im_showToast:dissolved ? @"该群已被解散" : @"你已被移出群聊"];
        // 先让吐司可见，再退出本页（随页面销毁，故略作停留）。
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf.navigationController popViewControllerAnimated:YES];
        });
        return;
    }
    [self reloadGroupInfo];
}

/// 群聊气泡发送者昵称：优先消息自带 from_nickname，其次群成员表，最后 uid。
- (NSString *)senderNameForMessage:(IMMessageModel *)m {
    if (m.fromNickname.length > 0) { return m.fromNickname; }
    NSString *nick = [self.groupInfo nicknameOfMember:m.from];
    return nick.length > 0 ? nick : (m.from ?: @"");
}

/// 群聊发送者在本群的角色（气泡群主/管理员徽标用）：**优先本群成员表的当前角色**（晋升/降级后老消息随之
/// 变化，微信式）；成员表里查不到该成员（未加载/发送者已退群）时，回退消息自带 `from_role`（服务端仅对
/// 群主/管理员冗余下发）兜底。都拿不到则 IMGroupRoleMember（不显徽标）。
- (IMGroupRole)senderRoleForMessage:(IMMessageModel *)m {
    for (IMGroupMember *mem in self.groupInfo.members) {
        if ([mem.userID isEqualToString:m.from]) { return mem.role; } // 成员表当前角色优先
    }
    return IMGroupRoleFromString(m.fromRole); // 兜底：发送时点角色（脏值/空→member）
}

/// 引用条被引用者显示名（群聊用）：自己→"你"，否则群成员昵称→uid。协议只下发 uid，昵称本地解析。
- (NSString *)replyFromNameForUID:(NSString *)uid {
    if (uid.length == 0) { return nil; }
    if ([uid isEqualToString:self.userID]) { return @"你"; }
    NSString *nick = [self.groupInfo nicknameOfMember:uid];
    return nick.length > 0 ? nick : uid;
}

/// 群聊发送者头像绝对 URL（无则空串——头像圈回退首字母）。相对路径补 host。
- (NSString *)senderAvatarURLForMessage:(IMMessageModel *)m {
    NSString *url = [self.groupInfo avatarURLOfMember:m.from];
    return url.length > 0 ? [self fullMediaURL:url] : @"";
}

#pragma mark - Telegram 式连续消息分组（同发送者连续段：名字只显首条、头像贴末条）

/// 上一「可见行」（跳过相册零高从行）；无则 -1。
- (NSInteger)prevVisibleRow:(NSInteger)row {
    for (NSInteger j = row - 1; j >= 0; j--) {
        if ([self isAlbumFollowerAtRow:j]) { continue; }
        return j;
    }
    return -1;
}

/// 下一「可见行」（跳过相册零高从行）；无则 messages.count。
- (NSInteger)nextVisibleRow:(NSInteger)row {
    for (NSInteger j = row + 1; j < (NSInteger)self.messages.count; j++) {
        if ([self isAlbumFollowerAtRow:j]) { continue; }
        return j;
    }
    return (NSInteger)self.messages.count;
}

/// 两条消息是否属于同一「连续段」：同发送者、都是普通气泡（非系统/撤回）、同一天。
- (BOOL)message:(IMMessageModel *)a sameSenderRunAs:(IMMessageModel *)b {
    if (![a.from isEqualToString:b.from]) { return NO; }
    if ([a.contentType isEqualToString:@"system"] || [b.contentType isEqualToString:@"system"]) { return NO; }
    if (a.recalledAt != 0 || b.recalledAt != 0) { return NO; }
    if (a.timestamp > 0 && b.timestamp > 0 && ![IMTheme isMillis:a.timestamp sameDayAsMillis:b.timestamp]) { return NO; }
    return YES;
}

/// 该行是否为连续段首条（对方群消息用；决定是否显示发送者名）。
- (BOOL)isFirstInSenderRun:(NSInteger)row {
    NSInteger p = [self prevVisibleRow:row];
    if (p < 0) { return YES; }
    return ![self message:self.messages[(NSUInteger)p] sameSenderRunAs:self.messages[(NSUInteger)row]];
}

/// 该行是否为连续段末条（对方群消息用；决定是否显示头像）。
- (BOOL)isLastInSenderRun:(NSInteger)row {
    NSInteger n = [self nextVisibleRow:row];
    if (n >= (NSInteger)self.messages.count) { return YES; }
    return ![self message:self.messages[(NSUInteger)n] sameSenderRunAs:self.messages[(NSUInteger)row]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 回前台抢回下载回调：一份共享下载任务只记一个回调对象，从详情页（看过同一文件）返回时回调可能被它接管，
    // 本页可见的下载进度条会停在旧值——这里让本页重新接管并就地刷新。
    if (_downloads) { [_downloads reattachActiveTasksForMessages:self.messages]; }
    IMSocketManager.sharedManager.delegate = self;
    // 同步当前真实连接态：socket 通常在会话列表页就已连上，进本页不会再触发 didChangeState，
    // 若不主动拉一次，connState 会停在默认值 → 标题误显「未连接」。
    self.connState = IMSocketManager.sharedManager.state;
    [self updateTitle];
    [self refreshBackUnreadBadge]; // 任务2：进页即显返回按钮全局未读徽标（全局总未读减当前会话）
    [IMSocketManager.sharedManager connectToHost:self.host userID:self.userID];
    // 登记本会话：以 SQLite 中“已连续同步完成”的位置为起点，不能用本地最大消息序号代替，
    // 否则只存有较新消息时会永久跳过前面的空洞。
    __block int64_t synced = 0;
    if (![self performDatabaseOperation:^(IMDatabase *database) {
        synced = [database syncedConvSeqForConv:self.convID];
    }]) { return; }
    [IMSocketManager.sharedManager trackConversation:self.convID syncedSeq:synced];
    // 跨 Tab 自愈：本页被压在别的 Tab 栈里期间，实时消息由网络层落库并推进本会话 synced 游标，但只投递给
    // 当时占用 delegate 的那个聊天页——本实例内存模型会落后。切回本 Tab 触发 appear 时，若 DB 游标已超过
    // 内存最大 conv_seq，就从库合并补齐（同栈已由折叠保证至多一个聊天页，此路径主要覆盖跨 Tab）。
    if (synced > [self maxInMemoryConvSeq]) { [self mergeMissedMessagesFromStore]; }
    // 在线态初始值改由 watch 回的 presence 快照提供（省掉每次进页一次 GET /users/{id}）：
    // watchUsers 注册即让服务端回一帧当前对端 presence，didChangePresenceForUser 渲染。首聊无会话也覆盖。
    // 兜底仍在：未连接时由 didChangeState 连上后补拉 + 重发 watch；对端离线时由 tick 每 2 分钟轮询。
    [self updatePeerWatch:YES];
    [self startPresenceTick];   // 在线态随时间推进（租约到期 / 「N 分钟前」递增），无事件可依赖
    [self reattachRunningUploads]; // 上传任务活在 uploader 单例里，回到本页要重新接管它的进度与完成回调
}

/// 在线态定时重算（仅单聊、仅页面可见期间）。
///
/// 必要性：服务端**不推下线帧**，对端离线是靠本地租约到期体现的——而"租约到期"是纯粹的时间流逝，
/// 不触发任何回调。若不自己叫醒，用户停在本页不动时副标题会永远停在「在线」（比有下线帧时更糟）。
/// 取 30s 周期而非"在 onlineUntil 时刻排一次性 timer"，是因为降档后的「N 分钟前在线」同样需要随时间推进，
/// 一次性 timer 只能修在线→离线那一跳，之后分钟数就冻住。
- (void)startPresenceTick {
    [self stopPresenceTick];
    if (self.isGroupChat) { return; } // 群聊副标题是成员数，不随时间变
    __weak typeof(self) weakSelf = self;
    __block NSInteger ticks = 0;
    self.presenceTickTimer = [NSTimer scheduledTimerWithTimeInterval:30.0 repeats:YES block:^(NSTimer *timer) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { [timer invalidate]; return; }
        [self updateTitle];
        // 每 4 个 tick（2 分钟）在对端不在线时重拉一次快照：单聊 topic 随首条消息才建立，
        // 故「好友但从没聊过」的对端不在 broadcastOnline 的收件人集合里，他上线时我收不到 presence 帧。
        // 租约模型只会让状态降级，没有任何东西能把它升回「在线」——不轮询就永远显示离线。
        if (++ticks % 4 == 0 && !self.peerPresence.isOnline) {
            [self refreshPeerPresence];
        }
    }];
}

/// 停止定时重算（离开页面时必须调用：NSTimer 强引用 block，不停会连着 VC 一起活到 timer 失效）。
- (void)stopPresenceTick {
    [self.presenceTickTimer invalidate];
    self.presenceTickTimer = nil;
}

/// 订阅/退订对端在线态（仅单聊）。watch=YES 关注对端（服务端只推它、并回一帧快照）；NO 清空关注。
/// 全量替换语义，重复发送幂等；连上前发送会被 writeData 静默丢弃，故须在 didChangeState 连上时重发。
- (void)updatePeerWatch:(BOOL)watch {
    if (self.isGroupChat || self.peerID.length == 0) { return; }
    [IMSocketManager.sharedManager watchUsers:(watch ? @[self.peerID] : @[])];
}

/// 拉取对端在线态快照（单聊才有）。失败静默：在线态是锦上添花，不该弹错打扰聊天。
- (void)refreshPeerPresence {
    if (self.isGroupChat || self.peerID.length == 0) { return; }
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService userProfileWithToken:token userID:self.peerID completion:^(IMUserCard *card, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !card) { return; }
        self.peerPresence = card.presence;
        [self updateTitle];
    }];
}

#pragma mark - 拉黑（微信式单向：拉黑者仍可发，故聊天页不拦输入；黑名单状态在通讯录管理）

// 微信式单向：拉黑者仍可给被拉黑者发消息（对方能收到），故聊天页不再拦输入/盖横幅。
// 是否拉黑、解除拉黑均在通讯录好友行（副标题"已拉黑" + 左滑"解除拉黑"）管理。

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // 在出现动画前、首次布局完成时即定位，避免"先显历史第一条→再滑到最新"的闪动。
    if (!self.didInitialPosition && self.messages.count > 0 && self.tableView.frame.size.height > 0) {
        [self positionInitialIfNeeded];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self positionInitialIfNeeded]; // 兜底：若 layout 时机未就绪（消息晚到），这里再定位一次
    // 进场动画结束、布局/safe-area inset 完全稳定后再校正一次定位（只做一次，#8）：
    // 无未读精确贴底、有未读重锚首条未读。不以 isNearBottom 为前提——估高偏差可超 80pt，
    // 首贴欠滚幅度恰恰会让该条件放弃修正；但必须只跑一次，否则从资料页等子页返回也会被强拉走。
    if (self.didInitialPosition && !self.didInitialSettle) {
        self.didInitialSettle = YES;
        NSInteger unreadRow = [self firstUnreadRow];
        if (unreadRow < 0) { [self scrollToAbsoluteBottom]; }
        else { [self anchorRowToTop:unreadRow]; }
    }
    // 可见即读：把定位后当前可见的消息标为已读（不滚动也算看到）。
    dispatch_async(dispatch_get_main_queue(), ^{ [self markVisibleRowsRead]; });
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self dismissMentionPanel]; // 离开/推子页前收起内联 @面板，避免残留
    [self stopPresenceTick]; // 页面不可见就没必要重算；也避免 timer 拖住 VC 不释放
    if (self.isMovingFromParentViewController) {
        // 真正离开聊天页（非推子页）：退订对端在线态，服务端不再向本连接推它的 presence。
        // 推子页（资料页等）不退订——回来时 viewWillAppear 会幂等重发，中途保持关注更自然。
        [self updatePeerWatch:NO];
        // 不断开长连接：返回会话列表后仍需常驻接收新消息以实时刷新未读（见 IMConversationListViewController）。
        // 仅交还 delegate，避免离开后本页继续处理消息。
        if (IMSocketManager.sharedManager.delegate == self) {
            IMSocketManager.sharedManager.delegate = nil;
        }
    }
}

#pragma mark - UI

- (void)setupUI {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.allowsSelection = NO;
    // 点击引用消息 → 跳转原消息（M4-2）。tap 与滚动(pan)/长按共存；非引用消息点击无副作用。
    UITapGestureRecognizer *jumpTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleReplyJumpTap:)];
    jumpTap.cancelsTouchesInView = NO;
    [self.tableView addGestureRecognizer:jumpTap];
    self.tableView.estimatedRowHeight = 56; // 估高更准 → 进会话滚到底更稳，减少自适应高度引起的偏移
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.backgroundView = [IMChatBackgroundView new]; // Telegram 绿主题壁纸
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.tableView registerClass:IMBubbleCell.class forCellReuseIdentifier:@"bubble"];
    [self.tableView registerClass:IMSystemCell.class forCellReuseIdentifier:@"system"];
    [self.tableView registerClass:IMImageCell.class forCellReuseIdentifier:@"image"];
    [self.tableView registerClass:IMAlbumCell.class forCellReuseIdentifier:@"album"];        // 相册宫格（leader 行）
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"albumPad"]; // 相册从行（零高占位）
    [self.tableView registerClass:IMChatRecordCell.class forCellReuseIdentifier:@"record"];
    [self.tableView registerClass:IMLinkCardCell.class forCellReuseIdentifier:@"link"];
    [self.view addSubview:self.tableView];

    // 引用预览条（M4-2，默认高度 0；引用时展开：左竖条 + 预览文案 + 取消 ✕）。
    self.replyBar = [UIView new];
    self.replyBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.replyBar.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.replyBar.clipsToBounds = YES;
    [self.view addSubview:self.replyBar];
    UIView *replyStripe = [UIView new];
    replyStripe.translatesAutoresizingMaskIntoConstraints = NO;
    replyStripe.backgroundColor = IMTheme.accent;
    [self.replyBar addSubview:replyStripe];
    self.replyThumb = [UIImageView new];
    self.replyThumb.translatesAutoresizingMaskIntoConstraints = NO;
    self.replyThumb.contentMode = UIViewContentModeScaleAspectFill;
    self.replyThumb.clipsToBounds = YES;
    self.replyThumb.layer.cornerRadius = 4;
    self.replyThumb.hidden = YES;
    [self.replyBar addSubview:self.replyThumb];
    self.replyLabel = [UILabel new];
    self.replyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.replyLabel.font = [UIFont systemFontOfSize:13];
    self.replyLabel.textColor = UIColor.secondaryLabelColor;
    [self.replyBar addSubview:self.replyLabel];
    UIButton *replyCancel = [UIButton buttonWithType:UIButtonTypeSystem];
    replyCancel.translatesAutoresizingMaskIntoConstraints = NO;
    [replyCancel setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    replyCancel.tintColor = UIColor.tertiaryLabelColor;
    [replyCancel addTarget:self action:@selector(cancelReply) forControlEvents:UIControlEventTouchUpInside];
    [self.replyBar addSubview:replyCancel];
    [NSLayoutConstraint activateConstraints:@[
        [replyStripe.leadingAnchor constraintEqualToAnchor:self.replyBar.leadingAnchor constant:12],
        [replyStripe.widthAnchor constraintEqualToConstant:3],
        [replyStripe.topAnchor constraintEqualToAnchor:self.replyBar.topAnchor constant:6],
        [replyStripe.bottomAnchor constraintEqualToAnchor:self.replyBar.bottomAnchor constant:-6],
        [self.replyThumb.leadingAnchor constraintEqualToAnchor:replyStripe.trailingAnchor constant:8],
        [self.replyThumb.centerYAnchor constraintEqualToAnchor:self.replyBar.centerYAnchor],
        [self.replyThumb.widthAnchor constraintEqualToConstant:28],
        [self.replyThumb.heightAnchor constraintEqualToConstant:28],
        [self.replyLabel.centerYAnchor constraintEqualToAnchor:self.replyBar.centerYAnchor],
        [replyCancel.leadingAnchor constraintEqualToAnchor:self.replyLabel.trailingAnchor constant:8],
        [replyCancel.trailingAnchor constraintEqualToAnchor:self.replyBar.trailingAnchor constant:-12],
        [replyCancel.centerYAnchor constraintEqualToAnchor:self.replyBar.centerYAnchor],
    ]];
    // label 前导：无缩略图时贴竖条、有缩略图时贴缩略图（beginReplyTo/cancel 切换）。
    self.replyLabelLeadingNoThumb = [self.replyLabel.leadingAnchor constraintEqualToAnchor:replyStripe.trailingAnchor constant:8];
    self.replyLabelLeadingThumb = [self.replyLabel.leadingAnchor constraintEqualToAnchor:self.replyThumb.trailingAnchor constant:8];
    self.replyLabelLeadingNoThumb.active = YES;

    // 粘贴图片预览条（引用条之下、输入栏之上；默认高度 0）：横向滚动的缩略图 chip，每张右上 ✕。
    self.pasteBar = [UIView new];
    self.pasteBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.pasteBar.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.pasteBar.clipsToBounds = YES;
    [self.view addSubview:self.pasteBar];
    UIScrollView *pasteScroll = [UIScrollView new];
    pasteScroll.translatesAutoresizingMaskIntoConstraints = NO;
    pasteScroll.showsHorizontalScrollIndicator = NO;
    [self.pasteBar addSubview:pasteScroll];
    self.pasteChipsStack = [UIStackView new];
    self.pasteChipsStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.pasteChipsStack.axis = UILayoutConstraintAxisHorizontal;
    self.pasteChipsStack.spacing = 10;
    self.pasteChipsStack.alignment = UIStackViewAlignmentCenter;
    [pasteScroll addSubview:self.pasteChipsStack];
    [NSLayoutConstraint activateConstraints:@[
        [pasteScroll.leadingAnchor constraintEqualToAnchor:self.pasteBar.leadingAnchor constant:12],
        [pasteScroll.trailingAnchor constraintEqualToAnchor:self.pasteBar.trailingAnchor constant:-12],
        [pasteScroll.topAnchor constraintEqualToAnchor:self.pasteBar.topAnchor],
        [pasteScroll.bottomAnchor constraintEqualToAnchor:self.pasteBar.bottomAnchor],
        [self.pasteChipsStack.leadingAnchor constraintEqualToAnchor:pasteScroll.contentLayoutGuide.leadingAnchor],
        [self.pasteChipsStack.trailingAnchor constraintEqualToAnchor:pasteScroll.contentLayoutGuide.trailingAnchor],
        [self.pasteChipsStack.topAnchor constraintEqualToAnchor:pasteScroll.contentLayoutGuide.topAnchor],
        [self.pasteChipsStack.bottomAnchor constraintEqualToAnchor:pasteScroll.contentLayoutGuide.bottomAnchor],
        [self.pasteChipsStack.heightAnchor constraintEqualToAnchor:pasteScroll.frameLayoutGuide.heightAnchor],
    ]];

    UIView *inputBar = [UIView new];
    self.inputBar = inputBar;
    inputBar.translatesAutoresizingMaskIntoConstraints = NO;
    inputBar.backgroundColor = UIColor.secondarySystemBackgroundColor;
    [self.view addSubview:inputBar];

    IMPasteImageTextField *pasteField = [IMPasteImageTextField new];
    __weak typeof(self) wsPaste = self;
    pasteField.onPasteImage = ^(UIImage *image) { [wsPaste appendPastedImage:image]; }; // 粘贴图片→预览条攒批→发送键统一发（#2）
    self.inputField = pasteField;
    self.inputField.translatesAutoresizingMaskIntoConstraints = NO;
    self.inputField.placeholder = @"输入消息…";
    self.inputField.font = [UIFont systemFontOfSize:MAX(15, IMTheme.chatFontSize - 1)];
    self.inputField.returnKeyType = UIReturnKeySend;
    self.inputField.delegate = self;
    // 圆角胶囊输入框（Telegram 风格）。
    self.inputField.backgroundColor = UIColor.systemBackgroundColor;
    self.inputField.layer.cornerRadius = IMAppearance.shared.bubbleRadius;
    self.inputField.layer.borderWidth = 1;
    self.inputField.layer.borderColor = UIColor.separatorColor.CGColor;
    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 0)];
    self.inputField.leftView = pad;
    self.inputField.leftViewMode = UITextFieldViewModeAlways;
    [self.inputField addTarget:self action:@selector(inputChanged) forControlEvents:UIControlEventEditingChanged];
    [inputBar addSubview:self.inputField];

    // 微信式输入栏（M4-6）：语音（左）| 输入框 | 表情 | 加号 | 发送。语音/表情当前占位。
    UIImageSymbolConfiguration *barCfg = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightRegular];
    UIButton *voiceButton = [UIButton buttonWithType:UIButtonTypeSystem];
    voiceButton.translatesAutoresizingMaskIntoConstraints = NO;
    [voiceButton setImage:[UIImage systemImageNamed:@"waveform.circle" withConfiguration:barCfg] forState:UIControlStateNormal];
    voiceButton.tintColor = IMTheme.textSecondary;
    [voiceButton addTarget:self action:@selector(voiceTapped) forControlEvents:UIControlEventTouchUpInside];
    [inputBar addSubview:voiceButton];

    UIButton *emojiButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.emojiButton = emojiButton;
    emojiButton.translatesAutoresizingMaskIntoConstraints = NO;
    [emojiButton setImage:[UIImage systemImageNamed:@"face.smiling" withConfiguration:barCfg] forState:UIControlStateNormal];
    emojiButton.tintColor = IMTheme.textSecondary;
    [emojiButton addTarget:self action:@selector(emojiTapped) forControlEvents:UIControlEventTouchUpInside];
    [inputBar addSubview:emojiButton];

    UIButton *plusButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.plusButton = plusButton;
    plusButton.translatesAutoresizingMaskIntoConstraints = NO;
    [plusButton setImage:[UIImage systemImageNamed:@"plus.circle" withConfiguration:barCfg] forState:UIControlStateNormal];
    plusButton.tintColor = IMTheme.textSecondary;
    [plusButton addTarget:self action:@selector(toggleAttachPanel) forControlEvents:UIControlEventTouchUpInside];
    [inputBar addSubview:plusButton];

    // 圆形发送按钮（蓝底上箭头）。有内容时显示、与表情/加号互斥（#4）。
    UIButton *sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.sendButton = sendButton;
    sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:28 weight:UIImageSymbolWeightRegular];
    [sendButton setImage:[UIImage systemImageNamed:@"arrow.up.circle.fill" withConfiguration:cfg] forState:UIControlStateNormal];
    sendButton.tintColor = IMTheme.accent;
    [sendButton addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
    [inputBar addSubview:sendButton];

    // 右下角"↓N"悬浮跳转按钮（默认隐藏；滚离底部时出现，点按回到最新；CHAT_UX §7）。
    self.jumpButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.jumpButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageSymbolConfiguration *jcfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold];
    // 标准 Liquid Glass 圆钮（iOS26 原生玻璃自带按压放大；旧系统 gray() 降级）；不再手绘底色/阴影。
    UIButtonConfiguration *jumpConf = IMGlassButtonConfiguration();
    jumpConf.image = [UIImage systemImageNamed:@"chevron.down" withConfiguration:jcfg];
    jumpConf.cornerStyle = UIButtonConfigurationCornerStyleCapsule; // 40×40 frame → 圆形
    jumpConf.contentInsets = NSDirectionalEdgeInsetsZero;
    jumpConf.baseForegroundColor = IMTheme.textPrimary;
    self.jumpButton.configuration = jumpConf;
    self.jumpButton.hidden = YES;
    [self.jumpButton addTarget:self action:@selector(jumpTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.jumpButton];

    self.jumpBadge = [UILabel new];
    self.jumpBadge.translatesAutoresizingMaskIntoConstraints = NO;
    self.jumpBadge.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    self.jumpBadge.textColor = UIColor.whiteColor;
    self.jumpBadge.backgroundColor = IMTheme.unreadBadge; // 与会话列表未读一致（蓝）
    self.jumpBadge.textAlignment = NSTextAlignmentCenter;
    self.jumpBadge.layer.cornerRadius = 9;
    self.jumpBadge.layer.masksToBounds = YES;
    self.jumpBadge.hidden = YES;
    [self.view addSubview:self.jumpBadge];

    // 置顶消息横幅（G0）：浮在消息表之上、紧贴安全区顶（Glass 导航栏正下方）。
    // 不改 tableView 的约束（它刻意铺到状态栏下），改用 contentInset.top 顶开内容——
    // 走 additionalSafeAreaInsets 会反过来推动本横幅自身的约束，形成循环。
    __weak typeof(self) wsBanner = self;
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;

    // 入群申请横幅（G3，蓝条，仅群主/管理员）：贴安全区顶，排在公告/置顶之上。点=进审批列表。
    self.approvalBanner = [[IMPinnedBannerView alloc] initWithStyle:IMBannerStyleApproval];
    self.approvalBanner.translatesAutoresizingMaskIntoConstraints = NO;
    self.approvalBanner.hidden = YES;
    self.approvalBanner.onTap = ^{ [wsBanner approvalBannerTapped]; };
    self.approvalBanner.onClose = ^{
        __strong typeof(wsBanner) self = wsBanner; if (!self) { return; }
        BOOL canManage = self.groupInfo.myRole == IMGroupRoleOwner || self.groupInfo.myRole == IMGroupRoleAdmin;
        NSInteger pending = (self.isGroupChat && canManage) ? self.groupInfo.pendingCount : 0;
        [NSUserDefaults.standardUserDefaults setInteger:pending forKey:[self bannerDismissKey:@"approval"]];
        [self applyApprovalBanner];
    };
    [self.view addSubview:self.approvalBanner];

    // 群公告横幅（G1，黄条）：接在申请横幅下方，排在置顶横幅之上（优先级 申请 > 公告 > 置顶）。点条=开公告全文视图。
    self.announcementBanner = [[IMPinnedBannerView alloc] initWithStyle:IMBannerStyleAnnouncement];
    self.announcementBanner.translatesAutoresizingMaskIntoConstraints = NO;
    self.announcementBanner.hidden = YES;
    self.announcementBanner.onTap = ^{ [wsBanner announcementBannerTapped]; };
    self.announcementBanner.onClose = ^{
        __strong typeof(wsBanner) self = wsBanner; if (!self) { return; }
        if (self.announcementText.length > 0) {
            [NSUserDefaults.standardUserDefaults setObject:self.announcementText forKey:[self bannerDismissKey:@"ann"]];
        }
        [self applyAnnouncementBanner];
    };
    [self.view addSubview:self.announcementBanner];

    // 置顶消息横幅（G0，蓝条）：接在公告横幅下方。
    self.pinnedBanner = [[IMPinnedBannerView alloc] initWithStyle:IMBannerStylePinned];
    self.pinnedBanner.translatesAutoresizingMaskIntoConstraints = NO;
    self.pinnedBanner.hidden = YES;
    self.pinnedBanner.onTap = ^{ [wsBanner pinnedBannerTapped]; };
    self.pinnedBanner.onList = ^{ [wsBanner pinnedBannerListTapped]; };
    self.pinnedBanner.onClose = ^{
        __strong typeof(wsBanner) self = wsBanner; if (!self) { return; }
        NSString *sig = [self currentPinnedSig];
        if (sig.length > 0) { [NSUserDefaults.standardUserDefaults setObject:sig forKey:[self bannerDismissKey:@"pin"]]; }
        [self applyPinnedBanner];
    };
    [self.view addSubview:self.pinnedBanner];

    [NSLayoutConstraint activateConstraints:@[
        [self.approvalBanner.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [self.approvalBanner.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.approvalBanner.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        (self.approvalBannerHeight = [self.approvalBanner.heightAnchor constraintEqualToConstant:0]),

        [self.announcementBanner.topAnchor constraintEqualToAnchor:self.approvalBanner.bottomAnchor],
        [self.announcementBanner.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.announcementBanner.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        (self.announcementBannerHeight = [self.announcementBanner.heightAnchor constraintEqualToConstant:0]),

        [self.pinnedBanner.topAnchor constraintEqualToAnchor:self.announcementBanner.bottomAnchor],
        [self.pinnedBanner.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.pinnedBanner.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        (self.pinnedBannerHeight = [self.pinnedBanner.heightAnchor constraintEqualToConstant:0]),
    ]];

    self.inputBottom = [inputBar.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor];
    [NSLayoutConstraint activateConstraints:@[
        // 聊天背景和消息内容铺到状态栏下方；统一 Glass 导航栏叠加在内容之上。
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.replyBar.topAnchor],

        // 引用条：夹在消息区与粘贴条之间；默认高度 0（cancelReply/showReply 切换）。
        [self.replyBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.replyBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.replyBar.bottomAnchor constraintEqualToAnchor:self.pasteBar.topAnchor],
        (self.replyBarHeight = [self.replyBar.heightAnchor constraintEqualToConstant:0]),

        // 粘贴图预览条：夹在引用条与输入栏之间；默认高度 0（refreshPasteBar 切换）。
        [self.pasteBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.pasteBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.pasteBar.bottomAnchor constraintEqualToAnchor:inputBar.topAnchor],
        (self.pasteBarHeight = [self.pasteBar.heightAnchor constraintEqualToConstant:0]),

        [inputBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [inputBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        self.inputBottom,
        [inputBar.heightAnchor constraintEqualToConstant:56],

        // 语音（左）| 输入框 | 表情 | 加号 | 发送（M4-6 微信式）。
        [voiceButton.leadingAnchor constraintEqualToAnchor:inputBar.leadingAnchor constant:8],
        [voiceButton.centerYAnchor constraintEqualToAnchor:inputBar.centerYAnchor],
        [voiceButton.widthAnchor constraintEqualToConstant:34],
        [voiceButton.heightAnchor constraintEqualToConstant:36],
        [self.inputField.leadingAnchor constraintEqualToAnchor:voiceButton.trailingAnchor constant:4],
        [self.inputField.centerYAnchor constraintEqualToAnchor:inputBar.centerYAnchor],
        [self.inputField.heightAnchor constraintEqualToConstant:36],
        // 表情/加号靠右并列；发送按钮与加号同槽位（互斥显示，#4）。
        [emojiButton.trailingAnchor constraintEqualToAnchor:plusButton.leadingAnchor constant:-2],
        [emojiButton.centerYAnchor constraintEqualToAnchor:inputBar.centerYAnchor],
        [emojiButton.widthAnchor constraintEqualToConstant:34],
        [emojiButton.heightAnchor constraintEqualToConstant:36],
        [plusButton.trailingAnchor constraintEqualToAnchor:inputBar.trailingAnchor constant:-8],
        [plusButton.centerYAnchor constraintEqualToAnchor:inputBar.centerYAnchor],
        [plusButton.widthAnchor constraintEqualToConstant:34],
        [plusButton.heightAnchor constraintEqualToConstant:36],
        [sendButton.trailingAnchor constraintEqualToAnchor:inputBar.trailingAnchor constant:-8],
        [sendButton.centerYAnchor constraintEqualToAnchor:inputBar.centerYAnchor],
        [sendButton.widthAnchor constraintEqualToConstant:36],
        [sendButton.heightAnchor constraintEqualToConstant:36],

        [self.jumpButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.jumpButton.bottomAnchor constraintEqualToAnchor:self.replyBar.topAnchor constant:-12],
        [self.jumpButton.widthAnchor constraintEqualToConstant:40],
        [self.jumpButton.heightAnchor constraintEqualToConstant:40],
        [self.jumpBadge.centerXAnchor constraintEqualToAnchor:self.jumpButton.trailingAnchor constant:-5],
        [self.jumpBadge.centerYAnchor constraintEqualToAnchor:self.jumpButton.topAnchor constant:5],
        [self.jumpBadge.heightAnchor constraintEqualToConstant:18],
        [self.jumpBadge.widthAnchor constraintGreaterThanOrEqualToConstant:18],
    ]];

    // 输入框右缘随内容切换：无内容贴表情、有内容贴发送（#4）。
    self.inputTrailToEmoji = [self.inputField.trailingAnchor constraintEqualToAnchor:emojiButton.leadingAnchor constant:-4];
    self.inputTrailToSend = [self.inputField.trailingAnchor constraintEqualToAnchor:sendButton.leadingAnchor constant:-4];
    [self updateSendButtonVisibility]; // 初始（空）：显示表情/加号，隐藏发送
}

/// 输入框有内容（文字或待发粘贴图）→ 显示发送、隐藏表情/加号；否则显示表情/加号、隐藏发送（#4）。
/// 注意：程序化改 text（回填/清空）不触发 EditingChanged，需在改后手动调用本方法。
- (void)updateSendButtonVisibility {
    BOOL hasContent = self.inputField.text.length > 0 || self.pendingPasteImages.count > 0;
    self.sendButton.hidden = !hasContent;
    self.emojiButton.hidden = hasContent;
    self.plusButton.hidden = hasContent;
    self.inputTrailToEmoji.active = !hasContent;
    self.inputTrailToSend.active = hasContent;
}

#pragma mark - 发送 / 接收

/// 输入变化 → 发「正在输入」（2s 节流，避免每次按键都发）。
- (void)inputChanged {
    [self updateSendButtonVisibility]; // 内容增删 → 切换发送/表情+加号（#4）
    [self maybePresentMentionPicker];  // 群聊键入 @ → 弹成员选择卡（M4-8）
    if (self.inputField.text.length == 0) { return; }
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (now - self.lastTypingSent > 2.0) {
        self.lastTypingSent = now;
        [IMSocketManager.sharedManager sendTypingForConv:self.convID];
    }
}

#pragma mark - @提及（M4-8）

/// 输入框「正在输入的 @查询词」：光标前最近一个 `@` 到光标之间、且不含空白的片段。
/// 返回 nil 表示当前不在 @ 输入态。半角 `@` 与中文键盘的全角 `＠` 都认。
- (nullable NSString *)activeMentionQuery {
    NSString *text = self.inputField.text ?: @"";
    if (text.length == 0) { return nil; }
    // UITextField 单行，取光标位置；拿不到就按整串末尾算。
    NSInteger caret = (NSInteger)text.length;
    UITextRange *sel = self.inputField.selectedTextRange;
    if (sel) {
        caret = [self.inputField offsetFromPosition:self.inputField.beginningOfDocument toPosition:sel.end];
    }
    if (caret <= 0 || caret > (NSInteger)text.length) { return nil; }
    NSString *head = [text substringToIndex:(NSUInteger)caret];
    NSRange at = [head rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"@＠"]
                                       options:NSBackwardsSearch];
    if (at.location == NSNotFound) { return nil; }
    NSString *q = [head substringFromIndex:at.location + at.length];
    // @ 后出现空白即视为这次提及已结束（用户在正常打字，不该再弹卡）。
    if ([q rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) { return nil; }
    return q;
}

/// 群聊里键入 `@` 时在**输入栏上方**内联一个成员下拉面板（child VC，不弹 sheet、不遮挡输入框）。
/// 面板顶部自带搜索框并自动聚焦：焦点从聊天输入框转到搜索框（键盘不收），过滤由搜索框驱动；
/// 选中后焦点交还聊天输入框、回填 token 并移除面板。删掉 `@`/点取消/发送/退出会话都会移除面板。
- (void)maybePresentMentionPicker {
    if (!self.isGroupChat || !self.groupInfo) { [self dismissMentionPanel]; return; }
    NSString *q = [self activeMentionQuery];
    if (!q) { [self dismissMentionPanel]; return; }
    if (self.mentionPanel) {
        // 已开：聊天输入框里 @后的文字**实时驱动**面板过滤（任务1，微信/Telegram 式）。
        [self.mentionPanel updateQuery:q];
        [self updateMentionPanelHeight];
        return;
    }
    __weak typeof(self) ws = self;
    // 首次打开即按当前 @查询词过滤（刚敲下 @、后面还没字时 q 为空串 → 列表显全部成员）。
    IMMentionPickerViewController *panel = [[IMMentionPickerViewController alloc]
        initInlineWithGroup:self.groupInfo
               initialQuery:q
               onPickMember:^(IMGroupMember *m) { [ws pickMentionInsert:m.displayName uid:m.userID]; }
                  onPickAll:^{ [ws pickMentionInsert:@"所有人" uid:nil]; }];
    panel.onInlineFilterChanged = ^{ [ws updateMentionPanelHeight]; };
    panel.onInlineCancel = ^{ [ws dismissMentionPanel]; [ws.inputField becomeFirstResponder]; };
    [self addChildViewController:panel];
    panel.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:panel.view];
    // 底边贴输入区栈顶（replyBar.top）→ 浮在消息区底部、输入栏之上；键盘弹起时随约束链一起上移。
    self.mentionPanelHeight = [panel.view.heightAnchor constraintEqualToConstant:[panel preferredInlineHeight]];
    [NSLayoutConstraint activateConstraints:@[
        [panel.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [panel.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [panel.view.bottomAnchor constraintEqualToAnchor:self.replyBar.topAnchor],
        self.mentionPanelHeight,
    ]];
    [panel didMoveToParentViewController:self];
    self.mentionPanel = panel;
    // 刻意**不**聚焦搜索框：焦点留在聊天输入框，用户想搜再点搜索框（对齐用户要求）。
}

/// 面板选中某成员/@所有人：焦点先回聊天输入框（保证 caret 有效）→ 回填 token → 移除面板。
- (void)pickMentionInsert:(NSString *)displayName uid:(nullable NSString *)uid {
    [self.inputField becomeFirstResponder];
    [self insertMentionToken:displayName forUID:uid];
    [self dismissMentionPanel];
}

- (void)updateMentionPanelHeight {
    if (!self.mentionPanel || !self.mentionPanelHeight) { return; }
    self.mentionPanelHeight.constant = [self.mentionPanel preferredInlineHeight];
    [self.view layoutIfNeeded];
}

/// 移除内联 @面板（选中 / 离开 @ 输入态 / 发送 / 退出会话）。
- (void)dismissMentionPanel {
    if (!self.mentionPanel) { return; }
    IMMentionPickerViewController *p = self.mentionPanel;
    self.mentionPanel = nil;
    self.mentionPanelHeight = nil;
    [p willMoveToParentViewController:nil];
    [p.view removeFromSuperview];
    [p removeFromParentViewController];
}

/// 回填 token：把输入框里"正在输入的 @query"整体替换为 `@显示名 `（尾随空格便于继续打字）。
/// uid 为 nil 表示 @所有人。被 @ 者记入 mentionCandidates，发送时按文本里是否还留着该 token 复核。
- (void)insertMentionToken:(NSString *)displayName forUID:(nullable NSString *)uid {
    NSString *text = self.inputField.text ?: @"";
    NSInteger caret = (NSInteger)text.length;
    UITextRange *sel = self.inputField.selectedTextRange;
    if (sel) {
        caret = [self.inputField offsetFromPosition:self.inputField.beginningOfDocument toPosition:sel.end];
    }
    caret = MAX(0, MIN(caret, (NSInteger)text.length));
    NSString *head = [text substringToIndex:(NSUInteger)caret];
    NSString *after = [text substringFromIndex:(NSUInteger)caret];
    NSRange at = [head rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"@＠"]
                                       options:NSBackwardsSearch];
    // 尾随空格便于继续打字；但光标后本就以空白开头时不再补，否则会留下双空格（与 Web mention.ts 一致）。
    BOOL afterStartsBlank = after.length > 0 &&
        [NSCharacterSet.whitespaceAndNewlineCharacterSet characterIsMember:[after characterAtIndex:0]];
    NSString *token = [NSString stringWithFormat:@"@%@%@", displayName, afterStartsBlank ? @"" : @" "];
    NSUInteger caretAfterInsert = 0;
    if (at.location == NSNotFound) {
        self.inputField.text = [NSString stringWithFormat:@"%@%@%@", head, token, after]; // 兜底：光标处插入
        caretAfterInsert = head.length + token.length;
    } else {
        NSString *before = [text substringToIndex:at.location];
        self.inputField.text = [NSString stringWithFormat:@"%@%@%@", before, token, after];
        caretAfterInsert = before.length + token.length;
    }
    if (uid.length > 0) {
        if (!self.mentionCandidates) { self.mentionCandidates = [NSMutableDictionary dictionary]; }
        self.mentionCandidates[uid] = displayName;
    } else {
        self.mentionAllPending = YES;
    }
    [self updateSendButtonVisibility];
    [self.inputField becomeFirstResponder];
    // 光标落回 token 之后（UITextField 被程序化赋值后默认停在末尾，token 后若还有正文就错位了）。
    UITextPosition *pos = [self.inputField positionFromPosition:self.inputField.beginningOfDocument
                                                         offset:(NSInteger)caretAfterInsert];
    if (pos) { self.inputField.selectedTextRange = [self.inputField textRangeFromPosition:pos toPosition:pos]; }
}

/// 发送前把输入框文本还原成 mentions uid 列表：只保留**文本里仍存在完整 token** 的候选，
/// 用户手动删掉 token 即自动不再 @ 他（草图 §07-06）。
- (NSArray<NSString *> *)resolvedMentionsInText:(NSString *)text {
    if (self.mentionCandidates.count == 0 || text.length == 0) { return @[]; }
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    [self.mentionCandidates enumerateKeysAndObjectsUsingBlock:^(NSString *uid, NSString *name, BOOL *stop) {
        if (IMChatTextContainsMentionToken(text, name)) { [out addObject:uid]; }
    }];
    return out;
}

/// @所有人 是否仍生效：既要标记在、文本里也要还留着完整的 `@所有人` token。
- (BOOL)resolvedMentionAllInText:(NSString *)text {
    return self.mentionAllPending && IMChatTextContainsMentionToken(text, @"所有人");
}

- (void)sendTapped {
    NSString *text = [self.inputField.text stringByTrimmingCharactersInSet:
                      NSCharacterSet.whitespaceAndNewlineCharacterSet];
    // 先发预览条里攒的粘贴图（≥2 张共享 group_id 成宫格），文字随后补发一条文本（Telegram 式）。
    if (self.pendingPasteImages.count > 0) {
        NSArray<UIImage *> *images = [self.pendingPasteImages copy];
        [self.pendingPasteImages removeAllObjects];
        [self refreshPasteBar];
        NSString *gid = images.count > 1 ? [@"alb-" stringByAppendingString:NSUUID.UUID.UUIDString] : nil;
        for (UIImage *img in images) { [self uploadAndSendPastedImage:img groupID:gid]; }
        [self updateSendButtonVisibility];
    }
    if (text.length == 0) { return; }

    // 编辑态（M4-5）：发 msg_op edit 而非新消息；内容由服务端广播回 onMsgOpApplied 更新。
    if (self.editingMessage && self.editingMessage.convSeq > 0) {
        [IMSocketManager.sharedManager editMessageInConv:(self.editingMessage.convID ?: @"")
                                           targetConvSeq:self.editingMessage.convSeq content:text];
        [self cancelEdit];
        return;
    }

    __block NSString *clientMsgID = nil;
    __weak typeof(self) weakSelf = self;
    IMSendCompletion completion = ^(BOOL success, NSError *error, int64_t convSeq) {
        [weakSelf handleSendResult:success convSeq:convSeq error:error forClientMsgID:clientMsgID];
    };
    int64_t replySeq = self.replyingTo.convSeq; // 引用回复（M4-2）：0=普通发送
    // @提及（M4-8）：按输入框里**仍留着**的 token 还原 uid（删了 token 就自动不 @ 他）。
    NSArray<NSString *> *mentions = self.isGroupChat ? [self resolvedMentionsInText:text] : @[];
    BOOL mentionAll = self.isGroupChat && [self resolvedMentionAllInText:text];
    // 群聊按 conv_id 路由（to 留空，服务端查成员写扩散）；单聊按对端 uid。
    clientMsgID = self.isGroupChat
        ? [IMSocketManager.sharedManager sendText:text toConv:self.convID replyToConvSeq:replySeq
                                         mentions:mentions mentionAll:mentionAll completion:completion]
        : [IMSocketManager.sharedManager sendText:text toUser:self.peerID replyToConvSeq:replySeq completion:completion];

    IMMessageModel *m = [IMMessageModel new];
    m.clientMsgID = clientMsgID;
    m.convID = self.convID;
    m.to = self.peerID;
    m.content = text;
    m.from = self.userID;
    m.contentType = @"text";
    m.status = IMMessageStatusSending;
    m.timestamp = (int64_t)(NSDate.date.timeIntervalSince1970 * 1000); // 本地时间，气泡尾巴即时显示时间（与 Web 一致）
    if (replySeq > 0) { // 本端即时快照（服务端会给收件方冻结权威快照；媒体用 [图片]/[视频] 占位）
        m.replyToConvSeq = replySeq;
        m.replySnapshot = IMReplySnippet(self.replyingTo);
        m.replyToFrom = self.replyingTo.from; // 被引用者 uid：本端回显需自带（服务端只发给收件方，ack 不回带、sync 已去重）
    }
    [self performDatabaseOperation:^(IMDatabase *database) {
        [database saveMessage:m]; // 落库（sending）
    }];
    [self.messages addObject:m];
    self.inputField.text = @"";
    [self clearPendingMentions]; // 发出即清，下一条重新累积（M4-8）
    [self updateSendButtonVisibility];
    [self cancelReply];
    [self appendReloadAndScroll];
}

/// 清空本条待发的 @提及态（输入框已清空，候选表与 @所有人 标记一并复位）。
- (void)clearPendingMentions {
    [self.mentionCandidates removeAllObjects];
    self.mentionAllPending = NO;
    [self dismissMentionPanel]; // 发出后输入框已清空（编程式清空不触发 editingChanged），显式收面板
}

#pragma mark - 引用回复（M4-2）

/// 进入引用态：展开引用条显示预览，聚焦输入框。
- (void)beginReplyTo:(IMMessageModel *)message {
    self.editingMessage = nil; // 引用与编辑互斥（共用引用条）
    self.replyingTo = message;
    NSString *who = [message.from isEqualToString:self.userID] ? @"自己"
        : (self.isGroupChat ? [self senderNameForMessage:message] : (self.peerID ?: @""));
    self.replyLabel.text = [NSString stringWithFormat:@"回复 %@：%@", who, IMReplySnippet(message)];
    // 引用图片/视频：预览条显示一枚小缩略图（#5）。
    BOOL isImage = [message.contentType isEqualToString:@"image"];
    BOOL isVideo = [message.contentType isEqualToString:@"video"];
    [self setReplyThumbForMediaMessage:(isImage || isVideo) ? message : nil isVideo:isVideo];
    self.replyBarHeight.constant = 40;
    [self.inputField becomeFirstResponder];
}

/// 显示/隐藏引用预览条的缩略图并切换 label 前导约束。message=nil → 隐藏（文本引用）。
- (void)setReplyThumbForMediaMessage:(IMMessageModel *)message isVideo:(BOOL)isVideo {
    if (!message) {
        self.replyThumb.hidden = YES;
        self.replyThumb.image = nil;
        self.replyLabelLeadingThumb.active = NO;
        self.replyLabelLeadingNoThumb.active = YES;
        return;
    }
    self.replyThumb.hidden = NO;
    self.replyThumb.image = nil;
    self.replyLabelLeadingNoThumb.active = NO;
    self.replyLabelLeadingThumb.active = YES;
    NSString *url = [self fullMediaURL:message.content];
    __weak typeof(self) ws = self;
    // 门控一致（M4-7）：统一取图（真帧仅已下载 > thumb 磨砂 > 媒体类型图标）；异步回来若已切换/取消
    // 引用目标（replyingTo 变了）则丢弃这张过期图（防串图）。
    [IMMediaPlaceholder previewForURL:url isVideo:isVideo thumb:message.thumb completion:^(UIImage *img) {
        __strong typeof(ws) self = ws;
        if (!self || self.replyingTo != message) { return; }
        self.replyThumb.image = img ?: [[UIImage systemImageNamed:(isVideo ? @"video.fill" : @"photo.fill")]
            imageWithTintColor:IMTheme.textSecondary renderingMode:UIImageRenderingModeAlwaysOriginal];
    }];
}

/// 退出引用态（或编辑态，引用条为二者共用）：收起条。
- (void)cancelReply {
    if (self.editingMessage) { [self cancelEdit]; return; }
    self.replyingTo = nil;
    self.replyBarHeight.constant = 0;
    self.replyLabel.text = nil;
    [self setReplyThumbForMediaMessage:nil isVideo:NO];
}

#pragma mark - 收藏（M4-4）

/// 收藏一条消息（内容快照到服务端，原消息撤回/删除后仍在）。
- (void)favoriteMessage:(IMMessageModel *)message {
    if (message.content.length == 0) { return; }
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    [IMHTTPService.sharedService addFavoriteWithToken:token contentType:(message.contentType ?: @"text")
                                              content:message.content sourceConvID:message.convID
                                        sourceConvSeq:message.convSeq sourceFrom:(message.from ?: @"")
                                           completion:^(NSError *error) {
        // toast 吐在当前可见页（从全屏媒体库的查看器收藏时，本页不可见，吐在自己身上等于没提示）。
        [UIViewController im_showGlobalToast:error ? [NSString stringWithFormat:@"收藏失败：%@", error.localizedDescription] : @"已收藏"];
    }];
}

#pragma mark - 编辑 / 翻译（M4-5）

/// 进入编辑态：引用条复用为"编辑消息"预览，输入框回填原文。
- (void)beginEditMessage:(IMMessageModel *)message {
    self.replyingTo = nil;
    self.editingMessage = message;
    [self setReplyThumbForMediaMessage:nil isVideo:NO]; // 编辑仅文本，无缩略图
    self.replyLabel.text = [NSString stringWithFormat:@"编辑消息：%@",
        message.content.length > 40 ? [[message.content substringToIndex:40] stringByAppendingString:@"…"] : (message.content ?: @"")];
    self.replyBarHeight.constant = 40;
    self.inputField.text = message.content;
    [self updateSendButtonVisibility];
    [self.inputField becomeFirstResponder];
}

/// 退出编辑态。
- (void)cancelEdit {
    self.editingMessage = nil;
    self.replyBarHeight.constant = 0;
    self.replyLabel.text = nil;
    self.inputField.text = @"";
    [self updateSendButtonVisibility];
}

/// 翻译一条消息：调服务端翻译，译文挂气泡下方（内存态）。
- (void)translateMessage:(IMMessageModel *)message {
    if (message.content.length == 0) { return; }
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService translateWithToken:token text:message.content targetLang:@"zh"
                                         completion:^(NSString *translation, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) { [self im_showToast:[NSString stringWithFormat:@"翻译失败：%@", error.localizedDescription]]; return; }
        message.translation = translation;
        [self.tableView reloadData];
    }];
}

#pragma mark - 附件面板 / 富媒体（M4-6）

- (void)voiceTapped { [self im_showComingSoon:@"语音"]; }
- (void)emojiTapped { [self im_showComingSoon:@"表情"]; }

/// 面板项（数据驱动，M4-6）：加入口 = 数组加一条。照片接真实上传，其余占位。
- (NSArray<NSDictionary *> *)attachItems {
    return @[
        @{ @"id": @"photo", @"title": @"照片", @"image": @"photo" },
        @{ @"id": @"camera", @"title": @"拍摄", @"image": @"camera" },
        @{ @"id": @"av", @"title": @"音视频", @"image": @"video" },
        @{ @"id": @"favorite", @"title": @"收藏", @"image": @"bookmark" },
        @{ @"id": @"card", @"title": @"个人名片", @"image": @"person.crop.square" },
        @{ @"id": @"file", @"title": @"文件", @"image": @"doc" },
    ];
}

static const CGFloat kIMAttachPanelHeight = 236; // 面板高度（顶起输入栏的量）

/// 展开/收起附件面板（首次点击惰性构建 2×3 网格）。面板显示在输入栏「下方」（微信式）：
/// 展开时收起键盘、把输入栏上顶 kIMAttachPanelHeight，面板填充其下方空间。
- (void)toggleAttachPanel {
    if (!self.attachPanel) {
        [self buildAttachPanel];
        // 首次建面板时先解析约束，确保动画从输入栏下方的真实初始 frame 开始，
        // 而非 Auto Layout 尚未赋值时的左上角 (0,0)。
        [self.view layoutIfNeeded];
    }
    [self showAttachPanel:!self.attachPanelVisible];
}

/// 统一切换面板可见性并驱动布局（与键盘互斥，见 updateInputBottomAnimated:）。
/// 注意：方法名不能叫 setAttachPanelVisible:（那是属性 attachPanelVisible 的合成 setter，会与内部 self.attachPanelVisible= 赋值自递归）。
- (void)showAttachPanel:(BOOL)visible {
    if (visible) { [self.inputField resignFirstResponder]; } // 面板与键盘不同时占位
    self.attachPanelVisible = visible;
    self.attachPanel.hidden = !visible;
    [self updateInputBottomAnimated:YES];
}

- (void)buildAttachPanel {
    UIView *panel = [UIView new];
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    panel.backgroundColor = UIColor.secondarySystemBackgroundColor;
    panel.hidden = YES;
    [self.view addSubview:panel];
    self.attachPanel = panel;

    UIStackView *rows = [UIStackView new]; // 竖直：两行
    rows.translatesAutoresizingMaskIntoConstraints = NO;
    rows.axis = UILayoutConstraintAxisVertical;
    rows.distribution = UIStackViewDistributionFillEqually;
    rows.spacing = 16;
    [panel addSubview:rows];

    NSArray<NSDictionary *> *items = [self attachItems];
    UIStackView *currentRow = nil;
    for (NSUInteger i = 0; i < items.count; i++) {
        if (i % 3 == 0) {
            currentRow = [UIStackView new];
            currentRow.axis = UILayoutConstraintAxisHorizontal;
            currentRow.distribution = UIStackViewDistributionFillEqually;
            currentRow.spacing = 16;
            [rows addArrangedSubview:currentRow];
        }
        [currentRow addArrangedSubview:[self attachItemViewFor:items[i]]];
    }
    [NSLayoutConstraint activateConstraints:@[
        [panel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [panel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [panel.topAnchor constraintEqualToAnchor:self.inputBar.bottomAnchor], // 在输入栏「下方」展开
        [panel.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],   // 铺到屏幕底（覆盖 home 指示条区域）
        [rows.topAnchor constraintEqualToAnchor:panel.topAnchor constant:16],
        [rows.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:24],
        [rows.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-24],
        [rows.heightAnchor constraintEqualToConstant:kIMAttachPanelHeight - 40],
    ]];
}

/// 单个面板项：图标圆钮 + 标题。
- (UIView *)attachItemViewFor:(NSDictionary *)item {
    UIStackView *v = [UIStackView new];
    v.axis = UILayoutConstraintAxisVertical;
    v.alignment = UIStackViewAlignmentCenter;
    v.spacing = 6;
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageSymbolConfiguration *c = [UIImageSymbolConfiguration configurationWithPointSize:26 weight:UIImageSymbolWeightRegular];
    [btn setImage:[UIImage systemImageNamed:item[@"image"] withConfiguration:c] forState:UIControlStateNormal];
    btn.tintColor = IMTheme.textPrimary;
    btn.backgroundColor = UIColor.systemBackgroundColor;
    btn.layer.cornerRadius = 12;
    NSString *itemId = item[@"id"];
    __weak typeof(self) ws = self;
    [btn addAction:[UIAction actionWithHandler:^(UIAction *a) { [ws attachItemTapped:itemId]; }]
        forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [btn.widthAnchor constraintEqualToConstant:56],
        [btn.heightAnchor constraintEqualToConstant:56],
    ]];
    UILabel *lbl = [UILabel new];
    lbl.text = item[@"title"];
    lbl.font = [UIFont systemFontOfSize:12];
    lbl.textColor = IMTheme.textSecondary;
    [v addArrangedSubview:btn];
    [v addArrangedSubview:lbl];
    return v;
}

- (void)attachItemTapped:(NSString *)itemId {
    [self showAttachPanel:NO];
    if ([itemId isEqualToString:@"photo"]) {
        [self openPhotoPicker];
        return;
    }
    if ([itemId isEqualToString:@"camera"]) {
        [self openCamera];
        return;
    }
    if ([itemId isEqualToString:@"file"]) {
        [self openFilePanel];
        return;
    }
    NSDictionary *names = @{ @"av": @"音视频",
                            @"favorite": @"从收藏发送", @"card": @"个人名片" };
    [self im_showComingSoon:names[itemId] ?: @"该功能"]; // 其余占位，后续按需接真实功能
}

/// 把消息里的相对 URL（/uploads/xxx）补成绝对地址（含 host）；已是 http/data 的原样返回。
- (NSString *)fullMediaURL:(NSString *)content {
    return IMMediaFullURL(content, self.host);
}

/// 全屏查看图片/视频（点击媒体气泡）：复用 IMMediaViewerViewController，附「媒体库」入口。
/// 任务3：在当前会话媒体时间线（口径同媒体库：image|video·未撤回·非空）里定位点中的这条，
/// 套 IMMediaPagerViewController 支持左右翻页（混排、封面待点、翻到头即停）；仅一张时退化为单开。
- (void)presentMediaViewerForMessage:(IMMessageModel *)m preloaded:(UIImage *)image {
    if (m.content.length == 0) { return; }
    NSMutableArray<IMMessageModel *> *mediaMsgs = [NSMutableArray array];
    for (IMMessageModel *x in self.messages) {
        if (x.recalledAt > 0 || x.content.length == 0) { continue; }
        if ([x.contentType isEqualToString:@"image"] || [x.contentType isEqualToString:@"video"]) {
            [mediaMsgs addObject:x];
        }
    }
    NSUInteger start = [mediaMsgs indexOfObjectIdenticalTo:m];
    if (start == NSNotFound) {
        // 不在时间线内（理论不至于，兜底）→ 单开自带全套控件的查看器。
        [self presentViewController:[self buildMediaViewerForMessage:m preloaded:image] animated:YES completion:nil];
        return;
    }
    // 恒走翻页容器（即便仅一张）：壳（✕/下载/媒体库/更多）在容器固定层、沉浸态一致。
    __weak typeof(self) ws = self;
    IMMediaPagerViewController *pager =
        [IMMediaPagerViewController pagerWithCount:mediaMsgs.count startIndex:start
                                      pageProvider:^IMMediaViewerViewController *(NSUInteger index) {
            __strong typeof(ws) self = ws;
            if (!self || index >= mediaMsgs.count) { return nil; }
            IMMessageModel *mm = mediaMsgs[index];
            // 仅初始点中的那条带气泡预载图（已解码），其余现建时自行按 URL 拉。
            return [self buildMediaViewerForMessage:mm preloaded:(mm == m ? image : nil)];
        }];
    pager.conversationTitle = [self conversationDisplayTitle];
    [self presentViewController:pager animated:YES completion:nil];
}

/// 为单条媒体消息构建一个查看器页（url/isVideo/媒体库入口/「更多」外部动作均绑定该条消息）。
/// 翻页容器按下标对每条消息各建一份，保证「更多」里的收藏/转发/删除/定位作用在正确的消息上。
- (IMMediaViewerViewController *)buildMediaViewerForMessage:(IMMessageModel *)m preloaded:(UIImage *)image {
    BOOL isVideo = [m.contentType isEqualToString:@"video"];
    __weak typeof(self) ws = self;
    IMMediaViewerViewController *viewer =
        [IMMediaViewerViewController viewerWithURL:[self fullMediaURL:m.content]
                                           isVideo:isVideo
                                    preloadedImage:image
                                     onOpenGallery:^{ [ws openConversationMediaGallery]; }];
    viewer.thumbDataURI = m.thumb; // 路线 A：未下载/加载中先显内嵌 thumb 磨砂占位 + 菊花
    viewer.moreActions = [self mediaViewerMoreActionsForMessage:m];
    return viewer;
}

/// 查看器「更多」外部动作（定位/收藏/复制/转发；内置「下载」由查看器自己加在最前）：
/// 聊天气泡查看器与全屏媒体库查看器共用。
- (NSArray<IMPopoverCardItem *> *)mediaViewerMoreActionsForMessage:(IMMessageModel *)m {
    BOOL isVideo = [m.contentType isEqualToString:@"video"];
    __weak typeof(self) ws = self;
    NSMutableArray<IMPopoverCardItem *> *acts = [NSMutableArray array];
    if (m.convSeq > 0) {
        [acts addObject:[IMPopoverCardItem itemWithTitle:@"定位到聊天位置" symbol:@"text.bubble" destructive:NO handler:^{
            [ws jumpToConvSeq:m.convSeq];
        }]];
    }
    [acts addObject:[IMPopoverCardItem itemWithTitle:@"收藏" symbol:@"bookmark" destructive:NO handler:^{ [ws favoriteMessage:m]; }]];
    // 视频不提供复制：无"复制字节"语义，复制链接意义不大，产品上禁止复制视频消息（与 Web 对齐）。
    if (!isVideo) {
        [acts addObject:[IMPopoverCardItem itemWithTitle:@"复制" symbol:@"doc.on.doc" destructive:NO handler:^{
            [ws copyMessageToPasteboard:m]; // 图片→复制图片字节（可粘贴回输入框发图）
        }]];
    }
    if (m.recalledAt == 0 && m.convSeq > 0) {
        [acts addObject:[IMPopoverCardItem itemWithTitle:@"转发" symbol:@"arrowshape.turn.up.right" destructive:NO handler:^{ [ws forwardMessage:m]; }]];
    }
    // 删除（与 Web 查看器「更多」对齐）：可为所有人删则弹两档 sheet，否则=仅删除自己 / 本地删。
    [acts addObject:[IMPopoverCardItem itemWithTitle:@"删除" symbol:@"trash" destructive:YES handler:^{ [ws confirmDeleteMediaMessage:m]; }]];
    return acts;
}

/// 查看器「更多」里的删除（IMPopoverCard 为扁平列表，用 action sheet 承载两档）：
/// 本地未发出（convSeq<=0）=本地删；可为所有人删=弹「仅删除自己 / 为所有人删除」；否则=仅删除自己。
- (void)confirmDeleteMediaMessage:(IMMessageModel *)m {
    if (!m) { return; }
    if (m.convSeq <= 0) { [self deleteMessage:m]; return; }
    if (![self canDeleteForEveryone:m]) { [self hideMessageForSelf:m]; return; }
    __weak typeof(self) ws = self;
    // 从可见页弹（查看器「更多」是先关查看器再执行，栈顶可能是全屏媒体库而非本页；
    // 挂到被覆盖的 self 上会被 UIKit 静默拒绝，曾致删除无反应）。
    UIViewController *presenter = [UIViewController im_topVisibleViewController] ?: self;
    [presenter im_presentDeleteChoiceSheetWithSelfOnly:^{ [ws hideMessageForSelf:m]; }
                                              everyone:^{ [ws deleteMessageForEveryone:m]; }];
}

/// 全屏媒体库逐格长按菜单里「消息相关」动作（转发/定位/删除，与资料 tab 一致；「取消下载」由媒体库自带）。
- (NSArray<IMMenuAction *> *)mediaContextActionsForMessage:(IMMessageModel *)m {
    __weak typeof(self) ws = self;
    NSMutableArray<IMMenuAction *> *acts = [NSMutableArray array];
    [acts addObject:[IMMenuAction actionWithId:@"forward" title:@"转发" image:@"arrowshape.turn.up.right"
                                       handler:^{ [ws forwardMessage:m]; }]];
    [acts addObject:[IMMenuAction actionWithId:@"locate" title:@"定位到聊天" image:@"text.bubble"
                                       handler:^{ [ws jumpToConvSeq:m.convSeq]; }]];
    [acts addObject:[self deleteMenuActionForMessage:m]]; // actionId=@"delete"（媒体库据此在其前插「取消下载」）
    return acts;
}

/// 媒体查看器/媒体库顶部标题（会话名）：单聊=对方昵称/uid，群聊=群名。
- (NSString *)conversationDisplayTitle {
    if (self.isGroupChat) { return self.groupName.length > 0 ? self.groupName : @"群聊"; }
    return self.peerNickname.length > 0 ? self.peerNickname : self.peerID;
}

/// 会话媒体库：汇总当前会话所有图片/视频消息，按时间序展示，点击复用同一查看器。
- (void)openConversationMediaGallery {
    NSMutableArray<IMMediaItem *> *items = [NSMutableArray array];
    NSMutableArray<IMMessageModel *> *msgs = [NSMutableArray array];
    for (IMMessageModel *m in self.messages) {
        if (m.recalledAt > 0 || m.content.length == 0) { continue; }
        BOOL isVideo = [m.contentType isEqualToString:@"video"];
        BOOL isImage = [m.contentType isEqualToString:@"image"];
        if (!isVideo && !isImage) { continue; }
        [items addObject:[IMMediaItem itemWithURL:[self fullMediaURL:m.content] isVideo:isVideo timestamp:m.timestamp thumb:m.thumb]];
        [msgs addObject:m];
    }
    __weak typeof(self) ws = self;
    IMConversationMediaViewController *gallery =
        [IMConversationMediaViewController galleryWithItems:items messages:msgs
                                                       host:self.host myUserID:self.userID isGroup:self.isGroupChat
                                                      title:[self conversationDisplayTitle]
                                     contextActionsProvider:^NSArray<IMMenuAction *> *(IMMessageModel *m) { return [ws mediaContextActionsForMessage:m]; }
                                        moreActionsProvider:^NSArray<IMPopoverCardItem *> *(IMMessageModel *m) { return [ws mediaViewerMoreActionsForMessage:m]; }];
    [self.navigationController pushViewController:gallery animated:YES];
}

/// 打开合并转发的聊天记录详情页（#3）。
- (void)openChatRecord:(IMMessageModel *)message {
    if (message.content.length == 0) { return; }
    IMChatRecordViewController *vc = [[IMChatRecordViewController alloc] initWithHost:self.host recordJSON:message.content];
    [self.navigationController pushViewController:vc animated:YES];
}

/// 相册多选（PHPicker，≤9，图片/Live 图/视频）→ **选完秒上屏**（≥2 张=一个宫格 cell，1 张=普通媒体气泡）
/// → 缩略图逐格异步补上 → 逐项 压缩/转码 + 带进度上传（每格环形进度）→ 传完一张转正式发送一张。
/// PHPicker 是进程外选择器，无需相册读权限（保存到相册的权限仍在下载路径申请）。
- (void)openPhotoPicker {
    __weak typeof(self) ws = self;
    [IMMediaPicker presentFromViewController:self limit:9
                           handlesCompletion:^(NSArray<IMPickedMediaHandle *> *handles) {
        [ws sendMediaHandles:handles];
    }];
}

/// 批量发送（相册重构，M4+）：句柄回调即上屏（不等压缩/转码），重活延后逐项进行。
- (void)sendMediaHandles:(NSArray<IMPickedMediaHandle *> *)handles {
    if (handles.count == 0) { return; }
    // ≥2 张：共享 group_id → 两端聚簇渲染宫格；1 张：普通媒体气泡（无 group_id）。
    NSString *gid = handles.count > 1 ? [@"alb-" stringByAppendingString:NSUUID.UUID.UUIDString] : nil;
    NSMutableArray<IMMessageModel *> *pending = [NSMutableArray arrayWithCapacity:handles.count];
    for (IMPickedMediaHandle *h in handles) {
        IMMessageModel *m = [IMMessageModel new];
        m.clientMsgID = [@"outbox-" stringByAppendingString:NSUUID.UUID.UUIDString]; // 临时键，转正式发送时换真 ID
        m.convID = self.convID; m.to = self.peerID; m.from = self.userID;
        m.content = @""; // 未上传：无 URL，格内显示本地预览/灰占位
        m.contentType = h.isVideo ? @"video" : @"image";
        m.groupID = gid;
        m.status = IMMessageStatusSending;
        m.timestamp = (int64_t)(NSDate.date.timeIntervalSince1970 * 1000);
        [self.messages addObject:m];
        [pending addObject:m];
    }
    // 转码 → 落盘 → 上传 → 发消息全程活在常驻服务（退出本页/无页面存活都不中断）；
    // enqueue 会先置好 queued 进度与缩略图加载，本页只负责上屏与渲染。
    [IMMediaSendService.shared enqueueMediaHandles:handles messages:pending
                                            toUser:(self.isGroupChat ? @"" : self.peerID)
                                         dbContext:self.databaseContext];
    [self.tableView reloadData]; // 一次性上屏：宫格只有 1 个可见 cell（从行零高），无逐条插行闪动
    [self scrollToAbsoluteBottom];
}

/// 待发/失败的乐观气泡落库（content 为 im-pending:// 本地引用）。
/// 成功发出后常驻服务会把 content 换成服务器 URL 再存一次，并删掉本地副本。
///
/// **content 为空的不落库**：那种行重进会话既显示不出内容也无法重试，只会留下一个永久的空气泡
/// （字节还没落盘就失败时会走到这里，例如未登录、句柄解码失败、磁盘写满）。
- (void)persistOutboxMessage:(IMMessageModel *)m {
    if (m.content.length == 0) { return; }
    [self performDatabaseOperation:^(IMDatabase *database) { [database saveMessage:m]; }];
}

/// 本地待发媒体的缩略图：重进会话时消息 content 是 im-pending:// 本地文件，直接出图，不走网络。
/// **解码放后台**：cellForRow 里同步解一张 4K 图或抽一帧 74MB 视频会直接卡住滚动
/// （正是 IMImageLoader 刚清掉的那种主线程解码）。首帧返回 nil，解完再刷该行。
- (UIImage *)pendingPreviewForMessage:(IMMessageModel *)m {
    NSString *key = m.clientMsgID ?: @"";
    UIImage *cached = self.outboxPreviews[key];
    if (cached) { return cached; }
    if (key.length == 0 || [self.pendingPreviewLoading containsObject:key]) { return nil; }
    NSString *path = [[IMPendingMediaStore shared] filePathForLocalRef:m.content];
    if (!path) { return nil; }
    [self.pendingPreviewLoading addObject:key];
    BOOL isVideo = [m.contentType isEqualToString:@"video"];
    __weak typeof(self) ws = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        UIImage *thumb = isVideo ? IMPendingVideoThumbnail(path) : IMPendingImageThumbnail(path);
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            [self.pendingPreviewLoading removeObject:key];
            if (!thumb) { return; }
            self.outboxPreviews[key] = thumb;
            [self refreshVisibleCellForMessage:m];
        });
    });
    return nil;
}

/// 点按待发中的图片/视频气泡（中心按钮状态机）或文件气泡的左侧图标位（同一套状态机）：
///   失败 ↻ → 重试；上传中 ⏸ ↔ 已暂停 ↑ → 切换；排队/压缩/准备中 ✕ → 确认后取消（防误触必须确认）。
- (void)handlePendingMediaTap:(IMMessageModel *)m {
    if (m.status == IMMessageStatusFailed) { [self retryPendingMessage:m]; return; }
    if ([IMMediaSendService.shared togglePauseForMessage:m]) { return; } // 分片上传：暂停↔继续
    IMUploadProgress *p = self.outboxProgress[m.clientMsgID ?: @""];
    if (p.phase == IMUploadPhaseQueued || p.phase == IMUploadPhaseTranscoding) {
        [self confirmCancelPendingMessage:m]; // 排队/压缩期无任务可暂停，点按=询问取消
    }
    // 一次性小上传进行中：无可操作，忽略点击
}

/// 取消发送前确认（长按菜单直达 cancelPendingMessage，点按走这里防误触）。
- (void)confirmCancelPendingMessage:(IMMessageModel *)m {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:@"取消发送这条消息？"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) ws = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消发送" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *a) { [ws cancelPendingMessage:m]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"继续发送" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

/// 取消发送：服务负责停任务/删副本/删库行并广播 DidCancel，本页在通知里移除该行。
- (void)cancelPendingMessage:(IMMessageModel *)m {
    [IMMediaSendService.shared cancelMessage:m dbContext:self.databaseContext];
}

/// 重试一条本地待发失败的消息（图片/视频/文件通吃）：交给常驻服务从本地副本续（文件走分片续传）。
- (void)retryPendingMessage:(IMMessageModel *)m {
    BOOL ok = [IMMediaSendService.shared retryMessage:m
                                               toUser:(self.isGroupChat ? @"" : self.peerID)
                                            dbContext:self.databaseContext];
    if (!ok) { [self im_showToast:@"本地文件已丢失，无法重试"]; return; }
    [self refreshVisibleCellForMessage:m];
}

/// 定点刷新消息的可见 cell：相册成员 → leader 行的宫格只刷格子（不 reload、不动布局）；
/// 普通消息 → reload 自身行（媒体 cell 固定高，不影响滚动位置）。
- (void)refreshVisibleCellForMessage:(IMMessageModel *)m {
    NSUInteger row = [self visibleRowForMessage:m];
    if (row == NSNotFound) { return; }
    // 行数守卫：消息可能刚 addObject 尚未 reloadData（如入列时服务同步广播初始进度），
    // 此时定点 reloadRows 会触发 UITableView 行数断言直接崩溃（真机 2026-08-04 crash 实锤）→ 整表刷。
    if ((NSInteger)row >= [self.tableView numberOfRowsInSection:0]) {
        [self.tableView reloadData];
        return;
    }
    NSIndexPath *ip = [NSIndexPath indexPathForRow:(NSInteger)row inSection:0];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:ip];
    if ([cell isKindOfClass:IMAlbumCell.class]) {
        [(IMAlbumCell *)cell refreshWithPreviews:self.outboxPreviews progress:self.outboxProgress];
        return;
    }
    [self.tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
}

/// 就地重算行高（媒体 cell 拿到真实比例后调用）：不 reload、不动画，避免打断滚动与图片闪烁。
- (void)refreshRowHeightsWithoutAnimation {
    [UIView performWithoutAnimation:^{
        [self.tableView beginUpdates];
        [self.tableView endUpdates];
    }];
}

/// 进度只改可见 cell 的覆盖层/进度环（不 reload，避免高频进度回调闪烁）。
- (void)updateUploadProgressForMessage:(IMMessageModel *)m {
    NSUInteger row = [self visibleRowForMessage:m];
    if (row == NSNotFound) { return; }
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)row inSection:0]];
    if ([cell isKindOfClass:IMAlbumCell.class]) {
        [(IMAlbumCell *)cell refreshWithPreviews:self.outboxPreviews progress:self.outboxProgress];
    } else if ([cell isKindOfClass:IMImageCell.class]) {
        [(IMImageCell *)cell setUploadProgress:self.outboxProgress[m.clientMsgID ?: @""]];
    }
}

/// 拍摄（#4 先申请相机权限）→ 上传 → 发图片消息。
- (void)openCamera {
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        [self im_showToast:@"当前设备不支持拍摄"];
        return;
    }
    __weak typeof(self) ws = self;
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            if (granted) { [self presentImagePickerWithSource:UIImagePickerControllerSourceTypeCamera]; }
            else { [self im_showToast:@"请在设置中允许使用相机"]; }
        });
    }];
}

/// 文件面板（Telegram 式）：从相册/从文件 入口 + 「最近发送的文件」列表（复发不再上传）。
- (void)openFilePanel {
    __weak typeof(self) ws = self;
    __block NSString *nextCursor = nil;
    __block NSArray<NSDictionary *> *cachedFiles = @[];
    [self performDatabaseOperation:^(IMDatabase *database) {
        cachedFiles = database.cachedSentFiles;
    }];
    IMFilePickerViewController *panel = [[IMFilePickerViewController alloc]
        initWithRecentFiles:cachedFiles
        onFromPhotos:^{ [ws openPhotoFilePicker]; }
        onFromFiles:^{ [ws presentDocumentPicker]; }
        onPickRecent:^(NSString *url, NSString *name, int64_t size) {
            [ws sendMediaURL:url contentType:@"file" fileName:name fileSize:size];
        }
        loadPage:^(BOOL nextPage, IMSentFilePageCompletion completion) {
            NSString *token = IMHTTPService.sharedService.currentToken;
            if (token.length == 0) {
                completion(nil, NO, [NSError errorWithDomain:@"IMFilePicker" code:-1 userInfo:nil]);
                return;
            }
            NSString *cursor = nextPage ? nextCursor : nil;
            [IMHTTPService.sharedService sentFilesWithToken:token cursor:cursor
                completion:^(NSArray<NSDictionary *> *files, NSString *cursorAfter, BOOL hasMore, NSError *error) {
                    if (!error) {
                        nextCursor = cursorAfter;
                        [ws performDatabaseOperation:^(IMDatabase *database) {
                            [database cacheSentFiles:files ?: @[]];
                        }];
                    }
                    completion(files, hasMore, error);
                }];
        }];
    // 直接 present 面板（不再包 UINavigationController）：面板自持一条 IMLiquidNavigationBar，
    // 顶部关闭按钮与全局返回按钮同款 Liquid Glass；sheet 配置在面板 init 内已设好。
    [self presentViewController:panel animated:YES completion:nil];
}

/// 文件面板中的相册入口：以 file 消息发送原始资源，不进入图片/视频气泡或相册宫格。
/// 与 Files 大文件路径同构：选完**立刻上屏**（旧实现要等整个原件拷进内存 + 一次性传完才见气泡，
/// 大视频等几分钟毫无反馈），导出/落盘/上传/发送全程活在常驻服务，≥8MB 分片可暂停续传。
- (void)openPhotoFilePicker {
    __weak typeof(self) ws = self;
    [IMMediaPicker presentFilePickerFromViewController:self limit:9
                           handlesCompletion:^(NSArray<IMPickedMediaHandle *> *handles) {
        [ws sendPhotoFileHandles:handles];
    }];
}

- (void)sendPhotoFileHandles:(NSArray<IMPickedMediaHandle *> *)handles {
    if (handles.count == 0) { return; }
    NSMutableArray<IMMessageModel *> *pending = [NSMutableArray arrayWithCapacity:handles.count];
    for (IMPickedMediaHandle *h in handles) {
        IMMessageModel *m = [IMMessageModel new];
        m.clientMsgID = [@"outbox-" stringByAppendingString:NSUUID.UUID.UUIDString]; // 临时键，转正式发送时换真 ID
        m.convID = self.convID; m.to = self.peerID; m.from = self.userID;
        m.content = @""; // 导出完成前无本地副本；服务落盘后写 im-pending:// 并落库
        m.contentType = @"file";
        m.fileName = [h suggestedFileName];
        m.fileSize = 0; // 未知，导出完成后服务补写（第二行先显「准备中…」）
        m.status = IMMessageStatusSending;
        m.timestamp = (int64_t)(NSDate.date.timeIntervalSince1970 * 1000);
        [self.messages addObject:m];
        [pending addObject:m];
    }
    // 先上屏再入列（与 sendLargeFileAtURL 同理：入列路径若同步广播进度，reloadRows 会撞行数断言）。
    [self.tableView reloadData];
    [self scrollToAbsoluteBottom];
    [IMMediaSendService.shared enqueuePhotoFileHandles:handles messages:pending
                                                toUser:(self.isGroupChat ? @"" : self.peerID)
                                             dbContext:self.databaseContext];
}

/// 文件面板关闭后，由聊天页直接呈现系统文件浏览器（全屏、单实例配置见 +systemDocumentPicker）。
/// 系统自行维护 Files/File Provider 的内部返回栈，选完或点叉叉都由系统关闭 picker 直接回到聊天页。
- (void)presentDocumentPicker {
    UIDocumentPickerViewController *picker = [IMFilePickerViewController systemDocumentPicker];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    [self handlePickedDocumentURL:urls.firstObject];
}

/// 大文件分片发送：先把文件落到待发目录并**立刻上屏**一条 sending 气泡（带进度、可暂停），
/// 再走分片上传；中断/退出会话都不丢，重进能看到并继续。
- (void)sendLargeFileAtURL:(NSURL *)fileURL fileName:(NSString *)fileName size:(int64_t)size token:(NSString *)token {
    IMMessageModel *m = [IMMessageModel new];
    m.clientMsgID = [@"outbox-" stringByAppendingString:NSUUID.UUID.UUIDString];
    m.convID = self.convID; m.to = self.peerID; m.from = self.userID;
    m.contentType = @"file";
    m.fileName = fileName;
    m.fileSize = size;
    m.status = IMMessageStatusSending;
    m.timestamp = (int64_t)(NSDate.date.timeIntervalSince1970 * 1000);
    // 文件系统拷贝，不经内存：几百 MB 的文件读进 NSData 足以触发 jetsam。
    NSString *localRef = [[IMPendingMediaStore shared] storeFileAtURL:fileURL
                                                      forClientMsgID:m.clientMsgID
                                                           extension:fileName.pathExtension];
    if (!localRef) { [self im_showToast:@"本地暂存失败，请重试"]; return; }
    m.content = localRef;
    [self.messages addObject:m];
    [self persistOutboxMessage:m];
    // **先上屏再入列**：enqueue 内部会同步广播初始进度（分片作业立即标 ⏸），通知回调按 messages
    // 数组定位新行去 reloadRows——若 tableView 还不知道这行存在，行数断言直接崩（真机 2026-08-04 实锤）。
    [self appendReloadAndScroll];
    // 分片上传 + 完成后发消息活在常驻服务：退出会话、甚至所有聊天页都销毁，传完照样发出去。
    [IMMediaSendService.shared enqueueFileMessage:m
                                           toUser:(self.isGroupChat ? @"" : self.peerID)
                                        dbContext:self.databaseContext];
}

/// 进入/回到会话时合并常驻服务里仍在跑的作业：
/// - 转码/落盘尚未完成的媒体（未落库）→ 本页列表看不到，把服务实例并进来；
/// - 已落库的行（库副本）→ 换成服务实例，让后续进度/完成直接作用于同一对象。
/// 并**自动认领孤儿 sending 行**：杀进程重启后库里 status=sending 但服务无作业的行，
/// 直接续传（凭旁挂 upload_id 从服务端 offset 继续，用户无感）；本地副本丢失才降级为失败可重试。
- (void)reattachRunningUploads {
    BOOL changed = NO;
    for (IMMessageModel *serviceModel in [IMMediaSendService.shared inFlightMessagesInConv:self.convID]) {
        IMMessageModel *mine = [self messageForClientMsgID:serviceModel.clientMsgID];
        if (!mine) {
            [self.messages addObject:serviceModel];
            changed = YES;
        } else if (mine != serviceModel) {
            NSUInteger idx = [self.messages indexOfObjectIdenticalTo:mine];
            if (idx != NSNotFound) { [self.messages replaceObjectAtIndex:idx withObject:serviceModel]; }
            changed = YES;
        }
    }
    NSString *toUser = self.isGroupChat ? @"" : self.peerID;
    for (IMMessageModel *m in self.messages) {
        if (m.status != IMMessageStatusSending || m.convSeq > 0) { continue; }
        if (![IMPendingMediaStore isLocalRef:m.content]) { continue; }
        if ([IMMediaSendService.shared hasActiveJobForClientMsgID:m.clientMsgID]) { continue; }
        if (![IMMediaSendService.shared retryMessage:m toUser:toUser dbContext:self.databaseContext]) {
            m.status = IMMessageStatusFailed; // 本地副本已丢失：无法续传，标失败给出 ↻（点了会提示副本丢失）
            [self persistOutboxMessage:m];
        }
        changed = YES;
    }
    if (changed) { [self.tableView reloadData]; }
}

/// 系统 Files 返回本地副本后上传并发送。
/// 大文件走**分片上传**：气泡立刻上屏并显示进度，可点击暂停/继续，断网后从服务端 offset 续传。
- (void)handlePickedDocumentURL:(NSURL *)url {
    if (!url) { return; }
    NSString *token = IMHTTPService.sharedService.currentToken;
    NSString *originalName = url.lastPathComponent ?: @"file.bin";
    // 先 stat 再决定走哪条路：大文件绝不能为了判断大小就整包读进内存。
    int64_t size = (int64_t)[[NSFileManager.defaultManager attributesOfItemAtPath:url.path error:NULL][NSFileSize] unsignedLongLongValue];
    if (size <= 0 || token.length == 0) { [self im_showToast:@"文件读取失败"]; return; }
    if (size >= (int64_t)IMChunkedUploader.chunkedThresholdBytes) {
        [self sendLargeFileAtURL:url fileName:originalName size:size token:token]; // 全程走文件，不进内存
        return;
    }
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (data.length == 0) { [self im_showToast:@"文件读取失败"]; return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService uploadData:data fileName:originalName
                                   mimeType:@"application/octet-stream" token:token
                                 completion:^(NSString *up, NSString *contentType, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error || up.length == 0) {
            [self im_showToast:error.localizedDescription.length ? error.localizedDescription : @"文件上传失败"];
            return;
        }
        [self sendMediaURL:up contentType:@"file" fileName:originalName fileSize:(int64_t)data.length];
    }];
}

- (void)presentImagePickerWithSource:(UIImagePickerControllerSourceType)source {
    UIImagePickerController *picker = [UIImagePickerController new];
    picker.sourceType = source;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    [picker dismissViewControllerAnimated:YES completion:nil];
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    if (!image) { return; }
    NSData *data = UIImageJPEGRepresentation(image, 0.8);
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (data.length == 0 || token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService uploadData:data fileName:@"photo.jpg" mimeType:@"image/jpeg" token:token
                                 completion:^(NSString *url, NSString *contentType, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error || url.length == 0) { [self im_showToast:@"图片上传失败"]; return; }
        [self sendMediaURL:url contentType:(contentType ?: @"image") fileName:nil fileSize:0
           mediaAttributes:[self mediaAttributesForImage:image bytes:(int64_t)data.length]];
    }];
}

/// 单图路径（相机/粘贴）的媒体元数据：像素尺寸 + 上传字节数，供收端按原比例排版。
- (IMMediaAttributes *)mediaAttributesForImage:(UIImage *)image bytes:(int64_t)bytes {
    IMMediaAttributes *attrs = [IMMediaAttributes new];
    CGFloat scale = image.scale > 0 ? image.scale : 1;
    attrs.pixelWidth = (NSInteger)round(image.size.width * scale);
    attrs.pixelHeight = (NSInteger)round(image.size.height * scale);
    attrs.fileSize = bytes;
    return attrs;
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

/// 发送已上传的媒体：走 socket sendMedia，乐观上屏。
- (void)sendMediaURL:(NSString *)url contentType:(NSString *)contentType {
    [self sendMediaURL:url contentType:contentType fileName:nil fileSize:0 mediaAttributes:nil];
}

- (void)sendMediaURL:(NSString *)url contentType:(NSString *)contentType fileName:(NSString *)fileName {
    [self sendMediaURL:url contentType:contentType fileName:fileName fileSize:0 mediaAttributes:nil];
}

- (void)sendMediaURL:(NSString *)url contentType:(NSString *)contentType fileName:(NSString *)fileName fileSize:(int64_t)fileSize {
    [self sendMediaURL:url contentType:contentType fileName:fileName fileSize:fileSize mediaAttributes:nil];
}

/// mediaAttributes：图片/视频的尺寸与时长（相机/粘贴等单图路径由调用方量出）；file 消息传 nil。
- (void)sendMediaURL:(NSString *)url contentType:(NSString *)contentType fileName:(NSString *)fileName
            fileSize:(int64_t)fileSize mediaAttributes:(IMMediaAttributes *)mediaAttributes {
    __block NSString *clientMsgID = nil;
    int64_t sentAt = (int64_t)(NSDate.date.timeIntervalSince1970 * 1000);
    __weak typeof(self) ws = self;
    IMSendCompletion completion = ^(BOOL success, NSError *error, int64_t convSeq) {
        [ws handleSendResult:success convSeq:convSeq error:error forClientMsgID:clientMsgID];
        if (success && [contentType isEqualToString:@"file"] && fileName.length > 0) {
            [ws performDatabaseOperation:^(IMDatabase *database) {
                [database cacheSentFiles:@[@{
                    @"server_msg_id": clientMsgID ?: @"",
                    @"url": url ?: @"", @"name": fileName, @"size": @(fileSize), @"timestamp": @(sentAt),
                }]];
            }];
        }
    };
    NSString *toUser = self.isGroupChat ? @"" : self.peerID;
    if ([contentType isEqualToString:@"file"]) {
        clientMsgID = [IMSocketManager.sharedManager sendFile:url fileName:fileName ?: @"" fileSize:fileSize toConv:self.convID toUser:toUser completion:completion];
    } else {
        clientMsgID = [IMSocketManager.sharedManager sendMedia:url contentType:contentType toConv:self.convID toUser:toUser
                                                    attributes:mediaAttributes completion:completion];
    }

    IMMessageModel *m = [IMMessageModel new];
    m.clientMsgID = clientMsgID; m.convID = self.convID; m.to = self.peerID; m.from = self.userID;
    m.content = url; m.contentType = contentType; m.status = IMMessageStatusSending;
    m.fileName = fileName;
    m.fileSize = mediaAttributes.fileSize > 0 ? mediaAttributes.fileSize : fileSize;
    m.mediaW = mediaAttributes.pixelWidth;
    m.mediaH = mediaAttributes.pixelHeight;
    m.duration = mediaAttributes.durationMillis;
    m.groupID = mediaAttributes.groupID; // 粘贴多图：本端也按宫格聚簇渲染
    m.timestamp = sentAt;
    [self performDatabaseOperation:^(IMDatabase *database) {
        [database saveMessage:m];
    }];
    [self.messages addObject:m];
    [self appendReloadAndScroll];
}

#pragma mark - 复制 / 粘贴图片（#2）

/// 复制消息：图片→复制真实图片字节（可粘贴回输入框直接发图）；其余→复制文本/链接。
- (void)copyMessageToPasteboard:(IMMessageModel *)message {
    if ([message.contentType isEqualToString:@"image"]) {
        __weak typeof(self) ws = self;
        [[IMImageLoader shared] loadImageURL:[self fullMediaURL:message.content] completion:^(UIImage *img) {
            if (img) {
                UIPasteboard.generalPasteboard.image = img;
                [ws im_showToast:@"已复制图片"];
            } else {
                UIPasteboard.generalPasteboard.string = [ws fullMediaURL:message.content];
                [ws im_showToast:@"已复制链接"];
            }
        }];
        return;
    }
    BOOL isMedia = [message.contentType isEqualToString:@"video"] || [message.contentType isEqualToString:@"file"];
    UIPasteboard.generalPasteboard.string = isMedia ? [self fullMediaURL:message.content] : (message.content ?: @"");
    if (isMedia) { [self im_showToast:@"已复制链接"]; }
}

/// 粘贴图片 → 预览条攒批（#2 重设计，Telegram 式）：不直接发，缩略图 chip 出现在输入栏上方，
/// 可继续粘贴/打字，逐张 ✕ 移除；发送键统一发出（≥2 张共享 group_id 成宫格，文字随后补发）。
- (void)appendPastedImage:(UIImage *)image {
    if (!image) { return; }
    if (!self.pendingPasteImages) { self.pendingPasteImages = [NSMutableArray array]; }
    if (self.pendingPasteImages.count >= 9) { [self im_showToast:@"一次最多发送 9 张图片"]; return; }
    [self.pendingPasteImages addObject:image];
    [self refreshPasteBar];
    [self updateSendButtonVisibility];
}

/// 重建预览条 chips（张数少、重建成本可忽略）：44pt 缩略图 + 右上 ✕；条高随有无内容 0↔60 切换。
- (void)refreshPasteBar {
    for (UIView *v in [self.pasteChipsStack.arrangedSubviews copy]) {
        [self.pasteChipsStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    [self.pendingPasteImages enumerateObjectsUsingBlock:^(UIImage *img, NSUInteger idx, BOOL *stop) {
        UIView *chip = [UIView new];
        chip.translatesAutoresizingMaskIntoConstraints = NO;
        UIImageView *iv = [[UIImageView alloc] initWithImage:img];
        iv.translatesAutoresizingMaskIntoConstraints = NO;
        iv.contentMode = UIViewContentModeScaleAspectFill;
        iv.clipsToBounds = YES;
        iv.layer.cornerRadius = 8;
        [chip addSubview:iv];
        UIButton *remove = [UIButton buttonWithType:UIButtonTypeSystem];
        remove.translatesAutoresizingMaskIntoConstraints = NO;
        [remove setImage:[UIImage systemImageNamed:@"xmark.circle.fill"
                                 withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:16
                                                                                                   weight:UIImageSymbolWeightBold]]
                forState:UIControlStateNormal];
        remove.tintColor = UIColor.secondaryLabelColor;
        remove.tag = (NSInteger)idx;
        [remove addTarget:self action:@selector(removePastedImageChip:) forControlEvents:UIControlEventTouchUpInside];
        [chip addSubview:remove];
        [NSLayoutConstraint activateConstraints:@[
            [chip.widthAnchor constraintEqualToConstant:50],
            [chip.heightAnchor constraintEqualToConstant:50],
            [iv.leadingAnchor constraintEqualToAnchor:chip.leadingAnchor],
            [iv.bottomAnchor constraintEqualToAnchor:chip.bottomAnchor],
            [iv.widthAnchor constraintEqualToConstant:44],
            [iv.heightAnchor constraintEqualToConstant:44],
            [remove.centerXAnchor constraintEqualToAnchor:iv.trailingAnchor constant:-2],
            [remove.centerYAnchor constraintEqualToAnchor:iv.topAnchor constant:2],
            [remove.widthAnchor constraintEqualToConstant:24],
            [remove.heightAnchor constraintEqualToConstant:24],
        ]];
        [self.pasteChipsStack addArrangedSubview:chip];
    }];
    self.pasteBarHeight.constant = self.pendingPasteImages.count > 0 ? 60 : 0;
    [self.view layoutIfNeeded];
}

- (void)removePastedImageChip:(UIButton *)sender {
    NSInteger idx = sender.tag;
    if (idx < 0 || idx >= (NSInteger)self.pendingPasteImages.count) { return; }
    [self.pendingPasteImages removeObjectAtIndex:(NSUInteger)idx];
    [self refreshPasteBar];
    [self updateSendButtonVisibility];
}

- (void)uploadAndSendPastedImage:(UIImage *)image groupID:(NSString *)groupID {
    NSData *jpeg = UIImageJPEGRepresentation(image, 0.8);
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (jpeg.length == 0 || token.length == 0) { [self im_showToast:@"图片处理失败"]; return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService uploadData:jpeg fileName:@"pasted.jpg" mimeType:@"image/jpeg" token:token
                                 completion:^(NSString *url, NSString *contentType, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error || url.length == 0) { [self im_showToast:@"图片上传失败"]; return; }
        IMMediaAttributes *attrs = [self mediaAttributesForImage:image bytes:(int64_t)jpeg.length];
        attrs.groupID = groupID; // ≥2 张：同批共享 group_id → 两端聚簇渲染宫格
        [self sendMediaURL:url contentType:(contentType ?: @"image") fileName:nil fileSize:0
           mediaAttributes:attrs];
    }];
}

#pragma mark - 转发（M4-3）

/// 该消息是否为"曾可用、被服务端清理"的媒体（image/video/file）。转发透传的是 content URL 本身、不重传字节，
/// 故本机有无缓存都救不了对端——命中即拦，与保存(看铁律A)语义不同。key 必须用查看器/气泡同款 fullMediaURL: 解析。
- (BOOL)isMediaExpiredForForward:(IMMessageModel *)m {
    NSString *ct = m.contentType ?: @"";
    if (!([ct isEqualToString:@"image"] || [ct isEqualToString:@"video"] || [ct isEqualToString:@"file"])) { return NO; }
    if (m.content.length == 0) { return NO; }
    return [IMMediaExpiryRegistry.shared isExpiredURL:[self fullMediaURL:m.content]];
}

/// 失效媒体的类型名词（toast 用）：视频/文件/图片。
- (NSString *)expiredNounForMessage:(IMMessageModel *)m {
    if ([m.contentType isEqualToString:@"video"]) { return @"视频"; }
    if ([m.contentType isEqualToString:@"file"]) { return @"文件"; }
    return @"图片";
}

/// 转发一条消息（#6）：整页会话选择器（单/多选，最多 9）→ 逐条转发，保留 content_type（图片/视频不退化成文本）。
- (void)forwardMessage:(IMMessageModel *)message {
    // 从谁可见就从谁弹（查看器「更多」先关查看器再执行，栈顶可能是全屏媒体库而非本页）。
    [self presentForwardPickerForMessage:message
                      fromViewController:([UIViewController im_topVisibleViewController] ?: self)];
}

/// 转发选择页由 `presenter` 弹出（详情页文件列表复用时传自己），回声逻辑与 toast 都收敛在这里。
- (void)presentForwardPickerForMessage:(IMMessageModel *)message fromViewController:(UIViewController *)presenter {
    if (message.content.length == 0 || message.recalledAt > 0) { return; }
    // 失效守卫：曾可用媒体被服务端清理(404) → 转出去对端必 404，不给转发入口。一处拦住卡片菜单/长按菜单/详情页文件列表复用三入口。
    if ([self isMediaExpiredForForward:message]) {
        [(presenter ?: self) im_showToast:[NSString stringWithFormat:@"该%@已失效，无法转发", [self expiredNounForMessage:message]]];
        return;
    }
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    NSString *origin = message.forwardFrom.length > 0 ? message.forwardFrom
        : (message.fromNickname.length > 0 ? message.fromNickname : (message.from ?: @"")); // 转发链保留最初作者
    NSString *content = message.content;
    NSString *contentType = message.contentType ?: @"text";
    NSString *fileName = message.fileName;
    int64_t fileSize = message.fileSize;
    IMMediaAttributes *attrs = [self forwardAttributesForMessage:message];
    __weak typeof(self) ws = self;
    __weak UIViewController *wp = presenter;
    IMForwardPickerViewController *picker = [[IMForwardPickerViewController alloc]
        initWithHost:self.host token:token onDone:^(NSArray<IMConversation *> *selected) {
        __strong typeof(ws) self = ws;
        if (!self || selected.count == 0) { return; }
        for (IMConversation *c in selected) {
            NSString *toUser = c.isGroup ? @"" : (c.peer ?: @"");
            [self forwardEchoContent:content contentType:contentType forwardFrom:origin fileName:fileName fileSize:fileSize
                          attributes:attrs toConv:c.convID toUser:toUser];
        }
        [(wp ?: self) im_showToast:selected.count == 1 ? @"已转发" : [NSString stringWithFormat:@"已转发到 %lu 个会话", (unsigned long)selected.count]];
    }];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    [(presenter ?: self) presentViewController:nav animated:YES completion:nil];
}

#pragma mark - 长文本展开/阅读器（Q1）

/// 消息在"展开记忆"里的 key：已落库用 convSeq，发送中退回 clientMsgID。
- (NSString *)textKeyForMessage:(IMMessageModel *)m {
    if (m.convSeq > 0) { return [NSString stringWithFormat:@"seq-%lld", (long long)m.convSeq]; }
    return m.clientMsgID.length > 0 ? m.clientMsgID : @"";
}

- (BOOL)isTextExpandedForMessage:(IMMessageModel *)m {
    return [self.expandedTextKeys containsObject:[self textKeyForMessage:m]];
}

/// 本条消息里需高亮的 `@昵称` → uid 映射（气泡内 @提及高亮 + 点击跳资料）：iOS 不落库 per-message mentions，
/// 改由**当前群成员 + 文本**推导——扫描群成员昵称在文本里是否有完整 token（与 Web 用服务端 mentions 收敛，
/// 因发送侧本就按成员昵称扫文本得出 mentions）。`@所有人` 仅在发送者是群主/管理员时高亮（对齐服务端 300204 鉴权，
/// 普通成员字面「@所有人」不误高亮），且 uid 存空串＝仅高亮不可点。非群聊/非文本/无 `@` 直接返回 nil。
- (NSDictionary<NSString *, NSString *> *)mentionMapForMessage:(IMMessageModel *)m {
    if (!self.isGroupChat || ![m.contentType isEqualToString:@"text"]) { return nil; }
    NSString *text = m.content;
    if (text.length == 0 || [text rangeOfString:@"@"].location == NSNotFound) { return nil; }
    NSArray<IMGroupMember *> *members = self.groupInfo.members;
    if (members.count == 0) { return nil; }
    NSMutableDictionary<NSString *, NSString *> *map = [NSMutableDictionary dictionary];
    for (IMGroupMember *mem in members) {
        if ([mem.userID isEqualToString:m.from]
            && (mem.role == IMGroupRoleOwner || mem.role == IMGroupRoleAdmin)
            && IMChatTextContainsMentionToken(text, @"所有人")) {
            map[@"所有人"] = @""; // 高亮但不可点
            break;
        }
    }
    for (IMGroupMember *mem in members) {
        NSString *nick = mem.displayName;
        if (nick.length > 0 && !map[nick] && IMChatTextContainsMentionToken(text, nick)) {
            map[nick] = mem.userID;
        }
    }
    return map.count > 0 ? map : nil;
}

/// 切换中长文本的展开态并就地重配该行（高度随之增减，气泡内容重排）。
- (void)toggleTextExpandedForMessage:(IMMessageModel *)m atIndexPath:(NSIndexPath *)ip {
    if (!self.expandedTextKeys) { self.expandedTextKeys = [NSMutableSet set]; }
    NSString *key = [self textKeyForMessage:m];
    if ([self.expandedTextKeys containsObject:key]) { [self.expandedTextKeys removeObject:key]; }
    else { [self.expandedTextKeys addObject:key]; }
    [self.tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
}

/// 点击文本消息的分档路由：Huge→全屏阅读器；Long→展开/收起；Short→无操作。返回 YES 表示已消费该点击。
- (BOOL)handleLongTextTapForMessage:(IMMessageModel *)m atIndexPath:(NSIndexPath *)ip {
    if (![m.contentType isEqualToString:@"text"] || m.recalledAt > 0) { return NO; }
    NSString *content = m.content ?: @"";
    if (IMLooksLikeURL(content)) { return NO; } // 纯 URL 交给链接打开逻辑
    IMBubbleTextTier tier = [IMBubbleCell textTierForContent:content];
    if (tier == IMBubbleTextTierHuge) {
        __weak typeof(self) ws = self;
        IMTextReaderViewController *reader = [IMTextReaderViewController readerWithText:content mentions:[self mentionMapForMessage:m]];
        reader.onTapMentionUID = ^(NSString *uid) { [ws openMemberProfileForUID:uid]; }; // 阅读器内点 @昵称 → 关阅读器 + 跳资料
        [self presentViewController:reader animated:YES completion:nil];
        return YES;
    }
    if (tier == IMBubbleTextTierLong) {
        [self toggleTextExpandedForMessage:m atIndexPath:ip];
        return YES;
    }
    return NO;
}

/// 点击引用消息（有 replyToConvSeq）→ 跳到原消息；其余点击忽略。附件面板展开时点空白先收起面板（#3）。
- (void)handleReplyJumpTap:(UITapGestureRecognizer *)gr {
    if (self.selecting) {
        // 多选态：可选行交给表格勾选；点到发送中/失败的本地件（无勾选圈）直接提示原因，不静默。
        CGPoint sp = [gr locationInView:self.tableView];
        NSIndexPath *sip = [self.tableView indexPathForRowAtPoint:sp];
        if (sip && sip.row < (NSInteger)self.messages.count) {
            IMMessageModel *sm = self.messages[(NSUInteger)sip.row];
            if (sm.convSeq <= 0 && ![sm.contentType isEqualToString:@"system"]) {
                [self im_showToast:@"发送中/失败的消息不可选择"];
            }
        }
        return;
    }
    if (self.attachPanelVisible) { [self showAttachPanel:NO]; return; }
    // 先在「点击那一刻的稳定布局」上定位点中的消息——必须在收键盘之前：resignFirstResponder 触发的 inset
    // 变化会让坐标反查落到收起动画中间态的错行（曾表现为「跳到别的消息、高亮错行」）。
    CGPoint p = [gr locationInView:self.tableView];
    NSIndexPath *ip = [self.tableView indexPathForRowAtPoint:p];
    // @昵称 点击（气泡内）：必须在**收键盘前**用稳定布局命中——resign 会改 inset 让 cell 位移、坐标反查失准。
    // 命中某个挂了 uid 的 token → 跳该成员资料页（先于长文展开/引用跳转）。
    if (ip && ip.row < (NSInteger)self.messages.count) {
        UITableViewCell *hitCell = [self.tableView cellForRowAtIndexPath:ip];
        if ([hitCell isKindOfClass:IMBubbleCell.class]) {
            NSString *muid = [(IMBubbleCell *)hitCell mentionUIDAtPoint:[self.tableView convertPoint:p toView:hitCell]];
            if (muid.length > 0) { [self.inputField resignFirstResponder]; [self openMemberProfileForUID:muid]; return; }
        }
    }
    BOOL keyboardWasUp = self.kbInset > 0;
    [self.inputField resignFirstResponder]; // 点消息区任意处收起键盘（微信式；拖拽收起仍由 Interactive 模式负责）
    if (!ip || ip.row >= (NSInteger)self.messages.count) { return; }
    IMMessageModel *m = self.messages[(NSUInteger)ip.row];
    // 长文本（Q1）**先于**引用跳转判定：Long/Huge 文本气泡的展开/阅读器是整条点击触发，若被引用跳转抢先，
    // 作为引用发出的长文/超长文就永远点不开（内部已滤掉非文本/URL/撤回，短文本与媒体/文件引用照走下面的跳转）。
    if ([self handleLongTextTapForMessage:m atIndexPath:ip]) { return; }
    if (m.replyToConvSeq > 0) {
        int64_t target = m.replyToConvSeq;
        // 键盘正收起时，把定位滚动推迟到 inset 落定后——否则 scrollToRow 用即将失效的布局会停错位。
        if (keyboardWasUp) { [self runAfterKeyboardHidden:^{ [self jumpToConvSeq:target]; }]; }
        else { [self jumpToConvSeq:target]; }
        return;
    }
    if (m.recalledAt > 0) { return; }
    // 文件消息（M4-7）：自己发的保持应用内浏览器打开；收到的——已下载则本地 QuickLook 预览、未下载则点整条=触发下载。
    if ([m.contentType isEqualToString:@"file"]) {
        BOOL fileMine = [m.from isEqualToString:self.userID];
        if (fileMine) {
            [self openLink:[self fullMediaURL:m.content]];
        } else if ([self.downloads localFileForMessage:m]) {
            [self openCachedFile:m];
        } else {
            [self.downloads handleTapForMessage:m]; // 未下载/暂停/失败：点整条 = 点 ↓ 同效
        }
    }
}

/// 应用内浏览器打开链接（SFSafariViewController，仅接受 http/https）。
- (void)openLink:(NSString *)urlString {
    // 层3：本站邀请链接（/q/u 名片、/q/g 群码）→ 走扫码同款 resolve+路由（原生加群/名片流程），不出 App。
    if ([IMQRResultRouter routeInviteLinkIfOwn:urlString host:self.host userID:self.userID fromController:self]) { return; }
    NSURL *url = [NSURL URLWithString:urlString ?: @""];
    if (!url || !([url.scheme isEqualToString:@"http"] || [url.scheme isEqualToString:@"https"])) { return; }
    SFSafariViewController *safari = [[SFSafariViewController alloc] initWithURL:url];
    [self presentViewController:safari animated:YES completion:nil];
}

#pragma mark - 下载编排（收到的图片 / 视频 / 文件，M4-7）

/// 策略判定 / 门控态 / 点击路由 / 落地位置全在 `IMMediaDownloadCoordinator` 里（与会话详情页共用同一份实现）。
- (IMMediaDownloadCoordinator *)downloads {
    if (!_downloads) {
        _downloads = [[IMMediaDownloadCoordinator alloc] initWithHost:self.host
                                                             myUserID:self.userID
                                                              isGroup:self.isGroupChat];
        __weak typeof(self) ws = self;
        // 高频进度/门控内更新 → **就地**改可见 cell（绝不 reload）：这是"点下载页面卡死/列表跳变"的根因修复。
        _downloads.onProgress = ^(IMMessageModel *m, IMDownloadProgress *state) {
            [ws updateDownloadProgressForMessage:m state:state];
        };
        // 低频整条重配（下载完成/图片解除门控）→ reload 让 cellForRow 重跑，加载清晰图/▶/文件图标。
        _downloads.onStateChanged = ^(IMMessageModel *m) { [ws refreshRowForMessage:m]; };
    }
    return _downloads;
}

/// 下载进度**就地更新**（不 reload）：镜像上传的 updateUploadProgressForMessage:。相册→只刷那一格；
/// 单图/视频/文件气泡→调 cell 自身的 updateDownloadProgress:（只改环/角标/图标，行高不变、主线程不卡）。
- (void)updateDownloadProgressForMessage:(IMMessageModel *)m state:(IMDownloadProgress *)state {
    NSUInteger row = [self visibleRowForMessage:m];
    if (row == NSNotFound || (NSInteger)row >= [self.tableView numberOfRowsInSection:0]) { return; }
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)row inSection:0]];
    if ([cell isKindOfClass:IMAlbumCell.class]) {
        [(IMAlbumCell *)cell updateDownloadProgress:state forMessage:m];
    } else if ([cell isKindOfClass:IMImageCell.class]) {
        [(IMImageCell *)cell updateDownloadProgress:state];
    } else if ([cell isKindOfClass:IMBubbleCell.class]) {
        [(IMBubbleCell *)cell updateDownloadProgress:state];
    }
    // cell 不可见（滚出屏）：无需更新，下次滚回自然由 cellForRow 拿最新态。
}

/// 定点重配该消息的可见行（下载完成/图片解除门控）：相册成员映射到宫格 leader 行；媒体气泡行高不变。
/// 行数守卫同上传路径：消息可能刚 addObject 尚未 reloadData，此时定点 reloadRows 会触发行数断言崩溃 → 整表刷。
- (void)refreshRowForMessage:(IMMessageModel *)m {
    NSUInteger row = [self visibleRowForMessage:m];
    if (row == NSNotFound) { return; }
    if ((NSInteger)row >= [self.tableView numberOfRowsInSection:0]) { [self.tableView reloadData]; return; }
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:(NSInteger)row inSection:0]]
                          withRowAnimation:UITableViewRowAnimationNone];
}

/// 已下载的文件 → 本地 QuickLook 预览（不再丢给应用内浏览器）。
- (void)openCachedFile:(IMMessageModel *)m {
    NSURL *local = [self.downloads localFileForMessage:m];
    if (!local) { return; }
    self.quickLookURL = local;
    QLPreviewController *ql = [QLPreviewController new];
    ql.dataSource = self;
    [self presentViewController:ql animated:YES completion:nil];
}

- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller {
    return self.quickLookURL ? 1 : 0;
}

- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index {
    return self.quickLookURL;
}

/// 跳转到被引用的原消息：滚到该 conv_seq 行并高亮一闪（与 Web quoteflash 同节奏，1.2s）。
- (void)jumpToConvSeq:(int64_t)targetConvSeq {
    // 本页不在栈顶（从全屏媒体库 IMConversationMediaViewController、合并记录等 push 页里点「定位」进来，
    // 且弹层查看器已 dismiss）→ 先弹回本聊天页再滚，否则滚动发生在被覆盖的表上、用户看不到跳转（全屏库定位失效即此）。
    UINavigationController *nav = self.navigationController;
    if (nav && nav.topViewController != self && [nav.viewControllers containsObject:self]) {
        [nav popToViewController:self animated:YES];
        // pop 动画进行中滚动会落错位；挂转场协调器完成回调，等 pop 落定再跳（无协调器回落下一轮 runloop）。
        id<UIViewControllerTransitionCoordinator> tc = nav.transitionCoordinator;
        if (tc) {
            [tc animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> ctx) {
                [self jumpToConvSeq:targetConvSeq];
            }];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{ [self jumpToConvSeq:targetConvSeq]; });
        }
        return;
    }
    int64_t earliest = 0; // 当前已加载最早 conv_seq(>0)，用于区分"未加载到"与"已删除"
    for (NSUInteger i = 0; i < self.messages.count; i++) {
        int64_t s = self.messages[i].convSeq;
        if (s > 0 && (earliest == 0 || s < earliest)) { earliest = s; }
        if (s == targetConvSeq) {
            // 相册成员行本身零高（宫格整体画在 leader 行）：直接滚到成员下标会落在不可见行、高亮闪不出来。
            // 统一经 visibleRowForMessage 映射到该相册的 leader 行（普通消息即自身行）。
            NSUInteger visRow = [self visibleRowForMessage:self.messages[i]];
            NSInteger targetRow = (visRow == NSNotFound) ? (NSInteger)i : (NSInteger)visRow;
            NSIndexPath *ip = [NSIndexPath indexPathForRow:targetRow inSection:0];
            [self.tableView scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
            // 等滚动动画到位后再闪（已在视口时 scrollToRow 也可能微调，同样适用）。
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ [self flashRowAtIndexPath:ip]; });
            return;
        }
    }
    // 跳不到分两种：落在窗口内却缺失 → 已被本地删除；目标比"已加载最早一条"还早（或全表无已确认消息，
    // earliest=0 判不出窗口）→ 本地没有。iOS 无上拉分页（全量载本地库），故不提示"上拉加载"，与 Web 文案刻意有别（CHAT_UX §3.1）。
    NSString *toast = (earliest == 0 || targetConvSeq < earliest)
        ? @"原消息不在本地" : @"原消息已被删除";
    [self im_showToast:toast];
}

/// 目标行高亮一闪：在气泡/卡片（previewTargetView）上盖一层强调色遮罩淡出——
/// 不动 cell 自身背景（图片 cell 改背景色看不见），对所有 cell 类型通吃。
- (void)flashRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:ip];
    if (!cell) { return; }
    UIView *target = [cell respondsToSelector:@selector(previewTargetView)]
        ? [(id)cell previewTargetView] : cell.contentView;
    if (!target) { return; }
    UIView *flash = [[UIView alloc] initWithFrame:target.bounds];
    flash.backgroundColor = [IMTheme.accent colorWithAlphaComponent:0.35];
    flash.layer.cornerRadius = target.layer.cornerRadius;
    flash.userInteractionEnabled = NO;
    flash.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [target addSubview:flash];
    [UIView animateWithDuration:0.9 delay:0.3 options:UIViewAnimationOptionCurveEaseOut
                     animations:^{ flash.alpha = 0; }
                     completion:^(BOOL finished) { [flash removeFromSuperview]; }];
}

- (void)handleSendResult:(BOOL)success convSeq:(int64_t)convSeq error:(NSError *)error forClientMsgID:(NSString *)clientMsgID {
    // 结果到来前先记录是否贴底：被拒收会给该条挂"系统行"，cell 随之变高，
    // 不重新贴底则系统行被顶出屏幕（需手动下滚才可见）。自己发的消息贴底（CHAT_UX §9）。
    BOOL wasNearBottom = [self isNearBottom];
    for (IMMessageModel *m in self.messages) {
        if ([m.clientMsgID isEqualToString:clientMsgID]) {
            m.status = success ? IMMessageStatusSent : IMMessageStatusFailed;
            // 被拒收 → 把服务端友好文案挂到 note，气泡下方居中显示（微信式系统行）；其余失败（如 ack 超时）不挂 note，仍显"未发送 ✗"。
            // 覆盖：被拉黑 200102 / 非好友 200103 / 被禁言 300004 / 非群成员 300203 / 群全员禁言 300206 / 成员级禁言 300208（G2）
            //     / 内容过大 300001（合并转发套娃膨胀超上限，后端回「消息内容过大，无法发送」，无恢复入口）。
            m.note = (!success && (error.code == 200102 || error.code == 200103 || error.code == 300004 ||
                                   error.code == 300203 || error.code == 300206 || error.code == 300208 || error.code == 300001)) ? error.localizedDescription : nil;
            m.noteCode = m.note ? error.code : 0; // 瞬态：决定系统行是否给恢复入口（200103 → 发好友申请）
            m.convSeq = convSeq;
            if (![self performDatabaseOperation:^(IMDatabase *database) {
                [database saveMessage:m]; // upsert：更新状态/conv_seq/note（含被拒文案，重进会话不丢）
            }]) { return; }
            if (convSeq > 0) { [self.seenConvSeqs addObject:@(convSeq)]; } // 防 sync 重复回显自己发的
            // 相册成员的 ACK 只定点刷宫格角标/状态胶囊（全表 reloadData 是批量发送闪屏的元凶之一）。
            if (m.groupID.length > 0) {
                [self refreshVisibleCellForMessage:m];
                return;
            }
            break;
        }
    }
    [self.tableView reloadData];
    if (wasNearBottom) { [self scrollToBottomAnimated:YES]; } // 贴底则把（变高后的）该条+系统行滚入视口
}

#pragma mark - IMSocketManagerDelegate（主线程回调）

- (void)socketManager:(IMSocketManager *)manager didChangeState:(IMSocketState)state {
    BOOL justConnected = (state == IMSocketStateConnected && self.connState != IMSocketStateConnected);
    self.connState = state;
    [self updateTitle];
    if (justConnected) {
        // 连上即补拉在线态快照，覆盖三种情况：①冷启动直接进本页时 currentToken 还是空的，
        // viewWillAppear 里那次拉取被静默跳过且无人重试；②断线期间对端状态已变，本地快照过期；
        // ③服务端重连竞态可能短暂把在线用户报成离线，重拉即纠正。
        [self refreshPeerPresence];
        [self updatePeerWatch:YES]; // watch 是连接级易失态：重连后必须重发，否则对端上线不再推达
    }
    if (state == IMSocketStateConnected) {
        [self markVisibleRowsRead]; // 重连后把当前可见的补报一次已读（可见即读）
    }
}

/// 标题：单聊=对方 uid；群聊=群名。连接态不再拼进标题后缀，统一走副标题（见 im_navigationSubtitle）。
- (void)updateTitle {
    if (self.isGroupChat) {
        self.title = self.groupName.length > 0 ? self.groupName : @"群聊";
    } else {
        self.title = self.peerID;
    }
    [self refreshUnifiedNavigationBar];
}

- (BOOL)im_isGroupChat { return self.isGroupChat; }

- (NSString *)im_navigationSubtitle {
    if (self.peerTyping) {
        return @"正在输入";
    }
    // 连接态优先：断开 / 连接中时副标题显示连接状态（同「在线」位置，无括号），
    // 覆盖单聊在线态与群聊成员数——此时本地在线快照无法再更新，显示连接态才是可验证的状态。
    NSString *conn = IMSocketStateSubtitle(self.connState);
    if (conn.length > 0) { return conn; }
    if (!self.isGroupChat) {
        // 单聊：在线态走副标题（原先的 🟢 已去掉）。
        return self.peerPresence.subtitleText ?: @"";
    }
    NSUInteger count = self.groupInfo.members.count;
    return count > 0 ? [NSString stringWithFormat:@"%lu 位成员", (unsigned long)count] : @"";
}

/// 消息排序（**唯一入口**，与 IMDatabase.messagesForConv 的 ORDER BY 及 im-web 的渲染排序三方一致）：
/// **时间戳主排**；同一毫秒时 conv_seq=0（待发/失败）视为最大值垫底，收到的（conv_seq>0）在前。
///
/// ⚠️ 曾出过的坑（2026-08-05）：这里原先与 DB 一样按 conv_seq 主排、且把 conv_seq=0 一律甩末尾。
/// 被拒收的消息**永远** conv_seq=0，于是永久钉在最底部，之后收到的消息全插到它上面 —— 用户滚到底
/// 只见旧的失败消息、以为新消息没收到。第一次进会话走 DB（当时已修）看着正常，Web 一发消息触发本
/// comparator 重排，时序又坏 —— **同一个 bug 在 DB 与内存两处各写了一遍**，故收敛到这一个方法。
- (void)sortMessagesInPlace {
    [self.messages sortUsingComparator:^NSComparisonResult(IMMessageModel *a, IMMessageModel *b) {
        if (a.timestamp != b.timestamp) {
            return a.timestamp < b.timestamp ? NSOrderedAscending : NSOrderedDescending;
        }
        // 同毫秒：conv_seq=0 视为 +∞ 垫底（等价 im-web 的 `convSeq || MAX_SAFE_INTEGER`）。
        int64_t sa = a.convSeq > 0 ? a.convSeq : INT64_MAX;
        int64_t sb = b.convSeq > 0 ? b.convSeq : INT64_MAX;
        if (sa == sb) { return NSOrderedSame; }
        return sa < sb ? NSOrderedAscending : NSOrderedDescending;
    }];
}

- (void)socketManager:(IMSocketManager *)manager didReceiveMessage:(IMMessageModel *)message {
    if (![self performDatabaseOperation:^(IMDatabase *database) {
        [database saveMessage:message]; // 任何会话的消息都落库（按 conv_seq 幂等）
    }]) { return; }
    if (![message.convID isEqualToString:self.convID]) { return; } // 非本会话不在此页显示
    // 同一条消息可能既被 new_msg 推送、又被 sync_resp 拉到，按 conv_seq 去重。
    if (message.convSeq > 0) {
        NSNumber *key = @(message.convSeq);
        if ([self.seenConvSeqs containsObject:key]) {
            // 完整历史校正会再次下发已经实时上屏的消息。不能重复插入，但要让权威元数据回填当前内存模型；
            // 否则 SQLite 已从 0 修复成真实 file_size，当前页面仍会一直显示 0 KB，直到重新进入会话。
            if ([message.contentType isEqualToString:@"file"] && message.fileSize > 0) {
                for (IMMessageModel *existing in self.messages) {
                    if (existing.convSeq != message.convSeq) { continue; }
                    existing.fileSize = message.fileSize;
                    if (message.fileName.length > 0) { existing.fileName = message.fileName; }
                    if (message.serverMsgID.length > 0) { existing.serverMsgID = message.serverMsgID; }
                    [self.tableView reloadData];
                    break;
                }
            }
            return;
        }
        [self.seenConvSeqs addObject:key];
    }
    // 收到新消息：贴底才自动贴底；在上方看历史则不打断，累加到"↓N"（CHAT_UX §9）。
    BOOL wasNearBottom = [self isNearBottom];
    // 绝大多数消息按序到达：直接尾插即保持有序，省掉每条都做的 O(n log n) 全量重排。
    // 仅当来的消息落在末条之前（乱序/补拉插队）才重排一次——判定口径与 sortMessagesInPlace 的
    // comparator 严格一致（timestamp 主序，同毫秒时 conv_seq=0 视为 +∞ 垫底）。
    IMMessageModel *lastMsg = self.messages.lastObject;
    BOOL needsSort = NO;
    if (lastMsg) {
        if (message.timestamp < lastMsg.timestamp) {
            needsSort = YES;
        } else if (message.timestamp == lastMsg.timestamp) {
            int64_t sNew = message.convSeq > 0 ? message.convSeq : INT64_MAX;
            int64_t sLast = lastMsg.convSeq > 0 ? lastMsg.convSeq : INT64_MAX;
            needsSort = sNew < sLast;
        }
    }
    [self.messages addObject:message];
    if (needsSort) { [self sortMessagesInPlace]; }
    [self.tableView reloadData];
    // 冷启动直进本页时 init 读库可能为空（账号数据库上下文未就绪），历史全靠 sync 事后补进——
    // 而 reloadData 不触发 VC 的 viewDidLayoutSubviews，进会话定位永远不会跑（模拟器日志实锤：
    // 该场景整个会话周期零 chat_initial_position）。首条消息落地时在此补一次定位。
    if (!self.didInitialPosition) {
        [self positionInitialIfNeeded];
        return; // positionInitialIfNeeded 内已含精确贴底/锚定 + markVisibleRowsRead
    }
    if (wasNearBottom) { [self scrollToBottomAnimated:YES]; }
    // 可见即读 + ↓N 刷新：贴底时新消息进视口即标已读；在上方看历史则不读、↓N 计数 +1（markVisibleRowsRead 内重算）。
    [self markVisibleRowsRead];
}

/// 对端已读到 upToConvSeq → 记录并刷新（已送达 → 已读）。
- (void)socketManager:(IMSocketManager *)manager didReadConv:(NSString *)convID by:(NSString *)from upToConvSeq:(int64_t)convSeq {
    if (![convID isEqualToString:self.convID] || [from isEqualToString:self.userID]) { return; }
    // 群聊：单个 peerReadSeq 无法表达「谁读到哪」，任一成员已读都推进会让所有人消息误显 ✓✓（已读）。
    // 群的已读语义走 IMReadReceiptViewController 的逐成员列表，气泡尾巴只保留 ✓（已送达）。
    if (self.isGroupChat) { return; }
    if (convSeq > self.peerReadSeq) {
        self.peerReadSeq = convSeq;
        [self.tableView reloadData];
    }
}

/// 对端正在输入 → 标题栏副标题暂显「正在输入」，3s 后恢复在线态/成员数。
- (void)socketManager:(IMSocketManager *)manager didTypingInConv:(NSString *)convID by:(NSString *)from {
    if (![convID isEqualToString:self.convID] || [from isEqualToString:self.userID]) { return; }
    self.peerTyping = YES;
    [self updateTitle];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideTyping) object:nil];
    [self performSelector:@selector(hideTyping) withObject:nil afterDelay:3.0];
}

- (void)hideTyping {
    self.peerTyping = NO;
    [self updateTitle];
}

/// 对端上线 → 更新副标题。（服务端不推下线：租约到期后 subtitleText 自动降级。）
- (void)socketManager:(IMSocketManager *)manager didChangePresenceForUser:(NSString *)user presence:(IMPresence *)presence {
    if (![user isEqualToString:self.peerID]) { return; }
    self.peerPresence = presence;
    [self updateTitle];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self sendTapped];
    return NO;
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.messages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMMessageModel *m = self.messages[indexPath.row];
    // 首条未读行只算一次（firstUnreadRow 是 O(k) 扫描且各 cell 分支都要用），各分支复用。
    // 相册部分已读：首条未读可能落在被折叠的 follower 行，映射到其 leader 行，保证分割线画在可见行上。
    NSInteger firstUnread = [self firstUnreadRow];
    if (firstUnread >= 0) {
        NSUInteger vis = [self visibleRowForMessage:self.messages[firstUnread]];
        if (vis != NSNotFound) { firstUnread = (NSInteger)vis; }
    }
    BOOL rowIsFirstUnread = (indexPath.row == firstUnread);
    // 系统消息（群邀请/移除/转让/禁言等留痕）：独立居中灰字行，无气泡/头像/时间勾。
    if ([m.contentType isEqualToString:@"system"]) {
        IMSystemCell *sys = [tableView dequeueReusableCellWithIdentifier:@"system" forIndexPath:indexPath];
        [sys configureWithText:m.content];
        return sys;
    }
    // 撤回消息（M4-1）：居中系统行"你/对方撤回了一条消息"，隐藏原气泡；本人文本可"重新编辑"回填输入框。
    if (m.recalledAt > 0) {
        BOOL mineR = [m.from isEqualToString:self.userID];
        IMSystemCell *sys = [tableView dequeueReusableCellWithIdentifier:@"system" forIndexPath:indexPath];
        NSString *who = mineR ? @"你" : (self.isGroupChat ? [self senderNameForMessage:m] : @"对方");
        NSString *text = [NSString stringWithFormat:@"%@撤回了一条消息", who];
        BOOL canReedit = mineR && [m.contentType isEqualToString:@"text"] && m.content.length > 0;
        __weak typeof(self) ws = self;
        NSString *original = m.content ?: @"";
        [sys configureWithText:text reeditHandler:canReedit ? ^{
            ws.inputField.text = original;
            [ws updateSendButtonVisibility];
            [ws.inputField becomeFirstResponder];
        } : nil];
        return sys;
    }
    // 合并转发（#3）：聊天记录卡片，点击进详情页看全部。
    if ([m.contentType isEqualToString:@"chat_record"]) {
        IMChatRecordCell *rec = [tableView dequeueReusableCellWithIdentifier:@"record" forIndexPath:indexPath];
        BOOL mineR = [m.from isEqualToString:self.userID];
        BOOL grpR = self.isGroupChat && !mineR;                              // 群聊对方
        BOOL firstR = grpR && [self isFirstInSenderRun:indexPath.row];       // 连续段首条→显示名
        BOOL lastR = grpR && [self isLastInSenderRun:indexPath.row];         // 连续段末条→显示头像
        [rec configureWithMessage:m mine:mineR senderName:(firstR ? [self senderNameForMessage:m] : nil)
                       senderRole:(firstR ? [self senderRoleForMessage:m] : IMGroupRoleMember)];
        [rec applyGroupAvatarURL:(grpR ? [self senderAvatarURLForMessage:m] : nil)
                            seed:(m.from ?: @"") name:(grpR ? [self senderNameForMessage:m] : nil)
                      showAvatar:lastR gutter:grpR];
        [rec applyUnreadDivider:rowIsFirstUnread]; // 首条未读为聊天记录卡片时也显分割线
        __weak typeof(self) ws = self;
        rec.onTap = ^{ [ws openChatRecord:m]; };
        // 被拒收系统行的恢复入口（非好友 200103 → 发好友申请；合并转发发给非好友会命中）。
        __weak typeof(self) wsNote = self;
        rec.onNoteActionTap = ^{ [wsNote sendFriendRequestFromRejectedNote]; };
        // 群聊对方头像点击 → 该成员资料页（单聊/自己不挂）。
        if (grpR) {
            NSString *memberUID = m.from;
            __weak typeof(self) wsAvatar = self;
            rec.onAvatarTap = ^{ [wsAvatar openMemberProfileForUID:memberUID]; };
        }
        return rec;
    }
    // 纯 URL 文本消息：URL 文本 + 链接富预览卡片（OG），点击应用内打开（带引用时也显示引用行+卡片）。
    if ([m.contentType isEqualToString:@"text"] && m.recalledAt == 0 && m.translation.length == 0 && IMLooksLikeURL(m.content)) {
        IMLinkCardCell *link = [tableView dequeueReusableCellWithIdentifier:@"link" forIndexPath:indexPath];
        BOOL mineL = [m.from isEqualToString:self.userID];
        BOOL grpL = self.isGroupChat && !mineL;
        BOOL firstL = grpL && [self isFirstInSenderRun:indexPath.row];
        BOOL lastL = grpL && [self isLastInSenderRun:indexPath.row];
        [link configureWithMessage:m mine:mineL senderName:(firstL ? [self senderNameForMessage:m] : nil)
                        senderRole:(firstL ? [self senderRoleForMessage:m] : IMGroupRoleMember)];
        [link applyGroupAvatarURL:(grpL ? [self senderAvatarURLForMessage:m] : nil)
                             seed:(m.from ?: @"") name:(grpL ? [self senderNameForMessage:m] : nil)
                       showAvatar:lastL gutter:grpL];
        [link applyUnreadDivider:rowIsFirstUnread]; // 首条未读为链接卡片时也显分割线
        // 群聊对方头像点击 → 该成员资料页（单聊/自己不挂；与文本气泡/图片/相册统一）。
        if (grpL) {
            NSString *memberUID = m.from;
            __weak typeof(self) wsAvatar = self;
            link.onAvatarTap = ^{ [wsAvatar openMemberProfileForUID:memberUID]; };
        }
        __weak typeof(self) ws = self;
        link.onTap = ^(NSString *url) { [ws openLink:url]; };
        // OG 预览异步展开 → 刷行高（滚动中延迟到停止；与 IMImageCell.onMediaSizeResolved 同守卫）。
        link.onContentSizeResolved = ^{
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            if (self.tableView.isDragging || self.tableView.isDecelerating) {
                self.needsRowHeightSettle = YES;
                return;
            }
            BOOL wasNearBottom = [self isNearBottom];
            [self refreshRowHeightsWithoutAnimation];
            if (wasNearBottom) { [self scrollToAbsoluteBottom]; }
        };
        return link;
    }
    // 相册宫格（M4+）：同 group_id 的多图/视频合并为一个 cell（leader 行渲染宫格，从行零高）。
    if ([self isAlbumMember:m]) {
        if ([self isAlbumFollowerAtRow:indexPath.row]) {
            UITableViewCell *pad = [tableView dequeueReusableCellWithIdentifier:@"albumPad" forIndexPath:indexPath];
            pad.hidden = YES;
            pad.selectionStyle = UITableViewCellSelectionStyleNone;
            return pad;
        }
        IMAlbumCell *alb = [tableView dequeueReusableCellWithIdentifier:@"album" forIndexPath:indexPath];
        NSArray<IMMessageModel *> *members = [self albumMembersForGroupID:m.groupID];
        BOOL mineAlb = [m.from isEqualToString:self.userID];
        BOOL grpAlb = self.isGroupChat && !mineAlb;                                  // 群聊对方
        BOOL firstAlb = grpAlb && [self isFirstInSenderRun:indexPath.row];           // 连续段首条→显示名
        BOOL lastAlb = grpAlb && [self isLastInSenderRun:indexPath.row];             // 连续段末条→显示头像
        NSString *senderNameAlb = firstAlb ? [self senderNameForMessage:m] : nil;
        IMGroupRole senderRoleAlb = firstAlb ? [self senderRoleForMessage:m] : IMGroupRoleMember;
        // 逐格下载门控（M4-7）：必须在 configure **前**挂好——bind 每一格时会回调查询该格的门控态。
        __weak typeof(self) wsAlbDl = self;
        alb.downloadStateForItem = ^IMDownloadProgress *(IMMessageModel *mm) {
            __strong typeof(wsAlbDl) self = wsAlbDl;
            return self ? [self.downloads stateForMessage:mm] : nil;
        };
        alb.onDownloadItem = ^(IMMessageModel *mm) {
            __strong typeof(wsAlbDl) self = wsAlbDl;
            if (self) { [self.downloads handleTapForMessage:mm]; }
        };
        [alb configureWithMembers:members mine:mineAlb host:self.host
                         previews:self.outboxPreviews progress:self.outboxProgress senderName:senderNameAlb
                       senderRole:senderRoleAlb];
        [alb applyGroupAvatarURL:(grpAlb ? [self senderAvatarURLForMessage:m] : nil)
                            seed:(m.from ?: @"") name:(grpAlb ? [self senderNameForMessage:m] : nil)
                      showAvatar:lastAlb gutter:grpAlb];
        [alb applyUnreadDivider:rowIsFirstUnread]; // 首条未读为相册宫格时也显分割线
        // 群聊对方头像点击 → 该成员资料页（单聊/自己不挂；与文本气泡/图片/链接统一）。
        if (grpAlb) {
            NSString *memberUID = m.from;
            __weak typeof(self) wsAvatar = self;
            alb.onAvatarTap = ^{ [wsAvatar openMemberProfileForUID:memberUID]; };
        }
        __weak typeof(self) wsAlbNote = self;
        alb.onNoteActionTap = ^{ [wsAlbNote sendFriendRequestFromRejectedNote]; };
        __weak typeof(self) ws = self;
        alb.onTapItem = ^(IMMessageModel *mm) {
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            // 待发格（排队/压缩/上传/失败）：走与单张气泡同一状态机——⏸↔↑ 暂停恢复、↻ 重试、✕ 确认取消。
            BOOL pendingTile = [IMPendingMediaStore isLocalRef:mm.content]
                || (mm.convSeq <= 0 && mm.content.length == 0
                    && (mm.status == IMMessageStatusSending || mm.status == IMMessageStatusFailed));
            if (pendingTile) { [self handlePendingMediaTap:mm]; return; }
            if (mm.content.length > 0) { [self presentMediaViewerForMessage:mm preloaded:nil]; }
        };
        alb.menuForItem = ^UIMenu *(IMMessageModel *mm) {
            __strong typeof(ws) self = ws;
            if (!self) { return nil; }
            // 待发格也给长按菜单（含「取消发送」——可单独取消宫格里的某一项）。
            return [IMMenuAction menuWithActions:[self messageActionsForMessage:mm
                                                                           mine:[mm.from isEqualToString:self.userID]]];
        };
        return alb;
    }
    // 图片/视频消息（M4-6）：独立媒体 cell。图片显缩略图、视频显首帧+播放角标（不自动播放）；点击进全屏查看器。
    // 上传中的乐观气泡：content 为空 → 显本地预览 + 居中进度（批量发送 UX）。
    if ([m.contentType isEqualToString:@"image"] || [m.contentType isEqualToString:@"video"]) {
        IMImageCell *img = [tableView dequeueReusableCellWithIdentifier:@"image" forIndexPath:indexPath];
        BOOL mineI = [m.from isEqualToString:self.userID];
        NSString *key = m.clientMsgID ?: @"";
        BOOL grpI = self.isGroupChat && !mineI;
        BOOL firstI = grpI && [self isFirstInSenderRun:indexPath.row];
        BOOL lastI = grpI && [self isLastInSenderRun:indexPath.row];
        NSString *senderNameI = firstI ? [self senderNameForMessage:m] : nil;
        IMGroupRole senderRoleI = firstI ? [self senderRoleForMessage:m] : IMGroupRoleMember;
        // 本地待发（im-pending://）不是网络地址：只显本地缩略图，绝不拿它去拼 URL 发请求。
        // 本地待发件 = content 已是 im-pending:// 引用，**或**还没走到落盘那步（排队/压缩期 content 为空）。
        // 后者漏掉的话，排队期点中心 ✕ 会被当成"打开查看器"（URL 为空 → 看起来没反应）。
        BOOL pendingLocal = [IMPendingMediaStore isLocalRef:m.content]
            || (m.convSeq <= 0 && m.content.length == 0
                && (m.status == IMMessageStatusSending || m.status == IMMessageStatusFailed));
        UIImage *previewI = pendingLocal ? [self pendingPreviewForMessage:m] : self.outboxPreviews[key];
        NSString *imgFullURL = ((m.content.length > 0 && !pendingLocal) ? [self fullMediaURL:m.content] : @"");
        // 门控（M4-7）：收到的图片/视频按策略"未下载" → 显 ↓（下载中为环形进度）+ 尺寸角标，不加载原图/不放行播放。
        // 视频封面仍照显（poster 只有几十 KB），门控挡的是**整段视频**。
        IMDownloadProgress *gate = pendingLocal ? nil : [self.downloads stateForMessage:m];
        img.gated = gate != nil;
        img.downloadProgress = gate;
        [img configureWithMessage:m
                          fullURL:imgFullURL
                        posterURL:(m.poster.length > 0 ? [self fullMediaURL:m.poster] : nil)
                             mine:mineI peerReadSeq:self.peerReadSeq
                     previewImage:previewI senderName:senderNameI senderRole:senderRoleI];
        [img applyGroupAvatarURL:(grpI ? [self senderAvatarURLForMessage:m] : nil)
                            seed:(m.from ?: @"") name:(grpI ? [self senderNameForMessage:m] : nil)
                      showAvatar:lastI gutter:grpI];
        [img applyUnreadDivider:rowIsFirstUnread]; // 首条未读为图片/视频时也显分割线
        // 群聊对方头像点击 → 该成员资料页（单聊/自己不挂；与文本气泡/相册/链接统一）。
        if (grpI) {
            NSString *memberUID = m.from;
            __weak typeof(self) wsAvatar = self;
            img.onAvatarTap = ^{ [wsAvatar openMemberProfileForUID:memberUID]; };
        }
        // 失败的本地待发件：进度角标显"发送失败"（内存里的进度在重进会话后是空的，按状态补上）。
        IMUploadProgress *progI = self.outboxProgress[key];
        if (!progI && pendingLocal && m.status == IMMessageStatusFailed) { progI = [IMUploadProgress failedProgress]; }
        [img setUploadProgress:progI];
        __weak typeof(self) ws = self;
        img.onNoteActionTap = ^{ [ws sendFriendRequestFromRejectedNote]; };
        img.onDownloadTap = ^{ // 门控点 ↓：图片=解除门控重载；视频=下载状态机（M4-7）
            __strong typeof(ws) self = ws;
            if (self) { [self.downloads handleTapForMessage:m]; }
        };
        img.onTap = ^(UIImage *image) {
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            if (pendingLocal) { [self handlePendingMediaTap:m]; return; } // 中心按钮状态机：⏸/↑/↻/✕
            [self presentMediaViewerForMessage:m preloaded:image];
        };
        // 老消息无 media_w/h：异步出图后才知比例 → 刷一次行高（无动画，不打断滚动）。
        // 行高变化会把底部偏移顶走——若此刻本就贴底（典型：刚进会话），必须重新贴底，
        // 否则用户看到的是"进来没停在最新消息"。上滚读历史时不动（wasNearBottom=NO）。
        IMMessageModel *mediaMsg = m;
        img.onMediaSizeResolved = ^(CGSize pixelSize) {
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            // 量出的尺寸写回模型 + 落库（一次性成本）：此后 estimatedHeight 首帧即正确，
            // 同一条消息不会每次滚过/重进会话都触发一遍行高跳变（上滑弹跳的主根因）。
            if (mediaMsg.mediaW <= 0 && pixelSize.width > 0 && pixelSize.height > 0) {
                mediaMsg.mediaW = (NSInteger)round(pixelSize.width);
                mediaMsg.mediaH = (NSInteger)round(pixelSize.height);
                if (mediaMsg.convSeq > 0) {
                    [self performDatabaseOperation:^(IMDatabase *database) { [database saveMessage:mediaMsg]; }];
                }
            }
            // 拖拽/惯性滚动中不做 begin/endUpdates（行高瞬变 + offset 修正 = 肉眼可见的卡顿弹跳），
            // 记脏、滚动停止后统一补一次。
            if (self.tableView.isDragging || self.tableView.isDecelerating) {
                self.needsRowHeightSettle = YES;
                return;
            }
            BOOL wasNearBottom = [self isNearBottom];
            [self refreshRowHeightsWithoutAnimation];
            if (wasNearBottom) { [self scrollToAbsoluteBottom]; }
        };
        return img;
    }
    IMBubbleCell *cell = [tableView dequeueReusableCellWithIdentifier:@"bubble" forIndexPath:indexPath];
    BOOL mine = [m.from isEqualToString:self.userID];
    BOOL showsDivider = rowIsFirstUnread;
    // 群聊：对方气泡带发送者昵称（自己/单聊不带）；连续同发送者只首条显名、末条显头像（Telegram 式）。
    BOOL grp = self.isGroupChat && !mine;
    BOOL firstInRun = grp && [self isFirstInSenderRun:indexPath.row];
    BOOL lastInRun = grp && [self isLastInSenderRun:indexPath.row];
    NSString *senderName = firstInRun ? [self senderNameForMessage:m] : nil;
    // 引用的是图片/视频：把原消息的媒体 URL 传给 cell，引用条内显示真缩略图（#4）。
    // 引用的是图片/视频：把完整媒体地址 + 内嵌 thumb 交给 cell，由 IMMediaPlaceholder 统一决定
    // 真帧(仅已下载)/thumb 磨砂/占位图标（门控一致 M4-7）。绝不为一张 24px 引用小图联网拉原件/抽远端帧。
    NSString *replyThumbURL = nil;   // 完整媒体地址（有媒体引用目标即置）
    NSString *replyThumbData = nil;  // 内嵌 thumb dataURI
    BOOL replyThumbIsVideo = NO;
    if (m.replyToConvSeq > 0) {
        IMMessageModel *target = [self messageWithConvSeq:m.replyToConvSeq];
        if (target && ([target.contentType isEqualToString:@"image"] || [target.contentType isEqualToString:@"video"])
            && target.recalledAt == 0 && target.content.length > 0) {
            replyThumbIsVideo = [target.contentType isEqualToString:@"video"];
            replyThumbURL = [self fullMediaURL:target.content];
            replyThumbData = target.thumb;
        }
    }
    // 文件上传中/失败：左侧图标位显圆环状态机、第二行显进度（必须在 configure 之前设，整条一次性布好）。
    NSString *bubbleKey = m.clientMsgID ?: @"";
    IMUploadProgress *fileProgress = self.outboxProgress[bubbleKey];
    if (!fileProgress && [m.contentType isEqualToString:@"file"] && m.status == IMMessageStatusFailed
        && [IMPendingMediaStore isLocalRef:m.content]) {
        fileProgress = [IMUploadProgress failedProgress]; // 重进会话：内存进度已空，按落库状态补
    }
    cell.uploadProgress = fileProgress;
    // 收到的文件：下载态（M4-7）。自己发的走上传态、二者互斥；有上传态时不叠加下载态。
    cell.downloadProgress = (!mine && !fileProgress && [m.contentType isEqualToString:@"file"])
        ? [self.downloads stateForMessage:m] : nil;
    // 图标位点击：上传态=发送状态机（⏸/↑/↻/✕）；下载态=下载状态机（↓/⏸/↻）；就绪/完成态不挂（点整条气泡打开）。
    if (fileProgress && [m.contentType isEqualToString:@"file"]) {
        __weak typeof(self) wsFile = self;
        cell.onFileControlTap = ^{
            __strong typeof(wsFile) self = wsFile;
            if (self) { [self handlePendingMediaTap:m]; }
        };
    } else if (cell.downloadProgress && [m.contentType isEqualToString:@"file"]) {
        __weak typeof(self) wsDl = self;
        cell.onFileControlTap = ^{
            __strong typeof(wsDl) self = wsDl;
            if (self) { [self.downloads handleTapForMessage:m]; }
        };
    } else {
        cell.onFileControlTap = nil;
    }
    // 群聊对方头像点击 → 该成员资料页（单聊/自己不挂）。
    if (self.isGroupChat && ![m.from isEqualToString:self.userID]) {
        NSString *memberUID = m.from;
        __weak typeof(self) wsAvatar = self;
        cell.onAvatarTap = ^{ [wsAvatar openMemberProfileForUID:memberUID]; };
    } else {
        cell.onAvatarTap = nil;
    }
    // 拒收系统行的恢复入口（非好友 200103 → 发好友申请）。cell 内部据 noteCode 判定是否可点。
    __weak typeof(self) wsNote = self;
    cell.onNoteActionTap = ^{ [wsNote sendFriendRequestFromRejectedNote]; };
    NSString *replyFromName = (self.isGroupChat && m.replyToConvSeq > 0 && m.replyToFrom.length > 0)
        ? [self replyFromNameForUID:m.replyToFrom] : nil;
    cell.textExpanded = [self isTextExpandedForMessage:m]; // 中长文本"展开全文"记忆（configure 前置）
    cell.mentionMap = [self mentionMapForMessage:m];       // 气泡内 @昵称 高亮+跳资料映射（configure 前置）
    [cell configureWithMessage:m mine:mine peerReadSeq:self.peerReadSeq
                     dayHeader:[self dayHeaderForRow:indexPath.row]
            showsUnreadDivider:showsDivider
                    senderName:senderName
                    senderRole:(firstInRun ? [self senderRoleForMessage:m] : IMGroupRoleMember)
                 replyThumbURL:replyThumbURL
                replyThumbData:replyThumbData
             replyThumbIsVideo:replyThumbIsVideo
                 replyFromName:replyFromName];
    [cell applyGroupAvatarURL:(grp ? [self senderAvatarURLForMessage:m] : nil)
                         seed:(m.from ?: @"") name:(grp ? [self senderNameForMessage:m] : nil)
                   showAvatar:lastInRun gutter:grp];
    return cell;
}

#pragma mark - 相册聚簇（M4+：同 group_id 的多图/视频渲染为一个宫格）

/// 相册成员判定：有 group_id 的图片/视频且未撤回。**多选态不聚簇**（展开成独立行以便逐条勾选/转发）。
- (BOOL)isAlbumMember:(IMMessageModel *)m {
    return !self.selecting && m.groupID.length > 0 && m.recalledAt == 0
        && ([m.contentType isEqualToString:@"image"] || [m.contentType isEqualToString:@"video"]);
}

/// 该行是否相册"从行"：同组首个成员为主行（渲染整个宫格），其余成员行零高隐藏。
/// 同批消息相邻发送，向前找通常 1~2 步即命中。
- (BOOL)isAlbumFollowerAtRow:(NSInteger)row {
    IMMessageModel *m = self.messages[(NSUInteger)row];
    if (![self isAlbumMember:m]) { return NO; }
    for (NSInteger i = row - 1; i >= 0; i--) {
        IMMessageModel *p = self.messages[(NSUInteger)i];
        if (p.groupID.length > 0 && [p.groupID isEqualToString:m.groupID] && [self isAlbumMember:p]) { return YES; }
    }
    return NO;
}

/// 同组全部成员（按消息顺序）。
- (NSArray<IMMessageModel *> *)albumMembersForGroupID:(NSString *)gid {
    NSMutableArray<IMMessageModel *> *out = [NSMutableArray array];
    for (IMMessageModel *m in self.messages) {
        if (m.groupID.length > 0 && [m.groupID isEqualToString:gid] && [self isAlbumMember:m]) { [out addObject:m]; }
    }
    return out;
}

/// 消息所属的"可见行"：相册成员 → 该组 leader 行；普通消息 → 自身行。NSNotFound=不在列表。
- (NSUInteger)visibleRowForMessage:(IMMessageModel *)m {
    NSUInteger own = [self.messages indexOfObjectIdenticalTo:m];
    if (own == NSNotFound || ![self isAlbumMember:m]) { return own; }
    for (NSUInteger i = 0; i <= own; i++) {
        IMMessageModel *p = self.messages[i];
        if (p.groupID.length > 0 && [p.groupID isEqualToString:m.groupID] && [self isAlbumMember:p]) { return i; }
    }
    return own;
}

/// 从行零高（宫格已在 leader 行整体渲染）；其余行自适应。
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row < (NSInteger)self.messages.count && [self isAlbumFollowerAtRow:indexPath.row]) { return 0; }
    return UITableViewAutomaticDimension;
}

/// 按消息类型精确估高：估算与真实行高差得越远，上滑实体化行时系统的 offset 修正越猛
///（=「滚到某处突然卡一下/弹跳」的另一半根因；主因是媒体尺寸此前不落库，见 onMediaSizeResolved）。
- (CGFloat)tableView:(UITableView *)tableView estimatedHeightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= (NSInteger)self.messages.count) { return 56; }
    IMMessageModel *m = self.messages[(NSUInteger)indexPath.row];
    if ([self isAlbumFollowerAtRow:indexPath.row]) { return 0; }
    if ([self isAlbumMember:m]) { return 240; } // 宫格 leader：整格粗估
    if ([m.contentType isEqualToString:@"image"] || [m.contentType isEqualToString:@"video"]) {
        // 已知 media_w/h → 与 cell 同一套缩放规则精确估；未知 → 方形占位边长（cell 首帧同款）。
        return [IMImageCell displayHeightForPixelWidth:m.mediaW pixelHeight:m.mediaH] + 8;
    }
    if ([m.contentType isEqualToString:@"file"]) { return 84; }
    if ([m.contentType isEqualToString:@"chat_record"]) {
        // 群聊对方连续段首条多一行发送者昵称（~22pt），估高相应加高，减少上滑实体化时的 offset 修正。
        BOOL grpNameRec = self.isGroupChat && ![m.from isEqualToString:self.userID]
            && [self isFirstInSenderRun:indexPath.row];
        return grpNameRec ? 142 : 120;
    }
    return 56;
}

/// 按 conv_seq 找已加载的消息（引用缩略图解析用；不在窗口内返回 nil）。
- (IMMessageModel *)messageWithConvSeq:(int64_t)convSeq {
    for (IMMessageModel *x in self.messages) {
        if (x.convSeq == convSeq) { return x; }
    }
    return nil;
}

/// 按时间分组：每自然日首条消息上方显示日期分隔胶囊（今天/昨天/M月d日）。无效时间或同日返回 nil。
- (NSString *)dayHeaderForRow:(NSInteger)row {
    IMMessageModel *m = self.messages[row];
    if (m.timestamp <= 0) { return nil; } // 发送中（未拿到服务端时间）不显示日期
    if (row == 0) { return [IMTheme dayHeaderStringFromMillis:m.timestamp]; }
    IMMessageModel *prev = self.messages[row - 1];
    if ([IMTheme isMillis:m.timestamp sameDayAsMillis:prev.timestamp]) { return nil; }
    return [IMTheme dayHeaderStringFromMillis:m.timestamp];
}

#pragma mark - 长按消息菜单（数据驱动：IMMenuAction 单一来源）

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView
    contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    if (self.selecting) { return nil; } // 多选态无长按菜单
    if (indexPath.row >= (NSInteger)self.messages.count) { return nil; }
    IMMessageModel *message = self.messages[indexPath.row];
    if ([message.contentType isEqualToString:@"system"]) { return nil; } // 系统消息无操作菜单
    if (message.recalledAt > 0) { return nil; } // 撤回墓碑无操作菜单
    if ([self isAlbumMember:message]) { return nil; } // 相册宫格：菜单由每个格子自带（定位到单条成员）
    BOOL mine = [message.from isEqualToString:self.userID];
    NSArray<IMMenuAction *> *actions = [self messageActionsForMessage:message mine:mine];
    // 群聊里自己发的消息：菜单**顶部**挂一条「N 人已读 ›」（M4-8）。人数要查服务端，
    // 故用 UIDeferredMenuElement 异步填——菜单先弹出、这一行随后就位，不阻塞其它操作。
    UIMenuElement *readRow = [self readReceiptMenuElementForMessage:message mine:mine];
    // identifier 带上 indexPath：高亮/收起预览回调要凭它找到 cell（否则只能用系统默认的整行全宽快照）。
    return [UIContextMenuConfiguration configurationWithIdentifier:indexPath previewProvider:nil
        actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
            UIMenu *base = [IMMenuAction menuWithActions:actions];
            if (!readRow) { return base; }
            NSMutableArray<UIMenuElement *> *children = [NSMutableArray arrayWithObject:readRow];
            [children addObjectsFromArray:base.children];
            return [UIMenu menuWithTitle:@"" children:children];
        }];
}

/// 群聊「N 人已读」菜单行（M4-8）。返回 nil 表示不该显示这一行：
/// 单聊 / 他人消息（只有发送者能看谁读了自己，隐私）/ 尚未拿到 conv_seq 的发送中消息。
/// 群规模超上限时服务端回 enabled=NO，此处同样静默隐藏该行（不弹错）。
- (nullable UIMenuElement *)readReceiptMenuElementForMessage:(IMMessageModel *)message mine:(BOOL)mine {
    if (!self.isGroupChat || !mine || message.convSeq <= 0) { return nil; }
    __weak typeof(self) ws = self;
    NSString *convID = self.convID;
    int64_t convSeq = message.convSeq;
    return [UIDeferredMenuElement elementWithProvider:^(void (^completion)(NSArray<UIMenuElement *> *)) {
        NSString *token = IMHTTPService.sharedService.currentToken;
        if (token.length == 0) { completion(@[]); return; }
        [IMHTTPService.sharedService readReceiptsWithToken:token convID:convID convSeq:convSeq
            completion:^(NSArray<NSString *> *read, NSArray<NSString *> *unread, BOOL enabled, NSError *error) {
                // 出错/超限：整行不出现——菜单里挂一条报错项没有任何操作价值。
                if (error || !enabled) { completion(@[]); return; }
                NSString *title = read.count > 0
                    ? [NSString stringWithFormat:@"%lu 人已读", (unsigned long)read.count]
                    : @"暂无人已读";
                UIAction *action = [UIAction actionWithTitle:title
                                                       image:[UIImage systemImageNamed:@"eye"]
                                                  identifier:nil
                                                     handler:^(__kindof UIAction *a) {
                    [ws presentReadReceiptsWithRead:read unread:unread];
                }];
                // 0 人已读时保留该行但不可点（草图 §04-2：显"暂无人已读"、不可点）。
                if (read.count == 0) { action.attributes = UIMenuElementAttributesDisabled; }
                completion(@[action]);
            }];
    }];
}

/// 打开已读名单卡（半屏 + 分段 tab，点成员进其资料页）。
- (void)presentReadReceiptsWithRead:(NSArray<NSString *> *)read unread:(NSArray<NSString *> *)unread {
    __weak typeof(self) ws = self;
    IMReadReceiptViewController *vc = [[IMReadReceiptViewController alloc]
        initWithGroup:self.groupInfo readUIDs:read unreadUIDs:unread
          onTapMember:^(NSString *uid) { [ws openMemberProfileForUID:uid]; }];
    [self presentViewController:vc animated:YES completion:nil];
}

/// 逐角圆角矩形路径：按 CACornerMask 决定每个角是圆角(半径 r)还是直角(0)，手动画弧——
/// 用于长按预览 visiblePath 精确复刻气泡（含尾巴那个直角），绕开 byRoundingCorners 的角组合渲染怪癖。
static UIBezierPath *IMBubbleOutlinePath(CGRect rect, CGFloat radius, CACornerMask mask) {
    CGFloat r = MIN(radius, MIN(CGRectGetWidth(rect), CGRectGetHeight(rect)) / 2.0);
    if (r < 0) { r = 0; }
    CGFloat tl = (mask & kCALayerMinXMinYCorner) ? r : 0; // 左上
    CGFloat tr = (mask & kCALayerMaxXMinYCorner) ? r : 0; // 右上
    CGFloat bl = (mask & kCALayerMinXMaxYCorner) ? r : 0; // 左下
    CGFloat br = (mask & kCALayerMaxXMaxYCorner) ? r : 0; // 右下
    CGFloat minX = CGRectGetMinX(rect), minY = CGRectGetMinY(rect);
    CGFloat maxX = CGRectGetMaxX(rect), maxY = CGRectGetMaxY(rect);
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(minX + tl, minY)];
    [p addLineToPoint:CGPointMake(maxX - tr, minY)];
    if (tr > 0) { [p addArcWithCenter:CGPointMake(maxX - tr, minY + tr) radius:tr startAngle:-M_PI_2 endAngle:0 clockwise:YES]; }
    else { [p addLineToPoint:CGPointMake(maxX, minY)]; }
    [p addLineToPoint:CGPointMake(maxX, maxY - br)];
    if (br > 0) { [p addArcWithCenter:CGPointMake(maxX - br, maxY - br) radius:br startAngle:0 endAngle:M_PI_2 clockwise:YES]; }
    else { [p addLineToPoint:CGPointMake(maxX, maxY)]; }
    [p addLineToPoint:CGPointMake(minX + bl, maxY)];
    if (bl > 0) { [p addArcWithCenter:CGPointMake(minX + bl, maxY - bl) radius:bl startAngle:M_PI_2 endAngle:M_PI clockwise:YES]; }
    else { [p addLineToPoint:CGPointMake(minX, maxY)]; }
    [p addLineToPoint:CGPointMake(minX, minY + tl)];
    if (tl > 0) { [p addArcWithCenter:CGPointMake(minX + tl, minY + tl) radius:tl startAngle:M_PI endAngle:3 * M_PI_2 clockwise:YES]; }
    else { [p addLineToPoint:CGPointMake(minX, minY)]; }
    [p closePath];
    return p;
}

/// 长按菜单只圈气泡本体：系统默认对整个 cell（contentView 全宽，含气泡两侧透明区）截图并垫系统底色
/// 托盘——表现为"整行宽的背景色"，收起动画时这块全宽快照归位又比气泡慢半拍。改为 UITargetedPreview
/// 指向 cell 的 previewTargetView（气泡/缩略图/卡片），背景透明 + 圆角 visiblePath，高亮与收起都干净。
- (UITargetedPreview *)targetedPreviewForConfiguration:(UIContextMenuConfiguration *)configuration {
    id identifier = configuration.identifier; // id<NSCopying> 不能直接发 isKindOfClass:，先落成 id
    NSIndexPath *ip = [identifier isKindOfClass:NSIndexPath.class] ? (NSIndexPath *)identifier : nil;
    if (!ip) { return nil; }
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:ip];
    if (![cell respondsToSelector:@selector(previewTargetView)]) { return nil; } // 系统默认兜底
    UIView *target = [(id)cell previewTargetView];
    if (!target || !target.window) { return nil; }
    UIPreviewParameters *params = [UIPreviewParameters new];
    params.backgroundColor = UIColor.clearColor; // 去掉全宽底色托盘
    // 高亮路径须**逐角复刻气泡自身的 maskedCorners**：文本气泡有尾巴（某个下角是直角）。
    // 此处**手动构造路径**而非用 `bezierPathWithRoundedRect:byRoundingCorners:`——后者在部分 iOS 版本对
    // 「保留右下、只缺左下」这类角组合会画错（实测：自己气泡尾角正常、对方气泡却被抹成四圆角）。手动逐角
    // 给半径就没有这个歧义；未设 maskedCorners 的（媒体/卡片=全角）四角同半径，退化为普通圆角矩形。
    params.visiblePath = IMBubbleOutlinePath(target.bounds, target.layer.cornerRadius, target.layer.maskedCorners);
    return [[UITargetedPreview alloc] initWithView:target parameters:params];
}

- (UITargetedPreview *)tableView:(UITableView *)tableView
    previewForHighlightingContextMenuWithConfiguration:(UIContextMenuConfiguration *)configuration {
    return [self targetedPreviewForConfiguration:configuration];
}

- (UITargetedPreview *)tableView:(UITableView *)tableView
    previewForDismissingContextMenuWithConfiguration:(UIContextMenuConfiguration *)configuration {
    return [self targetedPreviewForConfiguration:configuration];
}

/// 单条消息的菜单动作（按显示顺序，仅含可见项）：
/// 复制 / 引用 / 转发 / 收藏 / 撤回(仅自己且有真实 conv_seq) / 多选 / 翻译 / 删除(破坏性)；
/// 对方消息额外含 举报消息 / 举报发送者。已接：复制、删除、举报*；其余 → 开发中吐司。
- (NSArray<IMMenuAction *> *)messageActionsForMessage:(IMMessageModel *)message mine:(BOOL)mine {
    __weak typeof(self) ws = self;
    NSMutableArray<IMMenuAction *> *actions = [NSMutableArray array];

    // 复制：仅文本（随时可复制）与已发出的图片（复制图片字节）。文件/聊天记录卡片无复制语义
    //（后者会把整段 JSON 拷进剪贴板）；发送中的图片 content 还是本地引用，复制无意义。与 Web 对齐。
    BOOL copyable = ([message.contentType isEqualToString:@"text"] && message.content.length > 0 && message.recalledAt == 0)
                 || ([message.contentType isEqualToString:@"image"] && message.convSeq > 0 && message.recalledAt == 0);
    if (copyable) {
        [actions addObject:[IMMenuAction actionWithId:@"copy" title:@"复制" image:@"doc.on.doc" handler:^{
            [ws copyMessageToPasteboard:message];
        }]];
    }
    if (message.recalledAt == 0 && message.convSeq > 0) {
        [actions addObject:[IMMenuAction actionWithId:@"reply" title:@"引用" image:@"arrowshape.turn.up.left" handler:^{
            [ws beginReplyTo:message];
        }]];
    }
    if (message.recalledAt == 0 && message.convSeq > 0) {
        [actions addObject:[IMMenuAction actionWithId:@"forward" title:@"转发" image:@"arrowshape.turn.up.right" handler:^{
            [ws forwardMessage:message];
        }]];
    }
    // 收藏：文本/图片/视频/文件/链接均可（快照存 content+content_type，后端通用；system/撤回除外）。
    // 必须 convSeq>0：发送中的行 content 是 im-pending:// 本地引用，收藏它是一条别端永远打不开的死链（与 Web 对齐）。
    if (message.convSeq > 0 && message.content.length > 0 && message.recalledAt == 0 && ![message.contentType isEqualToString:@"system"]) {
        [actions addObject:[IMMenuAction actionWithId:@"favorite" title:@"收藏" image:@"bookmark" handler:^{
            [ws favoriteMessage:message];
        }]];
    }
    // 撤回（M4-1）：仅本人、已拿到 conv_seq、未撤回、2min 窗口内（服务端为准，此处仅避免必然失败的入口）。
    int64_t nowMs = (int64_t)([NSDate date].timeIntervalSince1970 * 1000);
    if (mine && message.convSeq > 0 && message.recalledAt == 0 && (nowMs - message.timestamp) <= kIMRecallWindowMs) {
        [actions addObject:[IMMenuAction actionWithId:@"recall" title:@"撤回" image:@"arrow.uturn.backward" handler:^{
            [IMSocketManager.sharedManager recallMessageInConv:(message.convID ?: @"") targetConvSeq:message.convSeq];
        }]];
    }
    // 置顶 ↔ 取消置顶（G0）：**切换对**，按当前状态只显示其一（与 Web menus.ts 同序同语义）。
    // 撤回态/未发出/系统消息不可置顶（横幅不能指向墓碑或本地行）；但已撤回的置顶仍要能摘下来。
    if ([self canPinMessages] && message.convSeq > 0) {
        if (message.pinnedAt > 0) {
            [actions addObject:[IMMenuAction actionWithId:@"unpin" title:@"取消置顶" image:@"pin.slash" handler:^{
                [IMSocketManager.sharedManager pinMessageInConv:(message.convID ?: @"")
                                                  targetConvSeq:message.convSeq pinned:NO];
            }]];
        } else if (message.recalledAt == 0 && ![message.contentType isEqualToString:@"system"]) {
            [actions addObject:[IMMenuAction actionWithId:@"pin" title:@"置顶" image:@"pin" handler:^{
                [IMSocketManager.sharedManager pinMessageInConv:(message.convID ?: @"")
                                                  targetConvSeq:message.convSeq pinned:YES];
            }]];
        }
    }
    // 编辑（M4-5）：仅本人文本、已拿到 conv_seq、未撤回。必须 convSeq>0——发送中的行发 msg_op edit
    // 会因 sendTapped 的 convSeq>0 判定落空而改走「发新消息」分支，造成重复发送且编辑条卡住。
    if (mine && [message.contentType isEqualToString:@"text"] && message.content.length > 0 && message.convSeq > 0 && message.recalledAt == 0) {
        [actions addObject:[IMMenuAction actionWithId:@"edit" title:@"编辑" image:@"pencil" handler:^{
            [ws beginEditMessage:message];
        }]];
    }
    // 取消发送：仅本人、仍在发送/失败的本地待发件（发出去拿到 conv_seq 后走撤回，不走这里）。
    // content 为空 = 还在排队/压缩（尚未落盘），同样允许取消。
    if (mine && message.convSeq <= 0
        && ([IMPendingMediaStore isLocalRef:message.content] || message.content.length == 0)
        && (message.status == IMMessageStatusSending || message.status == IMMessageStatusFailed)) {
        [actions addObject:[IMMenuAction actionWithId:@"cancelSend" title:@"取消发送" image:@"xmark.circle" handler:^{
            [ws cancelPendingMessage:message];
        }]];
    }
    // 多选：仅已发出的消息（发送中/失败的本地件不可勾选，入口一并收掉；与 Web visible convSeq>0 对齐）。
    if (message.convSeq > 0) {
        [actions addObject:[IMMenuAction actionWithId:@"multiSelect" title:@"多选" image:@"checkmark.circle" handler:^{
            [ws enterSelectionWithMessage:message];
        }]];
    }
    if ([message.contentType isEqualToString:@"text"] && message.content.length > 0 && message.recalledAt == 0) {
        [actions addObject:[IMMenuAction actionWithId:@"translate" title:@"翻译" image:@"character.bubble" handler:^{
            [ws translateMessage:message];
        }]];
    }
    // 举报（AG-3）：仅对方消息可举报。举报消息用 conv_seq 定位（与 Web 一致）。
    if (!mine) {
        [actions addObject:[IMMenuAction actionWithId:@"reportMessage" title:@"举报消息" image:@"exclamationmark.bubble" handler:^{
            [ws reportTargetType:@"message" targetID:[@(message.convSeq) stringValue] title:@"举报这条消息"];
        }]];
        [actions addObject:[IMMenuAction actionWithId:@"reportUser" title:@"举报发送者" image:@"person.crop.circle.badge.exclamationmark" handler:^{
            [ws reportTargetType:@"user" targetID:(message.from ?: @"") title:[NSString stringWithFormat:@"举报用户 %@", message.from]];
        }]];
    }
    // 删除：发送中的本地件不显示——删除只删行不停止上传，传完仍会发出去（僵尸任务）；
    // 想撤走请用「取消发送」（停任务/删副本/删库行一步到位）。失败行保留删除。
    if (!(message.status == IMMessageStatusSending && message.convSeq <= 0)) {
        [actions addObject:[self deleteMenuActionForMessage:message]];
    }
    return actions;
}

/// 我能否为该消息「为所有人删除」：我发的，或群主/管理员。
/// 权限规则的**唯一出处**（长按菜单与查看器删除共用；详情页 canDeleteForEveryone: 同规则）——改语义只改这里。
- (BOOL)canDeleteForEveryone:(IMMessageModel *)message {
    if (message.from.length > 0 && [message.from isEqualToString:self.userID]) { return YES; }
    return self.isGroupChat && (self.groupInfo.myRole == IMGroupRoleOwner || self.groupInfo.myRole == IMGroupRoleAdmin);
}

/// 删除菜单项（任务2，两档，与详情页一致）：
///  - 本地未发出/失败件（convSeq<=0）：直接「删除」=本地删（服务器无此消息）。
///  - 已发出、我发的 / 群主·管理员：「删除」→ 子菜单【为所有人删除】(msg_op delete) +【仅删除自己】(hide 多设备)。
///  - 已发出、仅能删自己：「删除」=仅删除自己（hide）。
- (IMMenuAction *)deleteMenuActionForMessage:(IMMessageModel *)message {
    __weak typeof(self) ws = self;
    if (message.convSeq <= 0) {
        return [IMMenuAction destructiveActionWithId:@"delete" title:@"删除" image:@"trash" handler:^{ [ws deleteMessage:message]; }];
    }
    if (![self canDeleteForEveryone:message]) {
        return [IMMenuAction destructiveActionWithId:@"delete" title:@"删除" image:@"trash" handler:^{ [ws hideMessageForSelf:message]; }];
    }
    IMMenuAction *selfOnly = [IMMenuAction destructiveActionWithId:@"deleteSelf" title:@"仅删除自己" image:@"trash"
                                                          handler:^{ [ws hideMessageForSelf:message]; }];
    IMMenuAction *everyone = [IMMenuAction destructiveActionWithId:@"deleteEveryone" title:@"为所有人删除" image:@"trash"
                                                          handler:^{ [ws deleteMessageForEveryone:message]; }];
    // 破坏性重的「为所有人删除」放最后（destructive-last，与本仓菜单约定一致，降低误触不可逆项）。
    return [IMMenuAction submenuWithId:@"delete" title:@"删除" image:@"trash" children:@[selfOnly, everyone]];
}

/// 本地删除一条消息（仅本端：从库 + 内存移除并刷新；不影响对端）。convSeq<=0 的本地失败件走此。
- (void)deleteMessage:(IMMessageModel *)message {
    [self performDatabaseOperation:^(IMDatabase *database) {
        [database deleteMessage:message];
    }];
    [self.messages removeObject:message];
    if (message.convSeq > 0) { [self.seenConvSeqs removeObject:@(message.convSeq)]; }
    [self.tableView reloadData];
}

/// 为所有人删除（任务2）：WS msg_op op=delete；服务端广播回经 IMSocketDidRemoveMessageNotification 移除本地。被拒走 reject 通知。
- (void)deleteMessageForEveryone:(IMMessageModel *)message {
    if (message.convSeq <= 0) { return; }
    [[IMSocketManager sharedManager] deleteMessageForEveryoneInConv:(message.convID ?: self.convID) targetConvSeq:message.convSeq];
}

/// 仅删除自己（任务2）：编排（REST hide + 本端移除）收敛在 IMSocketManager，VC 只负责失败 toast。
- (void)hideMessageForSelf:(IMMessageModel *)message {
    if (message.convSeq <= 0) { return; }
    __weak typeof(self) ws = self;
    [[IMSocketManager sharedManager] hideMessageInConv:(message.convID ?: self.convID) targetConvSeq:message.convSeq
                                            completion:^(NSError *error) {
        if (error) { [ws im_showToast:error.localizedDescription ?: @"删除失败"]; }
    }];
}

#pragma mark - 多选态（#2：转发/收藏/删除）

/// 进入多选：表格进入编辑多选态，隐藏输入栏、显示底部工具栏，并默认选中触发的那条。
/// 列表**锚定长按的那条消息不动**：宫格展开为独立行会让行结构/总高度剧变，不锚定就会跳到别处。
- (void)enterSelectionWithMessage:(IMMessageModel *)message {
    if (self.selecting) { return; }
    self.selecting = YES;
    [self showAttachPanel:NO];
    [self cancelReply];
    [self.inputField resignFirstResponder];

    NSUInteger row = [self.messages indexOfObject:message];
    [self preserveScreenPositionOfRow:row during:^{
        self.tableView.allowsMultipleSelectionDuringEditing = YES;
        [self.tableView setEditing:YES animated:NO];
        [self.tableView reloadData]; // 相册宫格展开为独立行（逐条可勾选）；isAlbumMember 在多选态恒 NO
        // 已在屏上的 cell 不会再走 willDisplay，就地改 selectionStyle 让勾选态可见（#5）。
        for (UITableViewCell *c in self.tableView.visibleCells) { [self applySelectionStyleForCell:c]; }
    }];

    [self buildSelectionBarIfNeeded];
    self.selectionBar.hidden = NO;
    self.inputBar.hidden = YES;

    self.savedTitle = self.title;
    self.savedRightItem = self.navigationItem.rightBarButtonItem;
    self.navigationItem.rightBarButtonItem = nil;
    // 必须用**带标题**的 item：统一 Liquid 标题栏按 leftTitle 渲染左位文字并把点击路由到本 item；
    // 系统 Cancel item 无标题 → 被回落成返回箭头、点击直接 pop 出聊天页（"没有取消按钮"的根因）。
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"取消" style:UIBarButtonItemStylePlain
                                        target:self action:@selector(exitSelection)];

    if (row != NSNotFound) {
        [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)row inSection:0]
                                    animated:NO scrollPosition:UITableViewScrollPositionNone];
    }
    [self updateSelectionUI];
}

- (void)exitSelection {
    if (!self.selecting) { return; }
    self.selecting = NO;
    // 退出同样锚定：以当前视口第一条可见消息为锚（宫格收拢后上方内容变矮，不锚定视口会漂移）。
    NSIndexPath *anchor = self.tableView.indexPathsForVisibleRows.firstObject;
    [self preserveScreenPositionOfRow:(anchor ? (NSUInteger)anchor.row : NSNotFound) during:^{
        [self.tableView setEditing:NO animated:NO];
        [self.tableView reloadData]; // 相册宫格恢复聚簇渲染
        for (UITableViewCell *c in self.tableView.visibleCells) { [self applySelectionStyleForCell:c]; }
    }];
    self.selectionBar.hidden = YES;
    self.inputBar.hidden = NO;
    self.title = self.savedTitle;
    self.navigationItem.leftBarButtonItem = nil; // 恢复默认返回
    self.navigationItem.rightBarButtonItem = self.savedRightItem;
    [self refreshUnifiedNavigationBar]; // 标题/左右钮改动要立刻刷进 Liquid 标题栏
}

/// 在表格 mutation（编辑态切换 + reloadData）前后保持某行的屏幕位置不变（多选进出时列表不跳）。
/// reload 后行高全部回到估算值，先落一次布局再对齐、两轮收敛（与 anchorRowToTop: 同思路）。
- (void)preserveScreenPositionOfRow:(NSUInteger)row during:(void (NS_NOESCAPE ^)(void))mutation {
    if (row == NSNotFound || row >= self.messages.count) { mutation(); return; }
    NSIndexPath *ip = [NSIndexPath indexPathForRow:(NSInteger)row inSection:0];
    CGFloat screenY = [self.tableView rectForRowAtIndexPath:ip].origin.y - self.tableView.contentOffset.y;
    mutation();
    for (int pass = 0; pass < 2; pass++) {
        [self.tableView layoutIfNeeded];
        CGFloat topInset = self.tableView.adjustedContentInset.top;
        CGFloat maxY = self.tableView.contentSize.height - self.tableView.bounds.size.height
                     + self.tableView.adjustedContentInset.bottom;
        CGFloat y = [self.tableView rectForRowAtIndexPath:ip].origin.y - screenY;
        y = MAX(-topInset, MIN(y, MAX(-topInset, maxY)));
        [self.tableView setContentOffset:CGPointMake(0, y) animated:NO];
    }
}

- (void)buildSelectionBarIfNeeded {
    if (self.selectionBar) { return; }
    UIView *bar = [UIView new];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.backgroundColor = UIColor.secondarySystemBackgroundColor;
    [self.view addSubview:bar];
    self.selectionBar = bar;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self selectionBarButton:@"转发" image:@"arrowshape.turn.up.right" action:@selector(forwardSelected)],
        [self selectionBarButton:@"收藏" image:@"bookmark" action:@selector(favoriteSelected)],
        [self selectionBarButton:@"删除" image:@"trash" action:@selector(deleteSelected)],
    ]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [bar.topAnchor constraintEqualToAnchor:self.inputBar.topAnchor],
        [row.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [row.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [row.topAnchor constraintEqualToAnchor:bar.topAnchor],
        [row.heightAnchor constraintEqualToConstant:56],
    ]];
}

- (UIButton *)selectionBarButton:(NSString *)title image:(NSString *)image action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *cfg = [UIButtonConfiguration plainButtonConfiguration];
    cfg.image = [UIImage systemImageNamed:image];
    cfg.title = title;
    cfg.imagePlacement = NSDirectionalRectEdgeTop;
    cfg.imagePadding = 3;
    cfg.baseForegroundColor = IMTheme.textPrimary;
    b.configuration = cfg;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

/// 已选消息（按行序）。
- (NSArray<IMMessageModel *> *)selectedMessages {
    NSArray<NSIndexPath *> *ips = [self.tableView.indexPathsForSelectedRows sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray<IMMessageModel *> *out = [NSMutableArray array];
    for (NSIndexPath *ip in ips) {
        if (ip.row < (NSInteger)self.messages.count) { [out addObject:self.messages[(NSUInteger)ip.row]]; }
    }
    return out;
}

- (void)updateSelectionUI {
    NSUInteger n = self.tableView.indexPathsForSelectedRows.count;
    self.title = n > 0 ? [NSString stringWithFormat:@"已选择 %lu 条", (unsigned long)n] : @"选择消息";
    [self refreshUnifiedNavigationBar]; // 标题与「取消」左钮由统一 Liquid 栏渲染，改完必须刷一次
}

#pragma mark 多选工具栏动作

- (void)forwardSelected {
    NSArray<IMMessageModel *> *msgs = [self selectedMessages];
    if (msgs.count == 0) { [self im_showToast:@"请先选择消息"]; return; }
    __weak typeof(self) ws = self;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"逐条转发" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [ws pickConversationsThen:^(NSArray<IMConversation *> *convs) { [ws forwardMessages:msgs perMessageToConversations:convs]; }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"合并转发" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        __strong typeof(ws) self = ws; if (!self) { return; }
        NSUInteger expiredCount = 0;
        for (IMMessageModel *m in msgs) { if ([self isMediaExpiredForForward:m]) { expiredCount++; } }
        if (expiredCount >= msgs.count) { [self im_showToast:@"所选均已失效，无法合并转发"]; return; } // 失效项会被剔出记录，全失效则整条无意义
        NSString *json = [self mergedForwardJSONForMessages:msgs];
        [self pickConversationsThen:^(NSArray<IMConversation *> *convs) { [self forwardMergedRecord:json toConversations:convs]; }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    // iPad/regular 宽度下走 popover：sourceRect 必须在 sourceView 自身坐标系内，否则锚点跑到屏幕外（原用 self.view 坐标）。
    UIView *anchor = self.selectionBar ?: self.view;
    sheet.popoverPresentationController.sourceView = anchor;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(anchor.bounds), CGRectGetMinY(anchor.bounds), 1, 1);
    sheet.popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirectionDown;
    [self presentViewController:sheet animated:YES completion:nil];
}

/// 弹出整页会话选择器，回调选中的会话。
/// 转发的发送方本地回显（用户反馈 #2）：服务端不回显自己发的消息，转发若不落库/上屏，
/// 发送方在目标会话里看不到这条转发。与普通发送一致：乐观消息落库（目标是当前会话则上屏），
/// ACK 后按 clientMsgID upsert 状态/conv_seq（页面已退出也能改到库，重进会话读到正确状态）。
- (void)forwardEchoContent:(NSString *)content contentType:(NSString *)ct forwardFrom:(NSString *)origin fileName:(NSString *)fileName fileSize:(int64_t)fileSize
                    toConv:(NSString *)convID toUser:(NSString *)toUser {
    [self forwardEchoContent:content contentType:ct forwardFrom:origin fileName:fileName fileSize:fileSize
                  attributes:nil toConv:convID toUser:toUser];
}

/// 从源消息取出转发要一并带走的媒体元数据（封面/尺寸/时长）；非媒体消息返回 nil。
- (IMMediaAttributes *)forwardAttributesForMessage:(IMMessageModel *)message {
    BOOL isMedia = [message.contentType isEqualToString:@"image"] || [message.contentType isEqualToString:@"video"];
    if (!isMedia) { return nil; }
    IMMediaAttributes *attrs = [IMMediaAttributes new];
    attrs.poster = message.poster;          // 视频封面（不带的话 Web 收端解不了 HEVC 就只剩空白）
    attrs.thumb = message.thumb;            // 极小模糊预览：不带的话收端未下载态只有空磨砂、没内容轮廓
    attrs.pixelWidth = message.mediaW;
    attrs.pixelHeight = message.mediaH;
    attrs.durationMillis = message.duration;
    attrs.fileSize = message.fileSize;
    return attrs;
}

/// attributes：原消息的封面/尺寸/时长。转发不带就等于把这些信息丢了（收端只能按未知渲染，事后补不回）。
- (void)forwardEchoContent:(NSString *)content contentType:(NSString *)ct forwardFrom:(NSString *)origin fileName:(NSString *)fileName fileSize:(int64_t)fileSize
                attributes:(IMMediaAttributes *)attributes toConv:(NSString *)convID toUser:(NSString *)toUser {
    IMMessageModel *m = [IMMessageModel new];
    int64_t sentAt = (int64_t)(NSDate.date.timeIntervalSince1970 * 1000);
    __weak typeof(self) ws = self;
    NSString *clientMsgID = [IMSocketManager.sharedManager forwardContent:content contentType:ct
                                                                   toConv:convID toUser:toUser forwardFrom:origin
                                                                 fileName:fileName
                                                                 fileSize:fileSize
                                                               attributes:attributes
                                                               completion:^(BOOL success, NSError *error, int64_t convSeq) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        m.status = success ? IMMessageStatusSent : IMMessageStatusFailed;
        m.convSeq = convSeq;
        if (![self performDatabaseOperation:^(IMDatabase *database) {
            [database saveMessage:m];
        }]) { return; }
        if (success && [ct isEqualToString:@"file"] && fileName.length > 0) {
            [self performDatabaseOperation:^(IMDatabase *database) {
                [database cacheSentFiles:@[@{
                    @"server_msg_id": m.clientMsgID ?: @"", @"url": content,
                    @"name": fileName, @"size": @(fileSize), @"timestamp": @(sentAt),
                }]];
            }];
        }
        if ([convID isEqualToString:self.convID]) {
            if (convSeq > 0) { [self.seenConvSeqs addObject:@(convSeq)]; } // 防 sync 重复回显
            [self.tableView reloadData];
        }
    }];
    m.clientMsgID = clientMsgID;
    m.convID = convID; m.to = toUser; m.from = self.userID;
    m.content = content; m.contentType = ct;
    m.fileName = fileName;
    m.fileSize = fileSize;
    m.poster = attributes.poster.length > 0 ? attributes.poster : nil;
    m.thumb = attributes.thumb.length > 0 ? attributes.thumb : nil;
    m.mediaW = attributes.pixelWidth;
    m.mediaH = attributes.pixelHeight;
    m.duration = attributes.durationMillis;
    m.forwardFrom = origin.length > 0 ? origin : nil;
    m.status = IMMessageStatusSending;
    m.timestamp = sentAt;
    [self performDatabaseOperation:^(IMDatabase *database) {
        [database saveMessage:m];
    }];
    if ([convID isEqualToString:self.convID]) {
        [self.messages addObject:m];
        [self appendReloadAndScroll];
    }
}

- (void)pickConversationsThen:(void (^)(NSArray<IMConversation *> *convs))block {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    IMForwardPickerViewController *picker = [[IMForwardPickerViewController alloc]
        initWithHost:self.host token:token onDone:^(NSArray<IMConversation *> *selected) {
        if (selected.count > 0) { block(selected); }
    }];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)forwardMessages:(NSArray<IMMessageModel *> *)msgs perMessageToConversations:(NSArray<IMConversation *> *)convs {
    // 失效媒体跳过（转出去对端必 404）：先数一次，避免在会话外层循环里重复计数。
    NSUInteger expiredCount = 0;
    for (IMMessageModel *m in msgs) { if ([self isMediaExpiredForForward:m]) { expiredCount++; } }
    for (IMConversation *c in convs) {
        NSString *toUser = c.isGroup ? @"" : (c.peer ?: @"");
        for (IMMessageModel *m in msgs) {
            if (m.recalledAt > 0 || m.content.length == 0 || [m.contentType isEqualToString:@"system"]) { continue; }
            if (m.convSeq <= 0) { continue; } // 防御：发送中/失败的本地件（多选已拦，此处兜底）
            if ([self isMediaExpiredForForward:m]) { continue; } // 失效媒体跳过
            NSString *origin = m.forwardFrom.length > 0 ? m.forwardFrom
                : (m.fromNickname.length > 0 ? m.fromNickname : (m.from ?: @""));
            [self forwardEchoContent:m.content contentType:(m.contentType ?: @"text") forwardFrom:origin fileName:m.fileName fileSize:m.fileSize
                          attributes:[self forwardAttributesForMessage:m] toConv:c.convID toUser:toUser];
        }
    }
    [self exitSelection];
    if (expiredCount >= msgs.count) { // 所选可选消息均为失效媒体（系统/撤回件多选态本就不可选）
        [self im_showToast:@"所选均已失效，未转发"];
        return;
    }
    NSString *base = convs.count == 1 ? @"已转发" : [NSString stringWithFormat:@"已转发到 %lu 个会话", (unsigned long)convs.count];
    [self im_showToast:expiredCount > 0
        ? [NSString stringWithFormat:@"%@（%lu 条已失效未转发）", base, (unsigned long)expiredCount]
        : base];
}

- (void)forwardMergedRecord:(NSString *)json toConversations:(NSArray<IMConversation *> *)convs {
    if (json.length == 0) { return; }
    for (IMConversation *c in convs) {
        NSString *toUser = c.isGroup ? @"" : (c.peer ?: @"");
        [self forwardEchoContent:json contentType:@"chat_record" forwardFrom:@"" fileName:nil fileSize:0
                          toConv:c.convID toUser:toUser];
    }
    [self exitSelection];
    [self im_showToast:@"已合并转发"];
}

- (void)favoriteSelected {
    NSArray<IMMessageModel *> *msgs = [self selectedMessages];
    if (msgs.count == 0) { [self im_showToast:@"请先选择消息"]; return; }
    for (IMMessageModel *m in msgs) {
        if (m.recalledAt > 0 || m.content.length == 0 || [m.contentType isEqualToString:@"system"]) { continue; }
        [self favoriteMessage:m];
    }
    [self exitSelection];
}

- (void)deleteSelected {
    NSArray<IMMessageModel *> *msgs = [self selectedMessages];
    if (msgs.count == 0) { [self im_showToast:@"请先选择消息"]; return; }
    __weak typeof(self) ws = self;
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:nil
        message:[NSString stringWithFormat:@"删除所选 %lu 条消息？", (unsigned long)msgs.count]
        preferredStyle:UIAlertControllerStyleActionSheet];
    [ac addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        __strong typeof(ws) self = ws;
        for (IMMessageModel *m in msgs) {
            [self performDatabaseOperation:^(IMDatabase *database) {
                [database deleteMessage:m];
            }];
            [self.messages removeObject:m];
            if (m.convSeq > 0) { [self.seenConvSeqs removeObject:@(m.convSeq)]; }
        }
        [self.tableView reloadData];
        [self exitSelection];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    ac.popoverPresentationController.sourceView = self.selectionBar ?: self.view;
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark 合并转发数据

/// 发送方显示名：自己→uid，群聊→成员昵称，单聊→标题（对端显示名）。
- (NSString *)displayNameForMessage:(IMMessageModel *)m {
    if ([m.from isEqualToString:self.userID]) { return self.userID ?: @"我"; }
    if (self.isGroupChat) { return [self senderNameForMessage:m]; }
    return (self.savedTitle.length ? self.savedTitle : (self.title.length ? self.title : (self.peerID ?: @"")));
}

/// 合并转发内容：JSON（t=标题，items=[{n:发送者, ct:类型, c:内容/URL, 文件另带 fn:文件名/fs:字节数}]），
/// content_type=chat_record。fn/fs 与 Web 同约定；老记录无 fn 时读端从 URL 反推原名兜底。
- (NSString *)mergedForwardJSONForMessages:(NSArray<IMMessageModel *> *)msgs {
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    for (IMMessageModel *m in msgs) {
        if (m.recalledAt > 0 || [m.contentType isEqualToString:@"system"] || m.content.length == 0) { continue; }
        if (m.convSeq <= 0) { continue; } // 防御：发送中/失败的本地件（多选已拦，此处兜底）
        if ([self isMediaExpiredForForward:m]) { continue; } // 失效媒体剔出合并记录（收端点开必 404）
        NSMutableDictionary *item = [@{ @"n": [self displayNameForMessage:m] ?: @"",
                                        @"ct": m.contentType ?: @"text",
                                        @"c": m.content ?: @"" } mutableCopy];
        if ([m.contentType isEqualToString:@"file"]) {
            NSString *fname = m.fileName.length > 0 ? m.fileName : IMMediaFileName(m.content);
            if (fname.length > 0) { item[@"fn"] = fname; }
            if (m.fileSize > 0) { item[@"fs"] = @(m.fileSize); }
        }
        [items addObject:item];
    }
    // 多选态下 self.title 已被替换为"已选择 N 条"，用 savedTitle 取真实会话名。
    NSString *base = self.savedTitle.length ? self.savedTitle : (self.title.length ? self.title : (self.peerID ?: @"聊天"));
    NSDictionary *dict = @{ @"t": [NSString stringWithFormat:@"%@ 的聊天记录", base], @"items": items };
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:NULL];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
}

#pragma mark - 编辑/选择 delegate

/// 多选态下该消息是否可勾选：系统提示/撤回墓碑/发送中·失败的本地件（无服务端内容，转出去是空的）不可选。
- (BOOL)isSelectableMessage:(IMMessageModel *)m {
    return ![m.contentType isEqualToString:@"system"] && m.recalledAt == 0 && m.convSeq > 0;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!self.selecting) { return NO; } // 仅多选态可选中
    // 不可选的行不显示勾选圈（系统编辑态对 canEdit=NO 的行自动不画圈，无需额外 UI）。
    if (indexPath.row >= (NSInteger)self.messages.count) { return NO; }
    return [self isSelectableMessage:self.messages[indexPath.row]];
}

/// 多选态勾选填充（#5）：selectionStyle=None 会让编辑圈选永远不显示"已勾选"态，
/// 进入多选须临时改回 Default（配 clear 的 multipleSelectionBackgroundView 保持气泡外观）。
- (void)applySelectionStyleForCell:(UITableViewCell *)cell {
    cell.selectionStyle = self.selecting ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    if (self.selecting && !cell.multipleSelectionBackgroundView) {
        UIView *bg = [UIView new];
        bg.backgroundColor = UIColor.clearColor;
        cell.multipleSelectionBackgroundView = bg;
    }
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    [self applySelectionStyleForCell:cell];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.selecting) { [self updateSelectionUI]; return; }
    // 上传中/失败的文件气泡不再响应整条点击：暂停/继续/重试/取消收敛到左侧图标位的圆环状态机
    //（cell.onFileControlTap → handlePendingMediaTap:），气泡其余区域仅在发送完成后点击打开文件。
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.selecting) { [self updateSelectionUI]; }
}

/// 举报（AG-3）：弹出输入框填理由 → 调 POST /api/v1/reports。message 举报带会话上下文。
- (void)reportTargetType:(NSString *)targetType targetID:(NSString *)targetID title:(NSString *)title {
    if (targetID.length == 0) { return; }
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
        message:@"请填写举报理由（可空）" preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"理由"; }];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"提交举报" style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *a) {
            NSString *reason = ac.textFields.firstObject.text ?: @"";
            NSString *convID = [targetType isEqualToString:@"message"] ? weakSelf.convID : nil;
            NSString *token = IMHTTPService.sharedService.currentToken;
            if (token.length == 0) { [weakSelf showReportResult:@"举报失败：未登录"]; return; }
            [IMHTTPService.sharedService reportWithToken:token targetType:targetType targetID:targetID
                convID:convID reason:reason completion:^(NSError *error) {
                    [weakSelf showReportResult:error ? [NSString stringWithFormat:@"举报失败：%@", error.localizedDescription]
                                                      : @"举报已提交，感谢反馈。"];
                }];
        }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)showReportResult:(NSString *)msg {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

/// 首条未读所在行：conv_seq > entryReadSeq 的第一条「对端」消息；无未读返回 -1。
/// **必须与服务端未读口径一致**（M4-8）：服务端 unreadCount 排除 msg_op 事件行与 system 系统消息，
/// 这里若只按 `from != 我` 找，会把分割线/进会话锚点定位到不计未读的系统行——
/// 表现为「以下为 N 条新消息」下方实际多出几行（群改名/入群留痕都会触发）。
- (NSInteger)firstUnreadRow {
    if (self.entryUnread <= 0) { return -1; }
    for (NSInteger i = 0; i < (NSInteger)self.messages.count; i++) {
        IMMessageModel *m = self.messages[i];
        if (m.convSeq <= self.entryReadSeq) { continue; }
        if ([m.from isEqualToString:self.userID]) { continue; }
        if (IMContentTypeCountsAsUnread(m.contentType)) { return i; }
    }
    return -1;
}

/// 进会话定位（只做一次）：有未读则停在首条未读，否则到底（CHAT_UX §3）。
- (void)positionInitialIfNeeded {
    if (self.didInitialPosition || self.messages.count == 0) { return; }
    self.didInitialPosition = YES;
    NSInteger unreadRow = [self firstUnreadRow];
    if (unreadRow >= 0) {
        [self anchorRowToTop:unreadRow];
    } else {
        // 无未读：估高会让 scrollToRow…Bottom 欠滚（stop 在真正底部之上）→ 用强制布局后的精确贴底。
        [self scrollToAbsoluteBottom];
    }
    IMLogDebugWithTag(IMLogTagUI, @"chat_initial_position conv_id=%@ rows=%lu unread_row=%ld offset_y=%.1f content_h=%.1f viewport_h=%.1f",
                      self.convID, (unsigned long)self.messages.count, (long)unreadRow,
                      self.tableView.contentOffset.y, self.tableView.contentSize.height,
                      self.tableView.bounds.size.height);
    // 定位后下一轮 runloop（自适应高度落定）再兜一次：无未读精确贴底；有未读重锚首条未读
    //（估高偏差会让锚点漂移——未读只剩末尾几条时表现为"停在底部之上一截"，模拟器日志
    //  chat_initial_position 09:41:02 实锤：偏差 350pt）。之后推进已读/刷新 ↓N。
    dispatch_async(dispatch_get_main_queue(), ^{
        if (unreadRow < 0) { [self scrollToAbsoluteBottom]; }
        else { [self anchorRowToTop:unreadRow]; }
        [self markVisibleRowsRead];
    });
}

/// 把某行锚到视口顶（进会话停首条未读用）：scrollToRow 触发目标区域真实布局后再对齐一轮，
/// 抵消估高偏差；行靠近末尾时 scrollToRow 自带底部 clamp——未读不足一屏时锚定即等价于贴底。
- (void)anchorRowToTop:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.messages.count) { return; }
    NSIndexPath *ip = [NSIndexPath indexPathForRow:row inSection:0];
    for (int pass = 0; pass < 2; pass++) {
        [self.tableView scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionTop animated:NO];
        [self.tableView layoutIfNeeded];
    }
}

/// 可见即读（CHAT_UX §6 完整语义）：扫描当前在视口内的行，取其最大 conv_seq；
/// 若超过已滚入位点则记录并节流上报（read_seq 单调推进，对端据此显示已读双勾、列表未读递减）。
- (void)markVisibleRowsRead {
    int64_t maxSeq = 0;
    for (NSIndexPath *ip in self.tableView.indexPathsForVisibleRows) {
        if (ip.row < (NSInteger)self.messages.count) {
            int64_t s = self.messages[ip.row].convSeq;
            if (s > maxSeq) { maxSeq = s; }
        }
    }
    if (maxSeq > self.pendingReadSeq) {
        self.pendingReadSeq = maxSeq;
        // 节流：滚动停 0.3s 后才真正发，避免每像素一条 receipt。
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(flushReadPosition) object:nil];
        [self performSelector:@selector(flushReadPosition) withObject:nil afterDelay:0.3];
    }
    [self updateJumpButton]; // 位点推进/新消息后刷新 ↓N 计数
}

/// 把节流累积的已读位点上报（仅在超过上次上报值时发）。
- (void)flushReadPosition {
    if (self.pendingReadSeq > self.maxReadReported) {
        self.maxReadReported = self.pendingReadSeq;
        [self performDatabaseOperation:^(IMDatabase *database) {
            [database markConversation:self.convID readUpToConvSeq:self.maxReadReported];
        }];
        [IMSocketManager.sharedManager markReadConv:self.convID upToConvSeq:self.maxReadReported];
    }
}

#pragma mark - 辅助

/// 自己发送：刷新 + 始终贴底（贴底后 ↓N 自动隐藏）。
/// 用精确贴底而非 scrollToRow…Bottom：估高（56）下后者会停在真底部之上，
/// 发媒体/文件（真实行高远超估高）时表现为"没滚到最新消息"。
- (void)appendReloadAndScroll {
    [self.tableView reloadData];
    [self scrollToAbsoluteBottom];
    [self markVisibleRowsRead];
}

#pragma mark - ↓N 跳转按钮 / 自动滚动（CHAT_UX §7、§9）

- (void)scrollToBottomAnimated:(BOOL)animated {
    if (self.messages.count == 0) { return; }
    NSIndexPath *last = [NSIndexPath indexPathForRow:self.messages.count - 1 inSection:0];
    [self.tableView scrollToRowAtIndexPath:last atScrollPosition:UITableViewScrollPositionBottom animated:animated];
}

/// 精确贴底：自适应行高下 contentSize 初始基于估高（estimatedRowHeight=56），单次 layoutIfNeeded 只布局
/// 视口附近的行、离屏行仍是估算 → 一跳会停在真底部之上（进会话不贴底的根因）。
/// 改为「滚到末行(触发底部区域真实布局)→按最新 contentSize 精确对齐→再验证」迭代至收敛（≤6 轮防御死循环）。
- (void)scrollToAbsoluteBottom {
    if (self.messages.count == 0) { return; }
    NSIndexPath *last = [NSIndexPath indexPathForRow:(NSInteger)self.messages.count - 1 inSection:0];
    CGFloat y = 0;
    for (int pass = 0; pass < 6; pass++) {
        [self.tableView scrollToRowAtIndexPath:last atScrollPosition:UITableViewScrollPositionBottom animated:NO];
        [self.tableView layoutIfNeeded];
        CGFloat bottomInset = self.tableView.adjustedContentInset.bottom;
        CGFloat topInset = self.tableView.adjustedContentInset.top;
        y = self.tableView.contentSize.height - self.tableView.bounds.size.height + bottomInset;
        if (y < -topInset) { y = -topInset; }
        if (fabs(self.tableView.contentOffset.y - y) < 0.5) { return; } // 已精确贴底
        [self.tableView setContentOffset:CGPointMake(0, y) animated:NO];
    }
    // 6 轮仍未收敛=估高与真实行高差距过大（历史全是媒体/多行消息）。留痕定位"首进/发送后不贴底"。
    IMLogWarnWithTag(IMLogTagUI, @"chat_stick_bottom_not_converged conv_id=%@ rows=%lu offset_y=%.1f target_y=%.1f content_h=%.1f",
                     self.convID, (unsigned long)self.messages.count, self.tableView.contentOffset.y, y,
                     self.tableView.contentSize.height);
}

/// 是否贴近底部（距底 < 80pt，计入底部安全区 inset）。
- (BOOL)isNearBottom {
    UIScrollView *sv = self.tableView;
    CGFloat distance = sv.contentSize.height - sv.contentOffset.y - sv.bounds.size.height + sv.adjustedContentInset.bottom;
    return distance < 80;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (self.tableView.contentSize.height <= 0) { return; }
    [self markVisibleRowsRead]; // 可见即读：滚到哪、读到哪（先推进 pendingReadSeq）
    [self updateJumpButton];    // 再据新位点刷新 ↓N 计数
}

// 滚动中媒体尺寸落定被延迟的行高重排：拖拽/惯性结束后统一补一次（滚动期间做会肉眼可见地弹跳）。
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (!decelerate) { [self settleRowHeightsIfNeeded]; }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    [self settleRowHeightsIfNeeded];
}

- (void)settleRowHeightsIfNeeded {
    if (!self.needsRowHeightSettle) { return; }
    self.needsRowHeightSettle = NO;
    [self refreshRowHeightsWithoutAnimation];
}

/// 据当前滚动位置显示/隐藏"↓N"：贴底则隐藏；离底则显示，徽标=视口下方未读数（随滚动递减）。
- (void)updateJumpButton {
    if ([self isNearBottom]) {
        self.jumpButton.hidden = YES;
        self.jumpBadge.hidden = YES;
        return;
    }
    self.jumpButton.hidden = NO;
    NSInteger below = [self unreadBelowReadFrontier];
    if (below > 0) {
        self.jumpBadge.hidden = NO;
        self.jumpBadge.text = below > 99 ? @"99+" : [NSString stringWithFormat:@"%ld", (long)below];
    } else {
        self.jumpBadge.hidden = YES;
    }
}

/// 视口下方仍未读的对端消息数 = conv_seq 超过已滚入位点(pendingReadSeq)的对端消息数。
/// 随着向下滚动 pendingReadSeq 推进 → 该数递减，滚到底为 0。
- (NSInteger)unreadBelowReadFrontier {
    NSInteger n = 0;
    for (IMMessageModel *m in self.messages) {
        if (![m.from isEqualToString:self.userID] && m.convSeq > self.pendingReadSeq) { n++; }
    }
    return n;
}

- (void)jumpTapped {
    [self scrollToBottomAnimated:YES];
    [self updateJumpButton];
}

- (void)observeKeyboard {
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardWillChange:)
                                               name:UIKeyboardWillChangeFrameNotification object:nil];
}

- (void)keyboardWillChange:(NSNotification *)note {
    // 缩/放 tableView 前先判贴底：约束链让 inputBar 上移即压缩 tableView 高度，而 UITableView
    // frame 变化时 contentOffset 顶端锚定不动 → 贴底的最新消息会被抬起的输入栏/键盘盖住而非跟随。
    // 交互式收键盘（keyboardDismissMode=Interactive）由 tableView 拖拽驱动，此时 isTracking=YES，
    // 跳过强制滚动以免与用户手势打架；仅在点按聚焦/收起等非拖拽路径重锚（对齐 :2282 的拖拽守卫）。
    BOOL wasNearBottom = !self.tableView.isTracking && [self isNearBottom];
    CGRect endFrame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat overlap = CGRectGetHeight(self.view.bounds) - [self.view convertRect:endFrame fromView:nil].origin.y;
    self.kbInset = MAX(0, overlap - self.view.safeAreaInsets.bottom);
    if (self.kbInset > 0 && self.attachPanelVisible) { // 键盘弹起 → 收起附件面板（二者互斥）
        self.attachPanelVisible = NO;
        self.attachPanel.hidden = YES;
    }
    [self updateInputBottomAnimated:NO];
    // frame 落定后：原本贴底则重锚到底（弹起→上顶，收起→回落，与 inputBar 同帧移动）；
    // 非贴底（正在往前翻历史）维持现状，不打断阅读位置。
    if (wasNearBottom) { [self scrollToAbsoluteBottom]; }
}

/// 把一段操作推迟到键盘完全收起（inset 落定）后在主线程执行一次——用于引用跳转等依赖稳定布局的定位。
/// 一次性监听 UIKeyboardDidHideNotification，触发即摘除；调用方须在已 resignFirstResponder 且键盘确在弹起态时用。
- (void)runAfterKeyboardHidden:(void (^)(void))block {
    if (!block) { return; }
    __block id<NSObject> token = nil;
    __block BOOL done = NO;
    __weak typeof(self) weakSelf = self;
    void (^teardown)(void) = ^{
        if (token) { [NSNotificationCenter.defaultCenter removeObserver:token]; token = nil; }
    };
    token = [NSNotificationCenter.defaultCenter addObserverForName:UIKeyboardDidHideNotification
                                                           object:nil queue:NSOperationQueue.mainQueue
                                                       usingBlock:^(NSNotification *note) {
        if (done) { return; }
        done = YES;
        teardown();
        block(); // 键盘确已收起、布局已稳：执行跳转
    }];
    // 兜底：外接硬件键盘/焦点被别的响应者抢走等场景 UIKeyboardDidHide 可能永不到达，届时这个一次性观察者
    // 及其强引用的 block（内含 self）会永久驻留、泄漏整个聊天页。1s 后强制摘除；但仅当键盘确已收起
    // （kbInset==0）才补跑跳转——否则跳转会打在还没稳定的布局上、落点偏。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (done) { return; }
        done = YES;
        teardown();
        __strong typeof(weakSelf) self = weakSelf;
        if (self && self.kbInset <= 0) { block(); }
    });
}

/// 输入栏底部偏移 = 键盘遮挡 与 面板高度 取较大者（二者互斥，但统一处理避免竞态）。
- (void)updateInputBottomAnimated:(BOOL)animated {
    CGFloat h = MAX(self.kbInset, self.attachPanelVisible ? kIMAttachPanelHeight : 0);
    self.inputBottom.constant = -h;
    if (animated) {
        [UIView animateWithDuration:0.25 animations:^{ [self.view layoutIfNeeded]; }];
    } else {
        [self.view layoutIfNeeded];
    }
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_presenceTickTimer invalidate]; // 兜底：正常路径已在 viewWillDisappear 停掉
}

@end
