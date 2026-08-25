//  IMChatViewController+Selection.m
//  聊天页「多选态」分文件实现（#2：转发/收藏/删除 + 合并转发）。
//  从 IMChatViewController.m 平移，未改行为；私有属性经 IMChatViewController+Private.h 共享。

#import "IMChatViewController+Private.h"
#import "IMMessageModel.h"
#import "IMConversation.h"
#import "IMForwardPickerViewController.h"
#import "IMHTTPService.h"
#import "IMDatabase.h"
#import "IMProtocol.h"
#import "IMMediaUtil.h"
#import "IMMediaExpiryRegistry.h"
#import "IMTheme.h"
#import "IMTimeUtil.h"
#import "IMGlass.h"
#import "IMAlbumCell.h"
#import "IMChatSearchState.h"
#import "IMChatSelectionState.h"
#import "IMPopoverCard.h"
#import "UIViewController+IMToast.h"

static const CGFloat kIMSelectionBarH = 48; // 底部选择栏高度（=搜索导航 kIMSearchNavBarH，堆叠时按钮间距一致）

@implementation IMChatViewController (Selection)

#pragma mark - 多选态（#2：转发/收藏/删除）

/// 进入多选：表格进入编辑多选态，隐藏输入栏、显示底部工具栏，并默认选中触发的那条。
/// 列表**锚定长按的那条消息不动**（相册成员锚到其宫格 leader 行），避免进出多选时视口漂移。
- (void)enterSelectionWithMessage:(IMMessageModel *)message {
    if (self.selecting) { return; }
    self.selecting = YES;
    self.selectionState = [IMChatSelectionState new];          // 多选态状态袋：进入创建、退出置 nil 整体释放
    self.selectionState.selectedMediaSeqs = [NSMutableSet set]; // 相册逐格勾选集（2a），每次进多选清空
    [self showAttachPanel:NO];
    [self cancelReply];
    [self.inputField resignFirstResponder];

    // 长按某相册格 → 只预选该格（左侧全选圈不主动打勾）；非相册消息 → 预选其整行。锚定用宫格 leader 行防漂移。
    BOOL triggeredAlbum = [self isAlbumMember:message] && message.convSeq > 0;
    if (triggeredAlbum) { [self.selectionState.selectedMediaSeqs addObject:@(message.convSeq)]; }
    NSUInteger row = [self visibleRowForMessage:message];
    if (row == NSNotFound) { row = [self.messages indexOfObject:message]; }
    [self preserveScreenPositionOfRow:row during:^{
        self.tableView.allowsMultipleSelectionDuringEditing = YES;
        [self.tableView setEditing:YES animated:NO];
        [self.tableView reloadData]; // 相册宫格保持聚簇（整组一个勾选单位），仅切换到编辑态显左侧勾选圈
        // 已在屏上的 cell 不会再走 willDisplay，就地改 selectionStyle 让勾选态可见（#5）。
        for (UITableViewCell *c in self.tableView.visibleCells) { [self applySelectionStyleForCell:c]; }
    }];

    [self extendTableBottomForSelection]; // 壁纸铺到底：透明选择栏后的玻璃钮浮在壁纸上、无背景
    [self buildSelectionBarIfNeeded];
    [self.view bringSubviewToFront:self.selectionBar];
    self.selectionBar.hidden = NO;
    self.inputBar.hidden = YES;
    // 与搜索共存：不隐藏搜索底部导航——选择栏堆叠在其**上方**（updateSelectionBarBottomAnchor 已按搜索态定位）。
    [self updateSelectionBarBottomAnchor];
    [self updateJumpButtonBottomAnchor]; // 向下钮改贴选择栏顶（若可见，堆在删除钮上方不重叠）

    self.savedTitle = self.title;
    self.savedRightItem = self.navigationItem.rightBarButtonItem; // 存下右项，退出多选原样恢复（保留头像项，不置 nil）
    // a(6)-A：多选态**保留右上头像项**（不再置 nil）——标题「已选择 N 条」点击复用 titleButton→右项 action 路由进详情。
    // 必须用**带标题**的 item：统一 Liquid 标题栏按 leftTitle 渲染左位文字并把点击路由到本 item；
    // 系统 Cancel item 无标题 → 被回落成返回箭头、点击直接 pop 出聊天页（"没有取消按钮"的根因）。
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"取消" style:UIBarButtonItemStylePlain
                                        target:self action:@selector(exitSelection)];

    // 相册格：勾选态在逐格 checkbox（selectedMediaSeqs），只在整组恰好只有这一格时才让左圈打勾；
    // 非相册消息：预选其整行。
    if (triggeredAlbum) {
        [self syncAlbumRowSelectionForGroupID:message.groupID];
    } else if (row != NSNotFound) {
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
        [self.tableView reloadData]; // 退出编辑态；相册宫格始终聚簇渲染（进出多选不再重排行结构）
        for (UITableViewCell *c in self.tableView.visibleCells) { [self applySelectionStyleForCell:c]; }
    }];
    self.selectionBar.hidden = YES;
    self.selectionState.barBottom.active = NO;          // 复位选择栏底边约束
    [self restoreTableBottomForSelection];              // 还原表底（若搜索态在，则表底由搜索维持、此处是 no-op）
    self.selectionState = nil;                          // 整袋释放（逐格勾选集 / 表底约束 / 选择栏底边）
    [self updateJumpButtonBottomAnchor];               // 向下钮落回 replyBar/搜索栏顶
    // 与搜索共存：仍在搜索态则搜索栏本就一直显示、输入栏保持隐藏；否则恢复输入栏。
    self.inputBar.hidden = self.searchState.searching ? YES : NO;
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
    // 与会话内搜索底部导航**同构且对齐**：透明容器定高 kIMSelectionBarH(=搜索栏高)，三个 36pt 玻璃钮——
    // 转发左对齐 📅(leading+16)、删除右对齐 ▼(trailing-16)、收藏居中；壁纸铺到底后钮浮其上、无背景。
    UIView *bar = [UIView new];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.backgroundColor = UIColor.clearColor;
    [self.view addSubview:bar];
    self.selectionBar = bar;

    UIButton *fwd = [self selectionBarButton:@"转发" image:@"arrowshape.turn.up.right" action:@selector(forwardSelected)];
    fwd.tag = 1;
    UIButton *fav = [self selectionBarButton:@"收藏" image:@"bookmark" action:@selector(favoriteSelected)];
    fav.tag = 2;
    // 删除：点击弹「仅为我删除」自定义气泡（复用 IMPopoverCard、锚删除钮上方，不与按钮重叠）。
    UIButton *del = [self selectionBarButton:@"删除" image:@"trash" action:@selector(deleteButtonTapped:)];
    del.tag = 3;
    [bar addSubview:fwd]; [bar addSubview:fav]; [bar addSubview:del];
    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bar.heightAnchor constraintEqualToConstant:kIMSelectionBarH],
        [fwd.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:16],
        [fwd.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [del.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-16],
        [del.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [fav.centerXAnchor constraintEqualToAnchor:bar.centerXAnchor],
        [fav.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
    ]];
    [self updateSelectionBarBottomAnchor]; // 底边：搜索开着=贴搜索栏顶（上下堆叠）/否则=安全区底
}

/// 删除钮点击 → 在钮**上方**弹「仅为我删除」确认气泡（复用详情页「更多」同款 IMPopoverCard，不与按钮重叠）。
- (void)deleteButtonTapped:(UIButton *)sender {
    if ([self selectedMessages].count == 0) { return; } // 兜底：此时按钮本应已禁用
    __weak typeof(self) ws = self;
    IMPopoverCardItem *item = [IMPopoverCardItem itemWithTitle:@"仅为我删除" symbol:@"trash" destructive:YES
                                                       handler:^{ [ws performDeleteSelected]; }];
    [IMPopoverCard presentFromAnchor:sender inHostView:self.view items:@[item]];
}

/// 选择栏底边定位：搜索底部导航开着时,选择栏钉在其**上方**（两排按钮堆叠、互不重叠）；否则钉安全区底。
/// 搜索进/出（endInChatSearch）与进多选时各调用一次。
- (void)updateSelectionBarBottomAnchor {
    if (!self.selectionBar) { return; }
    self.selectionState.barBottom.active = NO;
    UIView *searchNav = self.searchState.searching ? self.searchState.searchNavBar : nil;
    if (searchNav && !searchNav.hidden) {
        self.selectionState.barBottom = [self.selectionBar.bottomAnchor constraintEqualToAnchor:searchNav.topAnchor];
    } else {
        self.selectionState.barBottom = [self.selectionBar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor];
    }
    self.selectionState.barBottom.active = YES;
}

/// 多选期间把消息表底从「replyBar 顶」改到「屏幕底」：壁纸铺到底，透明选择栏后的玻璃钮浮在壁纸上而非 self.view 纯色底。
/// 搜索态已自行铺到底（extendTableToScreenBottom），此处不重复改，退出各自还原。
- (void)extendTableBottomForSelection {
    if (self.searchState.searching) { return; }
    if (self.selectionState.tableBottom) { return; }
    NSLayoutConstraint *orig = nil;
    for (NSLayoutConstraint *c in self.view.constraints) {
        if (c.firstItem == self.tableView && c.firstAttribute == NSLayoutAttributeBottom) { orig = c; break; }
    }
    if (!orig) { return; }
    self.selectionState.savedTableBottom = orig;
    orig.active = NO;
    self.selectionState.tableBottom = [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor];
    self.selectionState.tableBottom.active = YES;
    UIEdgeInsets ci = self.tableView.contentInset;
    self.selectionState.savedBottomInset = ci.bottom;
    ci.bottom = self.selectionState.savedBottomInset + kIMSelectionBarH + 8; // 底部内容不被玻璃钮盖住
    self.tableView.contentInset = ci;
}

- (void)restoreTableBottomForSelection {
    if (!self.selectionState.tableBottom) { return; }
    self.selectionState.tableBottom.active = NO; self.selectionState.tableBottom = nil;
    self.selectionState.savedTableBottom.active = YES; self.selectionState.savedTableBottom = nil;
    UIEdgeInsets ci = self.tableView.contentInset;
    ci.bottom = self.selectionState.savedBottomInset;
    self.tableView.contentInset = ci;
}

/// 独立圆形 Liquid Glass 按钮（复用全站配方 + Capsule；定尺 **36pt**，与搜索底栏 searchGlassButtonSymbol 一致）。
/// 图标承载语义（辅助功能读 title）；删除用系统红以突出破坏性。
- (UIButton *)selectionBarButton:(NSString *)title image:(NSString *)image action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *cfg = IMGlassButtonConfiguration();
    cfg.image = [UIImage systemImageNamed:image];
    cfg.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    cfg.baseForegroundColor = [title isEqualToString:@"删除"] ? UIColor.systemRedColor : IMTheme.textPrimary;
    b.configuration = cfg;
    b.accessibilityLabel = title;
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [b.widthAnchor constraintEqualToConstant:36],
        [b.heightAnchor constraintEqualToConstant:36],
    ]];
    if (action) { [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside]; }
    return b;
}

/// 向下钮底边随「多选/搜索」态重定位：多选态贴选择栏顶、搜索态贴搜索栏顶、否则贴 replyBar 顶——
/// 保证「向下钮 / 多选行 / 搜索行」自上而下堆叠、间距一致、不重叠（b：某些机型会与删除钮重叠）。
- (void)updateJumpButtonBottomAnchor {
    if (!self.jumpButtonBottom) { return; }
    self.jumpButtonBottom.active = NO;
    NSLayoutYAxisAnchor *topAnchor; CGFloat gap;
    if (self.selecting && self.selectionBar) { topAnchor = self.selectionBar.topAnchor; gap = 6; }
    else if (self.searchState.searching && self.searchState.searchNavBar) { topAnchor = self.searchState.searchNavBar.topAnchor; gap = 6; }
    else { topAnchor = self.replyBar.topAnchor; gap = 12; }
    self.jumpButtonBottom = [self.jumpButton.bottomAnchor constraintEqualToAnchor:topAnchor constant:-gap];
    self.jumpButtonBottom.active = YES;
}

/// 已选消息（按行序）。相册**逐格勾选**（2a）：成员按 selectedMediaSeqs（conv_seq 集合）判定；
/// 非相册消息仍按表格行选中判定。整组"全选"只是左侧系统圈的显示态，不作为选中来源（避免重复）。
- (NSArray<IMMessageModel *> *)selectedMessages {
    NSMutableSet<NSNumber *> *selRows = [NSMutableSet set];
    for (NSIndexPath *ip in self.tableView.indexPathsForSelectedRows) { [selRows addObject:@(ip.row)]; }
    NSMutableArray<IMMessageModel *> *out = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.messages.count; i++) {
        IMMessageModel *m = self.messages[i];
        BOOL selected;
        if ([self isAlbumMember:m]) {
            selected = m.convSeq > 0 && [self.selectionState.selectedMediaSeqs containsObject:@(m.convSeq)];
        } else {
            selected = [selRows containsObject:@(i)];
        }
        if (selected) { [out addObject:m]; }
    }
    return out;
}

/// 相册逐格勾选切换（2a）：翻转该成员在 selectedMediaSeqs 的选中，同步左侧系统圈（整组全选态），刷新计数。
- (void)toggleAlbumMemberSelection:(IMMessageModel *)member {
    if (member.convSeq <= 0) { return; }
    if (!self.selectionState.selectedMediaSeqs) { self.selectionState.selectedMediaSeqs = [NSMutableSet set]; }
    NSNumber *seq = @(member.convSeq);
    if ([self.selectionState.selectedMediaSeqs containsObject:seq]) { [self.selectionState.selectedMediaSeqs removeObject:seq]; }
    else { [self.selectionState.selectedMediaSeqs addObject:seq]; }
    [self syncAlbumRowSelectionForGroupID:member.groupID];
    [self updateSelectionUI];
}

/// 把某相册组的左侧系统圈同步为「全部成员已勾选」：全选→选中 leader 行（圈打勾），否则取消。
/// 程序化 select/deselect 不触发 didSelect/didDeselect（无递归）。仅改左圈显示，不改逐格状态。
- (void)syncAlbumRowSelectionForGroupID:(NSString *)gid {
    if (gid.length == 0) { return; }
    NSArray<IMMessageModel *> *members = [self albumMembersForGroupID:gid];
    NSMutableArray<IMMessageModel *> *selectable = [NSMutableArray array];
    for (IMMessageModel *m in members) { if (m.convSeq > 0) { [selectable addObject:m]; } }
    BOOL allSelected = selectable.count > 0;
    for (IMMessageModel *m in selectable) { if (![self.selectionState.selectedMediaSeqs containsObject:@(m.convSeq)]) { allSelected = NO; break; } }
    NSUInteger leaderRow = members.count > 0 ? [self visibleRowForMessage:members.firstObject] : NSNotFound;
    if (leaderRow == NSNotFound || leaderRow >= self.messages.count) { return; }
    NSIndexPath *ip = [NSIndexPath indexPathForRow:(NSInteger)leaderRow inSection:0];
    if (allSelected) { [self.tableView selectRowAtIndexPath:ip animated:NO scrollPosition:UITableViewScrollPositionNone]; }
    else { [self.tableView deselectRowAtIndexPath:ip animated:NO]; }
}

- (void)updateSelectionUI {
    // 用展开后的真实条数（相册整组算 N 条）——与转发/删除的作用条数一致，不再按"行数"少算。
    NSUInteger n = [self selectedMessages].count;
    self.title = n > 0 ? [NSString stringWithFormat:@"已选择 %lu 条", (unsigned long)n] : @"选择消息";
    // a(4)：0 选中时三钮置灰禁用（系统按钮自动变淡、不可点）→ 去掉「请先选择消息」吐司。
    BOOL has = n > 0;
    ((UIButton *)[self.selectionBar viewWithTag:1]).enabled = has; // 转发
    ((UIButton *)[self.selectionBar viewWithTag:2]).enabled = has; // 收藏
    ((UIButton *)[self.selectionBar viewWithTag:3]).enabled = has; // 删除
    [self refreshUnifiedNavigationBar]; // 标题与「取消」左钮由统一 Liquid 栏渲染，改完必须刷一次
}

#pragma mark 多选工具栏动作

- (void)forwardSelected {
    NSArray<IMMessageModel *> *msgs = [self selectedMessages];
    if (msgs.count == 0) { return; } // 按钮禁用兜底：0 选中不弹吐司（a4）
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
- (IMMediaAttributes *)forwardAttributesForMessage:(IMMessageModel *)message stripCaption:(BOOL)stripCaption {
    BOOL isMedia = [message.contentType isEqualToString:@"image"] || [message.contentType isEqualToString:@"video"];
    // 图说：文件也可能带 caption，需建 attrs 承载；stripCaption=YES 时视 caption 为不存在。
    BOOL hasCaption = !stripCaption && message.caption.length > 0;
    if (!isMedia && !hasCaption) { return nil; }
    IMMediaAttributes *attrs = [IMMediaAttributes new];
    if (isMedia) {
        attrs.poster = message.poster;          // 视频封面（不带的话 Web 收端解不了 HEVC 就只剩空白）
        attrs.thumb = message.thumb;            // 极小模糊预览：不带的话收端未下载态只有空磨砂、没内容轮廓
        attrs.pixelWidth = message.mediaW;
        attrs.pixelHeight = message.mediaH;
        attrs.durationMillis = message.duration;
        attrs.fileSize = message.fileSize;
    }
    // 图说整体转发（Telegram 模型）：caption + mentions 随转发跟随——收端 @ 高亮可点、被@者强提醒
    // （服务端按目标群成员再过滤，非成员自动落普通文字）。**不带 mentionAll**：@所有人 需目标群
    // 群主/管理员权限，无权会整条拒发 300204，且转发不该再次全员强提醒（与 Web 同取舍）。
    // stripCaption=YES（资料页文件 tab 转发入口）：视角看不到 caption/mentions，一并清空，避免把
    // 原发件人当时的「@xxx 附言」意外带到目标会话。其余入口（长按/查看器/多选/收藏）保留。
    if (!stripCaption) {
        attrs.caption = message.caption;
        attrs.mentions = message.mentions;
    }
    return attrs;
}

/// attributes：原消息的封面/尺寸/时长。转发不带就等于把这些信息丢了（收端只能按未知渲染，事后补不回）。
- (void)forwardEchoContent:(NSString *)content contentType:(NSString *)ct forwardFrom:(NSString *)origin fileName:(NSString *)fileName fileSize:(int64_t)fileSize
                attributes:(IMMediaAttributes *)attributes toConv:(NSString *)convID toUser:(NSString *)toUser {
    IMMessageModel *m = [IMMessageModel new];
    int64_t sentAt = IMNowMillis();
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
    m.caption = attributes.caption.length > 0 ? attributes.caption : nil; // 图说随转发跟随（本端气泡即时显）
    m.mentions = attributes.mentions; // 配文 @ 落到本端回显行：再次转发这条时才能继续重发 mentions（强提醒链不断）
    m.groupID = attributes.groupID.length > 0 ? attributes.groupID : nil; // 整体转发相册：本端回显也聚簇成宫格
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

/// 该消息是否可被转发（撤回/空内容/系统/发送中·失败本地件/失效媒体一律不可）。
- (BOOL)isForwardableMessage:(IMMessageModel *)m {
    if (m.recalledAt > 0 || m.content.length == 0 || [m.contentType isEqualToString:@"system"]) { return NO; }
    if (m.convSeq <= 0) { return NO; }
    if ([self isMediaExpiredForForward:m]) { return NO; }
    return YES;
}

- (void)forwardMessages:(NSArray<IMMessageModel *> *)msgs perMessageToConversations:(NSArray<IMConversation *> *)convs {
    // 失效媒体跳过（转出去对端必 404）：先数一次，避免在会话外层循环里重复计数。
    NSUInteger expiredCount = 0;
    for (IMMessageModel *m in msgs) { if ([self isMediaExpiredForForward:m]) { expiredCount++; } }
    // 整体转发相册（用户要求）：同一原相册被选 ≥2 张 → 用**一个新的共享 group_id** 一起转发，收端重新聚成宫格；
    // 只选 1 张或非相册 → 单发。逐个目标会话独立生成新 group_id（不同会话的转发相册互不串）。
    NSCountedSet<NSString *> *albumCount = [NSCountedSet set];
    for (IMMessageModel *m in msgs) {
        if (![self isForwardableMessage:m]) { continue; }
        if (m.groupID.length > 0 && [self isAlbumMember:m]) { [albumCount addObject:m.groupID]; }
    }
    for (IMConversation *c in convs) {
        NSString *toUser = c.isGroup ? @"" : (c.peer ?: @"");
        NSMutableDictionary<NSString *, NSString *> *newGidForOld = [NSMutableDictionary dictionary]; // 原 group_id → 本会话新 group_id
        for (IMMessageModel *m in msgs) {
            if (![self isForwardableMessage:m]) { continue; } // 撤回/空/系统/发送中失败/失效 一律跳过
            NSString *origin = m.forwardFrom.length > 0 ? m.forwardFrom
                : (m.fromNickname.length > 0 ? m.fromNickname : (m.from ?: @""));
            // 主消息流多选批量转发：用户在气泡上勾选，看得到 caption，按 Telegram 语义保留一起转过去。
            IMMediaAttributes *attrs = [self forwardAttributesForMessage:m stripCaption:NO];
            if (m.groupID.length > 0 && [self isAlbumMember:m] && [albumCount countForObject:m.groupID] >= 2) {
                NSString *newGid = newGidForOld[m.groupID];
                if (!newGid) { newGid = [@"alb-" stringByAppendingString:NSUUID.UUID.UUIDString]; newGidForOld[m.groupID] = newGid; }
                if (!attrs) { attrs = [IMMediaAttributes new]; }
                attrs.groupID = newGid; // 整体转发：同册共享新 group_id，收端聚簇
            }
            [self forwardEchoContent:m.content contentType:(m.contentType ?: @"text") forwardFrom:origin fileName:m.fileName fileSize:m.fileSize
                          attributes:attrs toConv:c.convID toUser:toUser];
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
    if (msgs.count == 0) { return; } // 按钮禁用兜底：0 选中不弹吐司（a4）
    for (IMMessageModel *m in msgs) {
        if (m.recalledAt > 0 || m.content.length == 0 || [m.contentType isEqualToString:@"system"]) { continue; }
        [self favoriteMessage:m];
    }
    [self exitSelection];
}

/// 直接执行删除（确认已由删除钮上方的「仅为我删除」菜单完成，此处不再二次确认）。仅删本端。
- (void)performDeleteSelected {
    NSArray<IMMessageModel *> *msgs = [self selectedMessages];
    if (msgs.count == 0) { return; } // 按钮禁用兜底：0 选中不弹吐司（a4）
    for (IMMessageModel *m in msgs) {
        [self performDatabaseOperation:^(IMDatabase *database) {
            [database deleteMessage:m];
        }];
        [self.messages removeObject:m];
        if (m.convSeq > 0) { [self.seenConvSeqs removeObject:@(m.convSeq)]; }
    }
    [self.tableView reloadData];
    [self exitSelection];
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
        if (m.caption.length > 0) { item[@"cap"] = m.caption; } // 图说条目携带 caption（cap，与 Web 同 key）→ 记录卡「有字显字」
        [items addObject:item];
    }
    // 多选态下 self.title 已被替换为"已选择 N 条"，用 savedTitle 取真实会话名。
    NSString *base = self.savedTitle.length ? self.savedTitle : (self.title.length ? self.title : (self.peerID ?: @"聊天"));
    NSDictionary *dict = @{ @"t": [NSString stringWithFormat:@"%@ 的聊天记录", base], @"items": items };
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:NULL];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
}

#pragma mark - 编辑/选择 delegate（tableView）

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
    if (self.selecting) {
        // 相册 leader 行的左侧系统圈 = 整组全选（点圈落到这里；逐格点选走 toggleAlbumMemberSelection: 程序化改圈、不触发本回调）。
        [self applyAlbumSelectAll:YES atRow:indexPath.row];
        [self updateSelectionUI];
        return;
    }
    // 上传中/失败的文件气泡不再响应整条点击：暂停/继续/重试/取消收敛到左侧图标位的圆环状态机
    //（cell.onFileControlTap → handlePendingMediaTap:），气泡其余区域仅在发送完成后点击打开文件。
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.selecting) {
        [self applyAlbumSelectAll:NO atRow:indexPath.row]; // 相册 leader 行取消 = 整组全不选
        [self updateSelectionUI];
    }
}

/// 相册 leader 行左侧系统圈全选/全不选：把整组成员 conv_seq 批量加入/移出 selectedMediaSeqs，并就地刷新该 cell 的逐格勾选框。
/// 非相册行不处理（其选中已由系统行选中表达）。
- (void)applyAlbumSelectAll:(BOOL)selectAll atRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.messages.count) { return; }
    IMMessageModel *m = self.messages[(NSUInteger)row];
    if (![self isAlbumMember:m] || m.groupID.length == 0) { return; }
    if (!self.selectionState.selectedMediaSeqs) { self.selectionState.selectedMediaSeqs = [NSMutableSet set]; }
    for (IMMessageModel *mm in [self albumMembersForGroupID:m.groupID]) {
        if (mm.convSeq <= 0) { continue; }
        if (selectAll) { [self.selectionState.selectedMediaSeqs addObject:@(mm.convSeq)]; }
        else { [self.selectionState.selectedMediaSeqs removeObject:@(mm.convSeq)]; }
    }
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
    if ([cell isKindOfClass:IMAlbumCell.class]) { [(IMAlbumCell *)cell refreshTileSelectionStates]; }
}

@end
