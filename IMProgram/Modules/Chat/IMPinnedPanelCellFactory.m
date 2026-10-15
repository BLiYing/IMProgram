//  IMPinnedPanelCellFactory.m
//  参数口径对照 IMChatViewController+DataSource.m 的 cellForRowAtIndexPath:（同一批 cell、同一批宿主方法）；
//  面板差异见头文件注释。

#import "IMPinnedPanelCellFactory.h"
#import <objc/runtime.h>
#import "IMMessageModel.h"
#import "IMTheme.h"
#import "IMLocalization.h"
#import "IMMediaUtil.h"                 // IMMediaLooksLikeURL
#import "IMMediaDownloadCoordinator.h"  // 图/视频下载门控
#import "IMDownloadProgress.h"
#import "IMRemarkStore.h"
#import "IMContactCard.h"
#import "IMCallRecord.h"
#import "IMLocateInChatIcon.h"
#import "IMBubbleHitTesting.h"
#import "IMBubbleCell.h"
#import "IMImageCell.h"
#import "IMLinkCardCell.h"
#import "IMChatRecordCell.h"
#import "IMContactCardCell.h"
#import "IMCallRecordCell.h"
#import "Voice/IMVoiceBubbleCell.h"

static NSString * const kIMPinnedCellBubble = @"pinned.bubble";
static NSString * const kIMPinnedCellImage = @"pinned.image";
static NSString * const kIMPinnedCellVoice = @"pinned.voice";
static NSString * const kIMPinnedCellLink = @"pinned.link";
static NSString * const kIMPinnedCellRecord = @"pinned.record";
static NSString * const kIMPinnedCellContact = @"pinned.contact";
static NSString * const kIMPinnedCellCall = @"pinned.call";
static NSString * const kIMPinnedCellDay = @"pinned.day";

/// 定位圆钮规格（PINNED_PANEL_UX_SKETCH ⑤：32×32 圆、图标 18、与气泡间距 8、底边对齐）。
static const CGFloat kIMLocateButtonSide = 32;
static const CGFloat kIMLocateGlyphSide = 18;
static const CGFloat kIMLocateGap = 8;
/// 聊天页气泡距 contentView 侧边的外距（IMBubbleCell 等 _leading/_trailing 的 12）。
static const CGFloat kIMRowSideMargin = 12;
static const void *kIMLocateButtonKey = &kIMLocateButtonKey;

#pragma mark - 定位圆钮

/// 挂在 cell 本身（不进 contentView：只读模式下 contentView 不接触摸，圆钮要能点）。
/// 约束跨层级贴气泡（共同祖先 = cell）；复用时气泡视图或左右侧变了才重建约束。
@interface IMPinnedLocateButton : UIButton
@property (nonatomic, copy, nullable) void (^onTap)(void);
- (void)bindToBubble:(UIView *)bubble inCell:(UITableViewCell *)cell mine:(BOOL)mine;
@end

@implementation IMPinnedLocateButton {
    __weak UIView *_boundBubble;
    BOOL _boundMine;
    NSArray<NSLayoutConstraint *> *_constraints;
}

+ (instancetype)locateButton {
    IMPinnedLocateButton *b = [IMPinnedLocateButton buttonWithType:UIButtonTypeSystem];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b setImage:[IMLocateInChatIcon imageWithSide:kIMLocateGlyphSide] forState:UIControlStateNormal];
    b.tintColor = IMTheme.accent;
    b.backgroundColor = IMTheme.surfaceElevated;
    b.layer.cornerRadius = kIMLocateButtonSide / 2;
    // 压在壁纸上要有底：阴影 0 1px 1px shadow-soft（稿 ⑤）。
    b.layer.shadowColor = UIColor.blackColor.CGColor;
    b.layer.shadowOpacity = 0.18;
    b.layer.shadowOffset = CGSizeMake(0, 1);
    b.layer.shadowRadius = 1;
    b.accessibilityLabel = IMLocalized(@"pinned.locate");
    [b addTarget:b action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [b.widthAnchor constraintEqualToConstant:kIMLocateButtonSide],
        [b.heightAnchor constraintEqualToConstant:kIMLocateButtonSide],
    ]];
    return b;
}

- (void)tapped { if (self.onTap) { self.onTap(); } }

- (void)bindToBubble:(UIView *)bubble inCell:(UITableViewCell *)cell mine:(BOOL)mine {
    if (_constraints && _boundBubble == bubble && _boundMine == mine) { return; }
    if (_constraints) { [NSLayoutConstraint deactivateConstraints:_constraints]; }
    _boundBubble = bubble;
    _boundMine = mine;
    // 我发的：圆钮在气泡左侧；别人的：在气泡右侧（IMPinnedLocateIconOnLeadingSide）。
    NSLayoutConstraint *side = mine
        ? [self.trailingAnchor constraintEqualToAnchor:bubble.leadingAnchor constant:-kIMLocateGap]
        : [self.leadingAnchor constraintEqualToAnchor:bubble.trailingAnchor constant:kIMLocateGap];
    // 气泡最大宽 = 行可用宽 − 头像列 − 图标列（40）：给圆钮让出一列，长文本在气泡内换行、圆钮始终可见。
    // 999：媒体 / 卡片是定宽（≤260），本就放得下，别与其定宽约束冲突。
    CGFloat reserve = kIMRowSideMargin + kIMLocateButtonSide + kIMLocateGap;
    NSLayoutConstraint *room = mine
        ? [bubble.leadingAnchor constraintGreaterThanOrEqualToAnchor:cell.contentView.leadingAnchor constant:reserve]
        : [bubble.trailingAnchor constraintLessThanOrEqualToAnchor:cell.contentView.trailingAnchor constant:-reserve];
    room.priority = UILayoutPriorityRequired - 1;
    _constraints = @[ side, room, [self.bottomAnchor constraintEqualToAnchor:bubble.bottomAnchor] ];
    [NSLayoutConstraint activateConstraints:_constraints];
}

@end

#pragma mark - 日期胶囊行

@interface IMPinnedDayPillCell : UITableViewCell
@property (nonatomic, strong, readonly) UILabel *label;
@end

@implementation IMPinnedDayPillCell {
    UIView *_pill;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _pill = [UIView new];
        _pill.translatesAutoresizingMaskIntoConstraints = NO;
        _pill.layer.cornerRadius = 12;
        _pill.layer.masksToBounds = YES;
        [self.contentView addSubview:_pill];
        _label = [UILabel new];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        _label.textColor = IMTheme.datePillText;
        [_pill addSubview:_label];
        [NSLayoutConstraint activateConstraints:@[
            [_pill.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
            [_pill.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4],
            [_pill.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_pill.heightAnchor constraintEqualToConstant:24],
            [_label.leadingAnchor constraintEqualToAnchor:_pill.leadingAnchor constant:12],
            [_label.trailingAnchor constraintEqualToAnchor:_pill.trailingAnchor constant:-12],
            [_label.centerYAnchor constraintEqualToAnchor:_pill.centerYAnchor],
        ]];
    }
    return self;
}

- (void)applyText:(NSString *)text {
    _pill.backgroundColor = [IMTheme.accent colorWithAlphaComponent:0.64]; // 与 IMBubbleCell 日期分隔同款，随主题色
    _label.text = text;
}

@end

#pragma mark - 工厂

@implementation IMPinnedPanelCellFactory

+ (void)registerCellsInTableView:(UITableView *)tableView {
    [tableView registerClass:IMBubbleCell.class forCellReuseIdentifier:kIMPinnedCellBubble];
    [tableView registerClass:IMImageCell.class forCellReuseIdentifier:kIMPinnedCellImage];
    [tableView registerClass:IMVoiceBubbleCell.class forCellReuseIdentifier:kIMPinnedCellVoice];
    [tableView registerClass:IMLinkCardCell.class forCellReuseIdentifier:kIMPinnedCellLink];
    [tableView registerClass:IMChatRecordCell.class forCellReuseIdentifier:kIMPinnedCellRecord];
    [tableView registerClass:IMContactCardCell.class forCellReuseIdentifier:kIMPinnedCellContact];
    [tableView registerClass:IMCallRecordCell.class forCellReuseIdentifier:kIMPinnedCellCall];
    [tableView registerClass:IMPinnedDayPillCell.class forCellReuseIdentifier:kIMPinnedCellDay];
}

+ (UITableViewCell *)dayPillCellWithText:(NSString *)text tableView:(UITableView *)tableView indexPath:(NSIndexPath *)indexPath {
    IMPinnedDayPillCell *cell = [tableView dequeueReusableCellWithIdentifier:kIMPinnedCellDay forIndexPath:indexPath];
    [cell applyText:text];
    return cell;
}

+ (UITableViewCell *)messageCellForMessage:(IMMessageModel *)m
                                      mine:(BOOL)mine
                                      host:(id<IMPinnedPanelHost>)host
                                 tableView:(UITableView *)tableView
                                 indexPath:(NSIndexPath *)indexPath
                                  onLocate:(void (^)(void))onLocate
                            onLayoutChange:(void (^)(void))onLayoutChange {
    // 群聊对方消息：面板里**每条**都带头像 + 昵称（无连续段合并）；我发的与单聊都不带。
    BOOL grp = host.isGroupChat && !mine;
    NSString *name = grp ? [host senderNameForMessage:m] : nil;
    IMGroupRole role = grp ? [host senderRoleForMessage:m] : IMGroupRoleMember;
    NSString *avatarURL = grp ? [host senderAvatarURLForMessage:m] : nil;
    UITableViewCell *cell = nil;
    NSString *type = m.contentType ?: @"text";

    if ([type isEqualToString:@"chat_record"]) {
        IMChatRecordCell *c = [tableView dequeueReusableCellWithIdentifier:kIMPinnedCellRecord forIndexPath:indexPath];
        c.readOnly = YES;
        [c configureWithMessage:m mine:mine peerReadSeq:kIMPeerReadSeqHidden senderName:name senderRole:role];
        [c applyGroupAvatarURL:avatarURL seed:(m.from ?: @"") name:name showAvatar:grp gutter:grp];
        cell = c;
    } else if ([type isEqualToString:IMContentTypeContact]) {
        IMContactCardCell *c = [tableView dequeueReusableCellWithIdentifier:kIMPinnedCellContact forIndexPath:indexPath];
        c.readOnly = YES;
        IMContactCard *card = IMContactCardParse(m.content);
        NSString *shown = card ? [IMRemarkStore.sharedStore displayNameForUser:card.userID fallback:card.nickname] : nil;
        [c configureWithMessage:m mine:mine displayName:shown peerReadSeq:kIMPeerReadSeqHidden senderName:name senderRole:role];
        [c applyGroupAvatarURL:avatarURL seed:(m.from ?: @"") name:name showAvatar:grp gutter:grp];
        cell = c;
    } else if ([type isEqualToString:IMContentTypeCall] && IMCallRecordParse(m.content)) {
        IMCallRecordCell *c = [tableView dequeueReusableCellWithIdentifier:kIMPinnedCellCall forIndexPath:indexPath];
        c.readOnly = YES;
        [c configureWithMessage:m mine:mine displayName:nil peerReadSeq:kIMPeerReadSeqHidden senderName:name senderRole:role];
        [c applyGroupAvatarURL:avatarURL seed:(m.from ?: @"") name:name showAvatar:grp gutter:grp];
        cell = c;
    } else if ([type isEqualToString:@"text"] && m.translation.length == 0 && IMMediaLooksLikeURL(m.content)) {
        IMLinkCardCell *c = [tableView dequeueReusableCellWithIdentifier:kIMPinnedCellLink forIndexPath:indexPath];
        c.readOnly = YES;
        [c configureWithMessage:m mine:mine peerReadSeq:kIMPeerReadSeqHidden senderName:name senderRole:role];
        [c applyGroupAvatarURL:avatarURL seed:(m.from ?: @"") name:name showAvatar:grp gutter:grp];
        c.onContentSizeResolved = onLayoutChange;
        cell = c;
    } else if ([type isEqualToString:@"voice"]) {
        IMVoiceBubbleCell *c = [tableView dequeueReusableCellWithIdentifier:kIMPinnedCellVoice forIndexPath:indexPath];
        c.readOnly = YES;
        [c configureWithMessage:m mine:mine dayHeader:nil showsUnreadDivider:NO senderName:name senderRole:role
                      hasPlayed:YES peerReadSeq:kIMPeerReadSeqHidden isGroupContext:host.isGroupChat];
        [c applyGroupAvatarURL:avatarURL seed:(m.from ?: @"") name:name showAvatar:grp gutter:grp];
        cell = c;
    } else if ([type isEqualToString:@"image"] || [type isEqualToString:@"video"]) {
        cell = [self imageCellForMessage:m mine:mine host:host name:name role:role avatarURL:avatarURL grp:grp
                               tableView:tableView indexPath:indexPath onLayoutChange:onLayoutChange];
    } else {
        cell = [self bubbleCellForMessage:m mine:mine host:host name:name role:role avatarURL:avatarURL grp:grp
                                tableView:tableView indexPath:indexPath onLayoutChange:onLayoutChange];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    [self attachLocateButtonToCell:cell mine:mine onTap:onLocate];
    return cell;
}

+ (UITableViewCell *)imageCellForMessage:(IMMessageModel *)m mine:(BOOL)mine host:(id<IMPinnedPanelHost>)host
                                    name:(NSString *)name role:(IMGroupRole)role avatarURL:(NSString *)avatarURL grp:(BOOL)grp
                               tableView:(UITableView *)tableView indexPath:(NSIndexPath *)indexPath
                          onLayoutChange:(void (^)(void))onLayoutChange {
    IMImageCell *c = [tableView dequeueReusableCellWithIdentifier:kIMPinnedCellImage forIndexPath:indexPath];
    c.readOnly = YES;
    // 门控与聊天页一致：策略说「未下载」就只显封面 / 模糊占位，不因进了面板就偷拉原图。
    IMDownloadProgress *gate = [host.downloads stateForMessage:m];
    c.gated = gate != nil;
    c.downloadProgress = gate;
    c.captionMentionMap = [host mentionMapForCaption:m];
    c.captionMentionSpans = [host mentionSpansForCaption:m];
    NSString *fullURL = m.content.length > 0 ? [host fullMediaURL:m.content] : @"";
    NSString *posterURL = m.poster.length > 0 ? [host fullMediaURL:m.poster] : nil;
    [c configureWithMessage:m fullURL:fullURL posterURL:posterURL mine:mine peerReadSeq:kIMPeerReadSeqHidden
               previewImage:nil senderName:name senderRole:role];
    [c applyGroupAvatarURL:avatarURL seed:(m.from ?: @"") name:name showAvatar:grp gutter:grp];
    [c setUploadProgress:nil];
    c.onMediaSizeResolved = ^(CGSize size) { if (onLayoutChange) { onLayoutChange(); } };
    return c;
}

+ (UITableViewCell *)bubbleCellForMessage:(IMMessageModel *)m mine:(BOOL)mine host:(id<IMPinnedPanelHost>)host
                                     name:(NSString *)name role:(IMGroupRole)role avatarURL:(NSString *)avatarURL grp:(BOOL)grp
                                tableView:(UITableView *)tableView indexPath:(NSIndexPath *)indexPath
                           onLayoutChange:(void (^)(void))onLayoutChange {
    IMBubbleCell *c = [tableView dequeueReusableCellWithIdentifier:kIMPinnedCellBubble forIndexPath:indexPath];
    c.readOnly = YES;
    c.uploadProgress = nil;
    c.downloadProgress = nil; // 文件：不画下载环（只读，点气泡去聊天里下）
    c.onFileControlTap = nil;
    c.textExpanded = NO;
    c.mentionMap = [host mentionMapForMessage:m];
    c.captionMentionMap = [host mentionMapForCaption:m];
    c.mentionSpans = [host mentionSpansForMessage:m];
    c.captionMentionSpans = [host mentionSpansForCaption:m];
    c.searchHighlightKeyword = nil;
    c.onLinkPreviewResolved = onLayoutChange;
    NSString *replyFrom = (host.isGroupChat && m.replyToConvSeq > 0 && m.replyToFrom.length > 0)
        ? [host replyFromNameForUID:m.replyToFrom] : nil;
    // 引用缩略图不取：被引用那条多半不在面板里，引用条退回类型小图标（与聊天页「目标不在窗口」同形）。
    [c configureWithMessage:m mine:mine peerReadSeq:kIMPeerReadSeqHidden dayHeader:nil showsUnreadDivider:NO
                 senderName:name senderRole:role replyThumbURL:nil replyThumbData:nil replyThumbIsVideo:NO
              replyFromName:replyFrom];
    [c applyGroupAvatarURL:avatarURL seed:(m.from ?: @"") name:name showAvatar:grp gutter:grp];
    return c;
}

+ (void)attachLocateButtonToCell:(UITableViewCell *)cell mine:(BOOL)mine onTap:(void (^)(void))onTap {
    UIView *bubble = [self bubbleViewInCell:cell];
    if (!bubble) { return; }
    IMPinnedLocateButton *button = objc_getAssociatedObject(cell, kIMLocateButtonKey);
    if (!button) {
        button = [IMPinnedLocateButton locateButton];
        [cell addSubview:button];
        objc_setAssociatedObject(cell, kIMLocateButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    button.onTap = onTap;
    [button bindToBubble:bubble inCell:cell mine:mine];
}

+ (UIView *)bubbleViewInCell:(UITableViewCell *)cell {
    if ([cell isKindOfClass:IMPinnedDayPillCell.class]) { return nil; }
    // 图说消息（有 caption）：整张卡片才是「气泡」（与聊天页长按预览同一视图）。
    if ([cell respondsToSelector:@selector(menuPreviewTargetView)]) { return [(id)cell menuPreviewTargetView]; }
    if ([cell respondsToSelector:@selector(previewTargetView)]) { return [(id)cell previewTargetView]; }
    return nil;
}

+ (BOOL)cell:(UITableViewCell *)cell bubbleContainsPoint:(CGPoint)point {
    if ([cell conformsToProtocol:@protocol(IMBubbleHitTesting)]) {
        return [(id<IMBubbleHitTesting>)cell pointInsideBubble:point];
    }
    UIView *bubble = [self bubbleViewInCell:cell];
    if (!bubble || bubble.hidden) { return NO; }
    return CGRectContainsPoint([bubble convertRect:bubble.bounds toView:cell], point);
}

@end
