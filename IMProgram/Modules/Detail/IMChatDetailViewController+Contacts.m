//  IMChatDetailViewController+Contacts.m
//  详情页「名片」页签（IMDetailTabKindContacts）：行渲染 + 点击落地。
//  单开一个 category 而不是塞回 IMChatDetailViewController.m —— 后者 1486 行、体量门禁上限 1500，
//  再往里加就撞闸（CODING_STYLE §7）。数据源无需新代码：recomputeTabContentWithMessages 已按
//  matchesKind: 泛化到任意内容页签。

#import "IMChatDetailViewController+Private.h"
#import "IMDetailContactCell.h"
#import "IMContactCard.h"
#import "IMMessageModel.h"
#import "IMGroupInfo.h"
#import "IMRemarkStore.h"

@implementation IMChatDetailViewController (Contacts)

- (UITableViewCell *)contactRowCellIn:(UITableView *)tv message:(IMMessageModel *)m {
    IMDetailContactCell *cell = [tv dequeueReusableCellWithIdentifier:@"detailcontact"];
    if (!cell) {
        cell = [[IMDetailContactCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"detailcontact"];
    }
    IMContactCard *card = IMContactCardParse(m.content);
    // 理论到不了（脏名片已被 matchesKind: 挡在 tabRows 之外），但 cell 是复用的：
    // 直接 return 会把**上一行**的名字/头像留在屏幕上，故显式走 nil 分支清空。
    if (!card) { [cell configureWithCard:nil displayName:nil sourceName:nil timestampMillis:0]; return cell; }
    // 主行显示名走**本机**口径（备注 > 快照昵称）——与卡片气泡、资料页标题同源，
    // 不会一处叫「老王」另一处叫「王建国」。
    NSString *shown = [IMRemarkStore.sharedStore displayNameForUser:card.userID fallback:card.nickname];
    // 「由 X 分享」：群聊才显（单聊详情页里发送者只可能是我或对方，写出来纯冗余）。
    NSString *source = nil;
    if (self.isGroup) {
        NSString *from = m.from ?: @"";
        if ([from isEqualToString:self.userID]) {
            source = @"你自己";
        } else if (from.length > 0) {
            NSString *nick = [self.group nicknameOfMember:from] ?: from;
            source = [IMRemarkStore.sharedStore displayNameForUser:from fallback:nick];
        }
    }
    [cell configureWithCard:card displayName:shown sourceName:source timestampMillis:m.timestamp];
    return cell;
}

- (void)openContactRowAtIndex:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.tabRows.count) { return; }
    [self openProfileForContactMessage:self.tabRows[row]];
}

- (void)openProfileForContactMessage:(IMMessageModel *)m {
    IMContactCard *card = IMContactCardParse(m.content);
    if (!card) { return; }
    // 名片里的人是我自己 → 仍进资料页（主按钮为「编辑资料」，由资料页自判），不特殊处理；
    // 唯一要避的是在**自己的**资料页上再 push 一个同 uid 的页（无意义的自我嵌套）。
    if ([card.userID isEqualToString:self.userID] && [self.peerID isEqualToString:self.userID]) { return; }
    // 先用快照填首屏、进页后再拉 GET /users/{u} 覆盖——与 QR 路由、群成员进资料页完全同路径。
    IMChatDetailViewController *vc =
        [[IMChatDetailViewController alloc] initSingleWithHost:self.host userID:self.userID
                                                       peerID:card.userID
                                                 peerNickname:card.nickname
                                                peerAvatarURL:card.avatarURL];
    vc.showsMessagePill = YES; // 从名片进 → 需要「消息」入口发起单聊
    [self.navigationController pushViewController:vc animated:YES];
}

@end
