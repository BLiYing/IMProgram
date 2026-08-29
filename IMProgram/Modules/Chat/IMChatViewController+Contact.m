//  IMChatViewController+Contact.m
//  个人名片发送（加号面板「个人名片」入口 ①）与点卡片进资料页的落点。
//  单开一个 category 而不是塞进 +Media.m（987 行，体量门禁 1500）——名片与"媒体上传"本就是两件事。
//
//  流程：加号面板 → **复用**通用好友多选页 IMFriendPickerViewController（上限 9）
//        → 卡片式二次确认 sheet（把即将发出的那张卡先给用户看）→ 逐条乐观回显发出。
//  设计见 docs/CONTACT_CARD_DESIGN.md §4。

#import "IMChatViewController+Private.h"
#import "IMFriendPickerViewController.h"
#import "IMChatDetailViewController.h"
#import "IMProfileEditViewController.h"
#import "IMContactCardView.h"
#import "IMContactCard.h"
#import "IMUserCard.h"
#import "IMHTTPService.h"
#import "IMTheme.h"
#import "UIViewController+IMToast.h"

/// 一次最多发几张名片（与转发选择页多选上限一致）。没有上限的话"一次发 200 张"就是刷屏。
static const NSUInteger kIMContactMaxSelection = 9;

@implementation IMChatViewController (Contact)

#pragma mark - 入口 ①：加号面板「个人名片」

/// **必须 push 而不是 present**：IMFriendPickerViewController「页面自身不关闭，由调用方决定后续导航」
/// （见其头注释），既有 4 个调用点也全是 push + popToViewController: 收起。
/// 曾写成模态 present 且 onDone 里不收起 → 随后在同一个 VC 上再 present 确认 sheet，
/// UIKit 因「已在 presenting」直接拒绝：用户勾完人点「发送」毫无反应、一张名片也发不出去
/// （/code-review 2026-08-29 抓到，用户实测同样撞上）。
- (void)openFriendPickerForContactCard {
    __weak typeof(self) ws = self;
    IMFriendPickerViewController *picker =
        [[IMFriendPickerViewController alloc] initWithHost:self.host userID:self.userID
                                               excludedIDs:nil          // 名片不排除任何人（含自己的好友、含当前会话对端）
                                              confirmTitle:@"发送"
                                                    onDone:^(NSArray<NSString *> *uids) {
        __strong typeof(ws) self = ws;
        if (!self || uids.count == 0) { return; }
        [self.navigationController popToViewController:self animated:YES]; // 先收起选人页，确认 sheet 才 present 得出来
        [self prepareContactCardsForUIDs:uids];
    }];
    picker.maxSelection = kIMContactMaxSelection;
    [self.navigationController pushViewController:picker animated:YES];
}

/// 选中 uid → 拉好友资料补齐昵称/头像 → 弹确认 sheet。
/// **必须现拉一次**：选人页只回 uid，而名片快照要冻结昵称与头像；拿不到就只能发一张 `{"u":…}`
/// 的裸卡（收端退化成 ID + 首字母圈）。拉失败时不阻塞发送，按裸卡继续（名片的语义核心是 uid）。
- (void)prepareContactCardsForUIDs:(NSArray<NSString *> *)uids {
    NSString *token = IMHTTPService.sharedService.currentToken;
    __weak typeof(self) ws = self;
    void (^present)(NSArray<IMContactCard *> *) = ^(NSArray<IMContactCard *> *cards) {
        __strong typeof(ws) self = ws;
        if (!self || cards.count == 0) { return; }
        [self presentContactSendConfirmForCards:cards];
    };
    if (token.length == 0) {
        present([self contactCardsFromUIDs:uids friends:nil]);
        return;
    }
    [IMHTTPService.sharedService friendsWithToken:token status:@"accepted"
                                       completion:^(NSArray<IMUserCard *> *friends, NSError *err) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        present([self contactCardsFromUIDs:uids friends:(err ? nil : friends)]);
    }];
}

/// 按选中顺序把 uid 组装成名片快照。
/// ⚠️ 昵称取 `card.nickname` 而**不是** `card.displayName`——后者会优先返回我给对方起的备注，
/// 发出去就是泄露"我给你起的外号"（设计文档 §2.4；chat_record 标题上已踩过同一个坑）。
- (NSArray<IMContactCard *> *)contactCardsFromUIDs:(NSArray<NSString *> *)uids
                                           friends:(NSArray<IMUserCard *> *)friends {
    NSMutableDictionary<NSString *, IMUserCard *> *byID = [NSMutableDictionary dictionary];
    for (IMUserCard *c in friends) { if (c.userID.length > 0) { byID[c.userID] = c; } }
    NSMutableArray<IMContactCard *> *out = [NSMutableArray array];
    for (NSString *uid in uids) {
        if (uid.length == 0) { continue; }
        IMUserCard *src = byID[uid];
        IMContactCard *card = [IMContactCard new];
        card.userID = uid;
        card.nickname = src.nickname;      // 真实昵称，非 displayName
        card.avatarURL = src.avatarURL;
        [out addObject:card];
    }
    return out;
}

#pragma mark - 二次确认 sheet（§4.2）

/// 卡片式 sheet 而不是系统 UIAlertController——因为要**把即将发出的名片先给用户看**，
/// 预览卡 1:1 复用收方将看到的 IMContactCardView（两处各画一遍必然漂移）。
- (void)presentContactSendConfirmForCards:(NSArray<IMContactCard *> *)cards {
    UIViewController *sheet = [UIViewController new];
    sheet.view.backgroundColor = IMTheme.pageBackground;

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    title.textColor = IMTheme.textPrimary;
    title.textAlignment = NSTextAlignmentCenter;
    title.numberOfLines = 2;
    NSString *to = [self conversationDisplayTitle] ?: @"";
    title.text = cards.count == 1
        ? [NSString stringWithFormat:@"发送名片给「%@」", to]
        : [NSString stringWithFormat:@"发送 %lu 张名片给「%@」", (unsigned long)cards.count, to];
    [sheet.view addSubview:title];

    // 首张出全卡，其余折叠成一行显示名（≤3 个，再多显「等 N 人」）——避免 9 张卡把 sheet 撑爆。
    IMContactCardView *preview = [IMContactCardView new];
    preview.translatesAutoresizingMaskIntoConstraints = NO;
    preview.backgroundColor = IMTheme.bubbleThem;
    preview.layer.cornerRadius = IMTheme.radiusBubble;
    [preview configureWithCard:cards.firstObject displayName:nil meta:nil];
    [sheet.view addSubview:preview];

    UILabel *rest = [UILabel new];
    rest.translatesAutoresizingMaskIntoConstraints = NO;
    rest.font = [UIFont systemFontOfSize:13];
    rest.textColor = IMTheme.textSecondary;
    rest.textAlignment = NSTextAlignmentCenter;
    rest.numberOfLines = 1;
    rest.lineBreakMode = NSLineBreakByTruncatingTail;
    rest.text = [self contactRestSummaryForCards:cards];
    rest.hidden = rest.text.length == 0;
    [sheet.view addSubview:rest];

    UIButton *send = [UIButton buttonWithType:UIButtonTypeSystem];
    send.translatesAutoresizingMaskIntoConstraints = NO;
    [send setTitle:@"发送" forState:UIControlStateNormal];
    [send setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    send.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    send.backgroundColor = IMTheme.accent;
    send.layer.cornerRadius = 12;
    [sheet.view addSubview:send];

    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    cancel.translatesAutoresizingMaskIntoConstraints = NO;
    [cancel setTitle:@"取消" forState:UIControlStateNormal];
    cancel.titleLabel.font = [UIFont systemFontOfSize:17];
    [sheet.view addSubview:cancel];

    __weak typeof(self) ws = self;
    __weak UIViewController *wsheet = sheet;
    [send addAction:[UIAction actionWithHandler:^(UIAction *a) {
        __strong typeof(ws) self = ws;
        [wsheet dismissViewControllerAnimated:YES completion:^{
            [self sendContactCards:cards];
        }];
    }] forControlEvents:UIControlEventTouchUpInside];
    [cancel addAction:[UIAction actionWithHandler:^(UIAction *a) {
        [wsheet dismissViewControllerAnimated:YES completion:nil];
    }] forControlEvents:UIControlEventTouchUpInside];

    UILayoutGuide *g = sheet.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:g.topAnchor constant:24],
        [title.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:24],
        [title.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-24],
        [preview.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:20],
        [preview.centerXAnchor constraintEqualToAnchor:g.centerXAnchor],
        [rest.topAnchor constraintEqualToAnchor:preview.bottomAnchor constant:8],
        [rest.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:24],
        [rest.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-24],
        [send.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:24],
        [send.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-24],
        [send.heightAnchor constraintEqualToConstant:50],
        [send.bottomAnchor constraintEqualToAnchor:cancel.topAnchor constant:-8],
        [cancel.leadingAnchor constraintEqualToAnchor:send.leadingAnchor],
        [cancel.trailingAnchor constraintEqualToAnchor:send.trailingAnchor],
        [cancel.heightAnchor constraintEqualToConstant:44],
        [cancel.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-12],
    ]];

    sheet.modalPresentationStyle = UIModalPresentationPageSheet;
    sheet.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.mediumDetent];
    sheet.sheetPresentationController.prefersGrabberVisible = YES;
    [self presentViewController:sheet animated:YES completion:nil];
}

/// ≥2 张时首卡之外的折叠摘要：「小红 · 老王」；超 3 个显「小红 · 老王 · 小刚 等 5 人」。
- (NSString *)contactRestSummaryForCards:(NSArray<IMContactCard *> *)cards {
    if (cards.count < 2) { return @""; }
    NSArray<IMContactCard *> *rest = [cards subarrayWithRange:NSMakeRange(1, cards.count - 1)];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (IMContactCard *c in rest) {
        if (names.count >= 3) { break; }
        [names addObject:(c.nickname.length > 0 ? c.nickname : c.userID)];
    }
    NSString *joined = [names componentsJoinedByString:@" · "];
    return rest.count > names.count
        ? [joined stringByAppendingFormat:@" 等 %lu 人", (unsigned long)rest.count]
        : joined;
}

#pragma mark - 发送

/// 按选中顺序逐条发出（每张名片是独立消息：失败那条独立显红、其余不受影响）。
/// **不出 toast**——气泡本身就是反馈，与发图/发文件一致，别重复报喜。
- (void)sendContactCards:(NSArray<IMContactCard *> *)cards {
    for (IMContactCard *c in cards) {
        NSString *content = IMContactCardBuild(c.userID, c.username, c.nickname, c.avatarURL);
        if (content.length == 0) { continue; }   // 无 uid（理论到不了）：服务端也会拒，不如本地就别发
        [self forwardEchoContent:content contentType:IMContentTypeContact forwardFrom:@""
                        fileName:nil fileSize:0
                          toConv:self.convID toUser:(self.isGroupChat ? @"" : (self.peerID ?: @""))];
    }
}

#pragma mark - 点名片卡 → 资料页（§6）

/// 三处落点（气泡 / 详情页名片行 / 收藏页名片行）共用的同一入口：
/// 先用快照填首屏、进页后再拉 `GET /users/{u}` 覆盖——与 QR 路由、群成员进资料页完全同路径。
/// 名片里的人已注销时资料页显空态，**卡片本身仍显示快照**（历史记录不该凭空变空）。
- (void)openContactProfileForUID:(NSString *)uid nickname:(NSString *)nickname avatarURL:(NSString *)avatarURL {
    if (uid.length == 0) { return; }
    // §6 第四分支：名片里的人就是我自己 → 进**编辑资料**，而不是把自己当"对端"开一个单聊资料页
    //（那个页面有「拉黑」「设置备注」「发消息」，对自己既无意义又危险：拉黑自己会写一条 self→self 黑名单）。
    // 此前无此判断，/code-review 2026-08-29 抓到；Web 侧对应分支走 openProfile()。
    if ([uid isEqualToString:self.userID]) {
        [self.navigationController pushViewController:
            [[IMProfileEditViewController alloc] initWithHost:self.host userID:self.userID] animated:YES];
        return;
    }
    IMChatDetailViewController *vc =
        [[IMChatDetailViewController alloc] initSingleWithHost:self.host userID:self.userID
                                                       peerID:uid
                                                 peerNickname:nickname
                                                peerAvatarURL:avatarURL];
    // 名片里的人就是当前会话对端时，「消息」入口是冗余的（已经在这个会话里了）——与 iOS 既有口径一致。
    vc.showsMessagePill = ![uid isEqualToString:(self.peerID ?: @"")];
    [self.navigationController pushViewController:vc animated:YES];
}

@end
