//  IMChatViewController+Menu.m
//  聊天页「长按消息菜单」分文件实现（数据驱动 IMMenuAction + iOS26 UIContextMenu 光栅化预览）。
//  从 IMChatViewController.m 平移，未改行为；私有属性经 IMChatViewController+Private.h 共享。

#import "IMChatViewController+Private.h"
#import "IMChatViewController+Voice.h"
#import "IMMessageModel.h"
#import "IMMenuAction.h"
#import "IMReadReceiptViewController.h"
#import "IMHTTPService.h"
#import "IMDatabase.h"
#import "IMPendingMediaStore.h"
#import "IMProtocol.h"
#import "IMGroupInfo.h"
#import "IMTheme.h"
#import "IMTimeUtil.h"
#import "IMBubbleCell.h"
#import "IMImageCell.h"
#import "IMLinkCardCell.h"
#import "IMChatRecordCell.h"
#import "UIViewController+IMToast.h"
#import "UIViewController+IMDeleteSheet.h"

@implementation IMChatViewController (Menu)

#pragma mark - 长按消息菜单（数据驱动：IMMenuAction 单一来源）

/// 单条消息的长按菜单配置（供挂在气泡上的 UIContextMenuInteraction 调用）。
/// 为什么不走 UITableView 的行级 contextMenu API：那套的自定义预览 delegate
/// （previewForHighlighting/DismissingContextMenuWithConfiguration:）在 iOS 26 的新菜单管线里**不再被回调**
/// （iOS 16 时 UICollectionView / UIContextMenuInteraction 均已废弃旧签名、换带 identifier 的新 API，
/// 唯独 UITableView 没给替代签名），表现为长按预览退化成系统默认的整行全宽矩形快照。
/// 故改为把交互直接挂在气泡视图上（attachMessageContextMenuToCell:），interaction 的新旧两代
/// 预览 delegate 都实现（见下 pragma 段），iOS 13…26 预览形状全可控。
- (nullable UIContextMenuConfiguration *)messageContextMenuConfigurationForIndexPath:(NSIndexPath *)indexPath {
    if (self.selecting) { return nil; } // 多选态无长按菜单
    if (indexPath.row >= (NSInteger)self.windowState.messages.count) { return nil; }
    IMMessageModel *message = self.windowState.messages[indexPath.row];
    if ([message.contentType isEqualToString:@"system"]) { return nil; } // 系统消息无操作菜单
    if (message.recalledAt > 0) { return nil; } // 撤回墓碑无操作菜单
    if ([self isAlbumMember:message]) { return nil; } // 相册宫格：菜单由每个格子自带（定位到单条成员）
    BOOL mine = [message.from isEqualToString:self.userID];
    NSArray<IMMenuAction *> *actions = [self messageActionsForMessage:message mine:mine];
    // 群聊里自己发的消息：菜单**顶部**挂一条「N 人已读 ›」（M4-8）。人数要查服务端，
    // 故用 UIDeferredMenuElement 异步填——菜单先弹出、这一行随后就位，不阻塞其它操作。
    UIMenuElement *readRow = [self readReceiptMenuElementForMessage:message mine:mine];
    // identifier 传 nil：预览不再靠它反查 cell（改用 interaction.view，见 targetedPreviewForInteraction:），
    // 且 indexPath 会随行插入/删除漂移，留着只会误导。
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil
        actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
            UIMenu *base = [IMMenuAction menuWithActions:actions];
            if (!readRow) { return base; }
            NSMutableArray<UIMenuElement *> *children = [NSMutableArray arrayWithObject:readRow];
            [children addObjectsFromArray:base.children];
            return [UIMenu menuWithTitle:@"" children:children];
        }];
}

/// 给消息 cell 的气泡本体（previewTargetView）挂长按菜单交互，由 willDisplayCell 统一调用。幂等：
/// 同一 view 只挂一次（cell 复用时子视图实例不变，不会越挂越多）；不实现 previewTargetView 的不挂
/// （系统行/撤回墓碑无菜单；相册宫格每个格子自带交互，定位到单条成员）。
- (void)attachMessageContextMenuToCell:(UITableViewCell *)cell {
    if (![cell respondsToSelector:@selector(previewTargetView)]) { return; }
    UIView *target = [(id)cell previewTargetView];
    if (!target) { return; }
    [self attachContextMenuInteractionToView:target];
    // 图说整体化：图/视频 cell 的 caption 文字区不在 previewTargetView(_thumb) 内 → 单独再挂一层交互，
    // 否则长按文字区无反应（缩略图区有反应）。无 caption 时该 view hidden，不接触摸、不弹菜单。
    if ([cell respondsToSelector:@selector(secondaryMenuTargetView)]) {
        UIView *secondary = [(id)cell secondaryMenuTargetView];
        if (secondary) { [self attachContextMenuInteractionToView:secondary]; }
    }
}

/// 幂等挂 UIContextMenuInteraction：同一 view 只挂一次（cell 复用子视图实例不变，不越挂越多）。
- (void)attachContextMenuInteractionToView:(UIView *)view {
    for (id<UIInteraction> it in view.interactions) {
        if ([it isKindOfClass:UIContextMenuInteraction.class]) { return; }
    }
    [view addInteraction:[[UIContextMenuInteraction alloc] initWithDelegate:self]];
}

#pragma mark UIContextMenuInteractionDelegate（消息气泡长按菜单）

- (nullable UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
                                 configurationForMenuAtLocation:(CGPoint)location {
    // interaction 挂在气泡视图上：向上找到所属 cell → indexPath →（复用 cell 也拿到的是当前行的消息）。
    UITableViewCell *cell = nil;
    for (UIView *v = interaction.view; v; v = v.superview) {
        if ([v isKindOfClass:UITableViewCell.class]) { cell = (UITableViewCell *)v; break; }
    }
    NSIndexPath *indexPath = cell ? [self.tableView indexPathForCell:cell] : nil;
    if (!indexPath) { return nil; }
    return [self messageContextMenuConfigurationForIndexPath:indexPath];
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

/// 长按预览只圈气泡本体，且**预览视图是气泡的光栅化位图**而非活视图本身。
/// 为什么要光栅化（iOS26 踩坑记录）：iOS26 的 lift 管线会把**源视图自身的 backgroundColor 从内容里
/// 剥离出来当托盘层**，托盘色由 params.backgroundColor 决定——我们为去掉系统托盘设的 clearColor
/// 在 iOS26 上会连气泡自己的白/绿底一起置透明，预览只剩文字浮在壁纸上（iOS≤18 旧管线是整视图
/// 快照含背景，无此问题）。烘成位图后背景/圆角/尾角都在像素里，系统怎么处理"源视图背景"都影响不到它。
/// 注意不用 snapshotViewAfterScreenUpdates:（复刻视图在源视图被系统隐藏时会变空白），
/// 用 drawViewHierarchyInRect: 画成独立 UIImage。
///
/// **从父视图按气泡矩形开窗裁剪**，而非只画 target 自身子树：链接卡的内容 `_stack`、图片/视频的播放键与
/// 时长/进度角标都是气泡的**兄弟视图**（盖在其上、不在 target 子树内），只画 target 会漏成空气泡/裸封面。
/// 平移父视图坐标系、按 target.frame 开窗光栅化后，凡视觉落在气泡矩形内的同级视图都进快照；昵称/头像/失败❗
/// 在矩形外自然排除。文本/记录卡内容本就在气泡子树内，此法结果与只画 target 一致，故四类 cell 统一走这条。
///
/// useCached=YES（dismissal 收起）复用 highlight 时缓存的快照，不重新截图——否则菜单存续期间整表 reload
/// （收到 WS 消息即触发）会让 target 复用换绑到别的消息，收起动画截到错误内容/空白。缓存在 willEnd 清。
- (nullable UITargetedPreview *)targetedPreviewForInteraction:(UIContextMenuInteraction *)interaction
                                                   useCached:(BOOL)useCached {
    UIView *target = interaction.view;
    // 图说整体化：图/视文 cell 有 caption 时，无论长按缩略图区还是文字区，都统一预览**整张卡片**
    // （否则长按图只掀起图、长按字只掀起字，像两种交互）。从 interaction.view 上溯到 cell 取统一预览视图。
    for (UIView *v = interaction.view; v; v = v.superview) {
        if ([v isKindOfClass:UITableViewCell.class]) {
            if ([v respondsToSelector:@selector(menuPreviewTargetView)]) {
                UIView *unified = [(id)v menuPreviewTargetView];
                if (unified) { target = unified; }
            }
            break;
        }
    }
    if (!target || !target.window || CGRectIsEmpty(target.bounds)) { return nil; }
    UIImage *snapshot = useCached ? self.cachedMenuSnapshot : nil;
    if (!snapshot) {
        UIView *host = target.superview ?: target;
        CGRect win = target.frame; // 气泡在父视图中的矩形（开窗范围）
        // 跳转高亮遮罩（flashRowAtIndexPath: 挂在 target 上的子视图）不能烘进静态预览，否则整菜单存续期都带色。
        UIView *flash = [target viewWithTag:kIMFlashOverlayTag];
        BOOL flashWasHidden = flash.hidden;
        flash.hidden = YES;
        UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
        fmt.opaque = NO;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:target.bounds.size format:fmt];
        snapshot = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            CGContextTranslateCTM(ctx.CGContext, -win.origin.x, -win.origin.y); // 把气泡矩形左上角对到 (0,0)
            [host drawViewHierarchyInRect:host.bounds afterScreenUpdates:NO];
        }];
        flash.hidden = flashWasHidden;
    }
    self.cachedMenuSnapshot = snapshot; // highlight 存、dismissal 命中后仍持有至 willEnd 清
    UIImageView *previewView = [[UIImageView alloc] initWithImage:snapshot]; // frame 由 image 尺寸给出
    UIPreviewParameters *params = [UIPreviewParameters new];
    params.backgroundColor = UIColor.clearColor; // 托盘透明（位图已自带气泡底色，无需托盘补色）
    // 高亮路径仍**逐角复刻气泡的 maskedCorners**（文本气泡尾巴=某个下角直角）：iOS≤18 靠它裁托盘/阴影；
    // 手动构造路径而非 bezierPathWithRoundedRect:byRoundingCorners:——后者对「缺一个下角」的组合
    // 在部分 iOS 版本会画错。未设 maskedCorners 的（媒体=全角）四角同半径，退化为普通圆角矩形。
    params.visiblePath = IMBubbleOutlinePath(target.bounds, target.layer.cornerRadius, target.layer.maskedCorners);
    // 位图钉回气泡原位（container=气泡父视图、center=气泡中心）：lift/收起动画从原位起落，无跳变。
    UIPreviewTarget *previewTarget = [[UIPreviewTarget alloc] initWithContainer:target.superview
                                                                         center:target.center];
    return [[UITargetedPreview alloc] initWithView:previewView parameters:params target:previewTarget];
}

// 预览 delegate 两代都实现：iOS 13–15 走旧签名（16 起废弃但老系统仍回调），
// iOS 16+（含 26）走带 identifier 的新签名——iOS 26 的菜单管线只认这一代。
// highlight 现场光栅化并缓存；dismissal 复用缓存（useCached:YES）。
- (UITargetedPreview *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
    previewForHighlightingMenuWithConfiguration:(UIContextMenuConfiguration *)configuration {
    return [self targetedPreviewForInteraction:interaction useCached:NO];
}

- (UITargetedPreview *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
    previewForDismissingMenuWithConfiguration:(UIContextMenuConfiguration *)configuration {
    return [self targetedPreviewForInteraction:interaction useCached:YES];
}

- (UITargetedPreview *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
                                configuration:(UIContextMenuConfiguration *)configuration
        highlightPreviewForItemWithIdentifier:(id<NSCopying>)identifier API_AVAILABLE(ios(16.0)) {
    return [self targetedPreviewForInteraction:interaction useCached:NO];
}

- (UITargetedPreview *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
                                configuration:(UIContextMenuConfiguration *)configuration
        dismissalPreviewForItemWithIdentifier:(id<NSCopying>)identifier API_AVAILABLE(ios(16.0)) {
    return [self targetedPreviewForInteraction:interaction useCached:YES];
}

/// 菜单收起：动画完成后清预览快照缓存（dismissal 预览在动画开始前取用，先清会拿不到）。
- (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction
      willEndForConfiguration:(UIContextMenuConfiguration *)configuration
                     animator:(id<UIContextMenuInteractionAnimating>)animator {
    __weak typeof(self) ws = self;
    if (animator) {
        [animator addCompletion:^{ ws.cachedMenuSnapshot = nil; }];
    } else {
        self.cachedMenuSnapshot = nil;
    }
}

/// 单条消息的菜单动作（按显示顺序，仅含可见项）：
/// 复制 / 引用 / 转发 / 收藏 / 撤回(仅自己且有真实 conv_seq) / 多选 / 翻译 / 删除(破坏性)；
/// 对方消息额外含 举报消息 / 举报发送者。已接：复制、删除、举报*；其余 → 开发中吐司。
- (NSArray<IMMenuAction *> *)messageActionsForMessage:(IMMessageModel *)message mine:(BOOL)mine {
    __weak typeof(self) ws = self;
    NSMutableArray<IMMenuAction *> *actions = [NSMutableArray array];

    // 语音消息「转文字」：只对已发出的 voice 消息可用。识别在**服务端**跑（2026-08-26 起），
    // 结果按音频内容在服务端与本机各缓存一份；本地"折叠名单"决定面板展开与否。
    // 见 IMServer docs/design/VOICE_TRANSCRIBE_DESIGN.md。
    if ([message.contentType isEqualToString:@"voice"] && message.convSeq > 0 && message.recalledAt == 0) {
        // 已转过 → 菜单项变「取消转文字」（清缓存 + 收起面板）；否则「转文字」。
        BOOL hasTranscript = [self im_hasVoiceTranscript:message];
        NSString *title = hasTranscript ? @"取消转文字" : @"转文字";
        NSString *icon = hasTranscript ? @"text.badge.xmark" : @"text.bubble";
        [actions addObject:[IMMenuAction actionWithId:@"transcribe" title:title image:icon handler:^{
            if (hasTranscript) { [ws im_clearVoiceTranscript:message]; }
            else { [ws im_transcribeVoiceMessage:message]; }
        }]];
    }

    // 复制：仅文本（随时可复制）与已发出的图片（复制图片字节）。文件/聊天记录卡片无复制语义
    //（后者会把整段 JSON 拷进剪贴板）；发送中的图片 content 还是本地引用，复制无意义。与 Web 对齐。
    // 图说消息（image/video/file 带 caption）也可复制——复制的是**文本**（caption），故三类都放开。
    // voice 不可复制（没有可复制文本，音频用「转文字」独立入口）。
    BOOL copyable = ([message.contentType isEqualToString:@"text"] && message.content.length > 0 && message.recalledAt == 0)
                 || ([message.contentType isEqualToString:@"image"] && message.convSeq > 0 && message.recalledAt == 0)
                 || (message.caption.length > 0 && message.convSeq > 0 && message.recalledAt == 0);
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
    int64_t nowMs = IMNowMillis();
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
    [self.windowState.messages removeObject:message];
    if (message.convSeq > 0) { [self.windowState.seenConvSeqs removeObject:@(message.convSeq)]; }
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

#pragma mark - 举报（AG-3）

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

@end
