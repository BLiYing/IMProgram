//  IMChatViewController+Nav.m
//  聊天页「右上圆头像按钮 + 资料页入口」分文件实现：标题栏 44pt 玻璃圆钮内嵌裁圆头像的绘制/安装/异步换图，
//  以及点头像进群资料页 / 单聊资料页 / 群成员资料页、拒收系统行的「发送好友申请」恢复入口。
//  从 IMChatViewController.m 平移，未改行为。

#import "IMChatViewController+Private.h"  // 含 IMGroupInfo（self.groupInfo 成员昵称/头像）
#import "IMChatDetailViewController.h"
#import "IMImageLoader.h"
#import "IMHTTPService.h"
#import "IMMainTabBarController.h"        // im_refreshNavigationBar
#import "UILabel+IMAvatar.h"              // IMAvatarInitials
#import "UIViewController+IMToast.h"
#import "IMTheme.h"
#import "IMAccountIdentity.h"

/// 右上圆头像按钮（单聊对方 / 群聊群头像），点击进资料页。
/// 44pt 官方 Glass 按钮直接承接点击和系统按压动画，内部 30pt 头像严格裁圆。
static UIImage *IMChatAvatarImage(UIImage *photo, NSString *seed, NSString *name, CGFloat diameter) {
    // 系统通知会话（seed=system）：走应用 logo（LaunchLogo）——与会话列表 / UILabel+IMAvatar 同一契约。
    // 见 docs/SYSTEM_NOTICE_SESSION_DESIGN.md §2.1。
    if (IMIsSystemUserID(seed) && !photo) {
        UIImage *logo = [UIImage imageNamed:@"LaunchLogo"];
        if (logo) {
            photo = logo;
        }
    }
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
            NSString *display = IMAvatarInitials(name.length ? name : seed);
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

@implementation IMChatViewController (Nav)

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
                                                                              peerNickname:IMDisplayName(nick, nil)
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

@end
