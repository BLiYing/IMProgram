//  IMChatViewController.m

#import "IMChatViewController.h"
#import "IMChatViewController+Private.h" // 私有类扩展（属性/协议）——与分文件 category 共享
#import "IMChatMessageLogic.h"        // 文件级纯逻辑：@提及 token / 未读口径 / 引用占位
#import "IMPasteImageTextField.h"     // 支持粘贴图片的输入框（#2）
#import "IMPendingMediaThumbnail.h"   // 本地待发媒体缩略图生成
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
#import "IMChatBannerStack.h"
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

#define IMLooksLikeURL(s) IMMediaLooksLikeURL(s)

#pragma mark - 聊天页

// 私有类扩展（属性/协议/指定初始化器）已移至 IMChatViewController+Private.h，
// 供本主实现文件与各分文件 category（+Media / +Menu / +Selection …）共享。

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

/// 下载编排器懒加载：策略判定 / 门控态 / 点击路由 / 落地位置全在 `IMMediaDownloadCoordinator`
/// （与会话详情页共用同一份实现）。直接访问 _downloads ivar，故留在主实现文件（category 不可见 ivar）。
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
        // 命中的就是栈顶（如在群里点了本群的邀请链接）：用户已在目标会话且本页是活 delegate、数据实时，
        // 只补播种即可。不 pop（对栈顶是 no-op）也**不清定位标志**——此时 viewWillAppear 不会触发，
        // 清了标志会在下一次任意重布局/新消息时把正上翻历史的用户猛拉回底部。
        if (existing != nav.topViewController) {
            [existing prepareForReuseEntry];
            [nav popToViewController:existing animated:YES];
        }
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
        // 单聊与群相反：非空即覆盖。聊天页对 peer 昵称/头像没有任何服务端刷新（页内值只来自
        // 更早的播种，可能过期），caller 的成员表/会话行快照永远 ≥ 页内值，覆盖才能修「对方改名」。
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
        // 群字段只填空缺、不覆盖：页内值可能已被 reloadGroupInfo 刷成服务端最新（caller 的会话行/群卡
        // 快照反而更旧，覆盖会把改过的群名退回旧名）；新实例初始化器已置名，fill-if-empty 语义等价。
        // 复用时的权威刷新交给 prepareForReuseEntry 里的 reloadGroupInfo。
        if (chat.groupName.length == 0 && name.length > 0) { chat.groupName = name; }
        if (chat.groupAvatarURL.length == 0 && groupAvatarURL.length > 0) { chat.groupAvatarURL = groupAvatarURL; }
    }];
}

/// 复用已在栈中的旧实例前的刷新（仅在实例非栈顶、即将真正 pop 时调用）：
/// ①按最新播种值重装标题/头像按钮（否则 seed 落在无人再读的属性上）；群聊再拉一次 reloadGroupInfo，
///   用服务端权威值纠正群名/头像/横幅（caller 快照与页内值都可能过期）；
/// ②清定位标志，让 pop 回来时像重新进入一样重锚到底部/未读，而非停在旧滚动位。
/// 被压期间错过的消息**不在这里合并**：pop 必触发 viewWillAppear，那里按 synced 游标守卫合并，
/// 避免此处无条件全量读库 + appear 再读一次的双重开销。
- (void)prepareForReuseEntry {
    if (self.isViewLoaded) {
        [self refreshDisplayIdentity];
        if (self.isGroupChat) { [self reloadGroupInfo]; }
    }
    self.didInitialPosition = NO;
    self.didInitialSettle = NO;
    // 重进语义=贴底：进入时的未读快照早已消化，清零让重锚走「无未读→精确贴底」分支；
    // 不清的话 firstUnreadRow 会拿冻结的 entryReadSeq 把用户锚回早已读过的旧「首条未读」。
    self.entryUnread = 0;
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
    // 合并的新消息可能落在视口外：重算 ↓N 徽标并推进可见位点已读（与 didReceiveMessage 同口径），
    // 否则用户停在历史位置时看不到任何「下面有新消息」的指示。
    [self markVisibleRowsRead];
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
        self.bannerStack.announcementText = group.announcement.length ? group.announcement : nil; // G1 公告横幅（setter 应用）
        [self.bannerStack applyApprovalPending:[self approvalPendingCount]]; // G3：群主/管理员待审入群申请横幅
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
        self.bannerStack.pinnedItems = items ?: @[]; // setter 内部夹紧索引 + 收起态判定 + 顶开 tableView
    }];
}

/// 待审批人数：仅群聊且我是群主/管理员才计，其余 0。喂给横幅栈决定是否显 G3 蓝条。
- (NSInteger)approvalPendingCount {
    BOOL canManage = self.groupInfo.myRole == IMGroupRoleOwner || self.groupInfo.myRole == IMGroupRoleAdmin;
    return (self.isGroupChat && canManage) ? self.groupInfo.pendingCount : 0;
}

#pragma mark IMChatBannerStackDelegate

/// 三横幅叠加总高变化 → 顶开消息表内容（放一处算，避免各方法各自覆盖 inset.top）。
- (void)bannerStackDidChangeHeight:(IMChatBannerStack *)stack {
    CGFloat top = stack.totalHeight;
    UIEdgeInsets inset = self.tableView.contentInset;
    if (inset.top == top) { return; }
    inset.top = top;
    self.tableView.contentInset = inset;
}

/// 点置顶横幅主体：跳到当前那条（轮转已在横幅栈内部处理）。
- (void)bannerStack:(IMChatBannerStack *)stack didRequestJumpToConvSeq:(int64_t)convSeq {
    [self jumpToConvSeq:convSeq];
}

/// 点入群申请横幅：进审批列表（同意/拒绝后回调重拉，角标随之更新）。
- (void)bannerStackDidTapApproval:(IMChatBannerStack *)stack {
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
    NSString *text = self.bannerStack.announcementText;
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
- (void)bannerStackDidTapAnnouncement:(IMChatBannerStack *)stack {
    NSString *text = stack.announcementText;
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

/// 点右侧列表键：半屏列出全部置顶消息，点行跳转；有权限者可就地取消置顶。
- (void)bannerStackDidTapPinnedList:(IMChatBannerStack *)stack {
    NSArray<IMPinnedMessage *> *items = stack.pinnedItems;
    if (items.count == 0) { return; }
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"置顶消息"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) ws = self;
    BOOL canPin = [self canPinMessages];
    for (IMPinnedMessage *item in items) {
        NSString *sender = [item senderLabelForGroup:self.isGroupChat];
        NSString *title = sender.length > 0
            ? [NSString stringWithFormat:@"%@：%@", sender, item.previewText]
            : item.previewText;
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            [ws jumpToConvSeq:item.convSeq];
        }]];
    }
    IMPinnedMessage *shown = stack.currentPinnedItem;
    if (canPin && shown) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"取消置顶当前这条" style:UIAlertActionStyleDestructive
                                               handler:^(UIAlertAction *action) {
            [IMSocketManager.sharedManager pinMessageInConv:(ws.convID ?: @"")
                                              targetConvSeq:shown.convSeq pinned:NO];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = stack.pinnedBannerView;
    sheet.popoverPresentationController.sourceRect = stack.pinnedBannerView.bounds;
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

    // 顶部三横幅栈（G0 置顶 / G1 公告 / G3 入群申请）：浮在消息表之上、紧贴安全区顶（Glass 导航栏正下方）。
    // 视图/布局/高度→内边距/收起持久化全在 IMChatBannerStack；点击导航经 delegate 回本页。
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    self.bannerStack = [[IMChatBannerStack alloc] initWithHostView:self.view
                                                         topAnchor:guide.topAnchor
                                                           isGroup:self.isGroupChat
                                                            userID:self.userID
                                                            convID:self.convID];
    self.bannerStack.delegate = self;

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

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self sendTapped];
    return NO;
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
    // 长按菜单交互统一在此挂（单一咽喉点，取代原先在 cellForRow 各类型分支各补一行——漏接一种即静默无菜单）。
    // 幂等；system/albumPad 等不实现 previewTargetView 的 cell 自动跳过；相册宫格每格自带交互不受影响。
    [self attachMessageContextMenuToCell:cell];
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
