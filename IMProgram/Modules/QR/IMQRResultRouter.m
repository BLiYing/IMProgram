//  IMQRResultRouter.m

#import "IMQRResultRouter.h"

#import "IMChatDetailViewController.h"
#import "IMChatViewController.h"
#import "IMGroupJoinPreviewViewController.h"
#import "IMHTTPService.h"
#import "IMQRCardViewController.h"
#import "IMQRLoginConfirmViewController.h"
#import "IMQRModels.h"
#import "UIViewController+IMToast.h"

/// 需管理员审批：`POST /groups/join` 用它表示"申请已提交"，不是失败。
static const NSInteger kIMErrCodeJoinPending = 300210;
/// 二维码失效（过期/被重置/不存在共用一码一文案）。
static const NSInteger kIMErrCodeQRExpired = 200110;

@implementation IMQRResultRouter

+ (void)routeResolved:(IMQRResolved *)resolved raw:(NSString *)raw
                 host:(NSString *)host userID:(NSString *)userID fromController:(UIViewController *)vc {
    if (!resolved || !vc) { return; }
    switch (resolved.kind) {
        case IMQRKindUser:  [self routeUser:resolved.user host:host userID:userID from:vc]; break;
        case IMQRKindGroup: [self routeGroup:resolved.group raw:raw host:host userID:userID from:vc]; break;
        case IMQRKindLogin: [self routeLogin:resolved.login host:host userID:userID from:vc]; break;
        case IMQRKindUnknown:
        default:            [self routeUnknownText:resolved.unknownText from:vc]; break;
    }
}

+ (BOOL)routeInviteLinkIfOwn:(NSString *)urlString host:(NSString *)host
                      userID:(NSString *)userID fromController:(UIViewController *)vc {
    if (urlString.length == 0 || host.length == 0 || !vc) { return NO; }
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url || !([url.scheme isEqualToString:@"http"] || [url.scheme isEqualToString:@"https"])) { return NO; }
    // host 匹配（self.host 形如 "localhost:8080"，NSURL.host 不含端口 → 拼回端口比对）。
    // 兜底：链接 host 是 localhost/127.0.0.1（dev 默认 -public-url 出的码）时也拦——真机连局域网 IP 场景
    // 精确比对必失败，而 resolve 走的是本机配置的 host（能通），拦下来走站内流程好过跳一个打不开的 Safari。
    NSString *urlHost = url.port ? [NSString stringWithFormat:@"%@:%@", url.host, url.port] : (url.host ?: @"");
    BOOL isDevLoopback = [url.host isEqualToString:@"localhost"] || [url.host isEqualToString:@"127.0.0.1"];
    if (![urlHost isEqualToString:host] && !isDevLoopback) { return NO; }
    // 只拦名片码/群码；登录码 /q/l 与其它路径放行走浏览器（落地页承接）。
    NSString *path = url.path ?: @"";
    if (!([path hasPrefix:@"/q/u/"] || [path hasPrefix:@"/q/g/"])) { return NO; }
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return NO; }
    [vc im_showToast:@"解析中…"];
    __weak UIViewController *wvc = vc;
    [IMHTTPService.sharedService qrResolveWithToken:token raw:urlString completion:^(NSDictionary *resolved, NSError *error) {
        __strong UIViewController *svc = wvc;
        if (!svc) { return; }
        if (error) { [self presentError:error fromController:svc]; return; }
        [self routeResolved:[IMQRResolved fromDictionary:resolved] raw:urlString host:host userID:userID fromController:svc];
    }];
    return YES;
}

+ (void)presentError:(NSError *)error fromController:(UIViewController *)vc {
    // 失效码是"扫码四分支"里的一支，给弹窗而不是一闪而过的 toast——用户需要读懂"去向对方要张新的"。
    // 刻意不区分过期/被重置/不存在（区分等于给爆破者反馈信号），文案由服务端 200110 统一映射。
    if (error.code == kIMErrCodeQRExpired) {
        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:@"二维码已失效"
                                                message:(error.localizedDescription ?: @"该二维码已过期或被重置，请向对方索取新的二维码。")
                                         preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"我知道了" style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:alert animated:YES completion:nil];
        return;
    }
    [vc im_showToast:error.localizedDescription ?: @"识别失败"];
}

#pragma mark - 名片码

/// 不新建"扫码结果页"，直接进已有资料页——加好友/发消息由资料页按好友态自行决定（少一处三端分叉）。
+ (void)routeUser:(IMQRUserCard *)card host:(NSString *)host userID:(NSString *)userID from:(UIViewController *)vc {
    if (!card || card.userID.length == 0) { [vc im_showToast:@"二维码内容有误"]; return; }
    if (IMQRUserActionForRelation(card.relation) == IMQRUserActionSelf) {
        // 扫自己的码：不给"加好友"，直接把他送回自己的名片码页（大概率是想给别人看）。
        [vc im_showToast:@"这是你自己的名片码"];
        IMQRCardViewController *mine = [[IMQRCardViewController alloc] initMyCardWithHost:host userID:userID
                                                                                nickname:card.nickname
                                                                               avatarURL:card.avatarURL];
        [vc.navigationController pushViewController:mine animated:YES];
        return;
    }
    IMChatDetailViewController *detail =
        [[IMChatDetailViewController alloc] initSingleWithHost:host userID:userID peerID:card.userID
                                                 peerNickname:(card.nickname.length ? card.nickname : card.userID)
                                                peerAvatarURL:card.avatarURL];
    detail.showsMessagePill = YES; // 从外部（扫码）进入，需要给出进单聊的入口
    [vc.navigationController pushViewController:detail animated:YES];
}

#pragma mark - 群码

/// G3 加群预览页（sketch §05）：独立页展示群头像/名/人数/邀请人 + 附言输入 + 主按钮（按 joinable 变）。
/// 替换旧兜底 alert——弹窗装不下头像、也不是"页"。（备注：简介 `intro` 待 /qr/resolve 返回后再展示。）
+ (void)routeGroup:(IMQRGroupCard *)card raw:(NSString *)raw
              host:(NSString *)host userID:(NSString *)userID from:(UIViewController *)vc {
    if (!card || card.groupID.length == 0) { [vc im_showToast:@"二维码内容有误"]; return; }
    IMQRGroupAction action = IMQRGroupActionForCard(card);
    [IMGroupJoinPreviewViewController pushFrom:vc host:host card:card action:action onSubmit:^(NSString *hello) {
        switch (action) {
            case IMQRGroupActionEnter:    [self enterGroup:card host:host userID:userID from:vc]; break;
            case IMQRGroupActionJoin:     [self joinGroup:card raw:raw hello:@"" host:host userID:userID from:vc]; break;
            case IMQRGroupActionApply:    [self joinGroup:card raw:raw hello:hello host:host userID:userID from:vc]; break;
            case IMQRGroupActionDisabled: break; // 不可加入：按钮禁用，不回调
        }
    }];
}

+ (void)joinGroup:(IMQRGroupCard *)card raw:(NSString *)raw hello:(NSString *)hello
             host:(NSString *)host userID:(NSString *)userID from:(UIViewController *)vc {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { [vc im_showToast:@"登录已失效，请重新登录"]; return; }
    [IMHTTPService.sharedService joinGroupWithToken:token code:raw ?: @"" hello:hello ?: @""
                                         completion:^(IMGroupInfo *_Nullable group, NSError *_Nullable error) {
        if (error) {
            // 300210 不是失败：申请已落库，等管理员审批（`join_result` 帧会回来）。
            [vc im_showToast:(error.code == kIMErrCodeJoinPending
                              ? @"申请已提交，等待管理员审批"
                              : (error.localizedDescription ?: @"加入群聊失败"))];
            return;
        }
        [self enterGroup:card host:host userID:userID from:vc];
    }];
}

+ (void)enterGroup:(IMQRGroupCard *)card host:(NSString *)host userID:(NSString *)userID from:(UIViewController *)vc {
    IMChatViewController *chat = [[IMChatViewController alloc] initWithHost:host userID:userID
                                                               groupConvID:card.groupID
                                                                 groupName:card.name
                                                                   readSeq:0 unread:0
                                                              groupReadSeq:0]; // 扫码入口无会话快照，全员已读位点由从会话列表进入时播种
    chat.groupAvatarURL = card.avatarURL;
    [vc.navigationController pushViewController:chat animated:YES];
}

#pragma mark - 扫码登录（QR P1）

/// 扫到网页版登录码：先 /qr/login/scan 拿 Web 端设备/IP/位置，再 push 确认页。
/// resolve 已校验票据可用；scan 若回 200110（并发过期/被抢）走统一失效 alert。
+ (void)routeLogin:(IMQRLoginTicket *)ticket host:(NSString *)host userID:(NSString *)userID from:(UIViewController *)vc {
    if (!ticket || ticket.ticket.length == 0) { [vc im_showToast:@"二维码内容有误"]; return; }
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { [vc im_showToast:@"登录已失效，请重新登录"]; return; }
    [IMHTTPService.sharedService qrLoginScanWithToken:token ticket:ticket.ticket
                                          completion:^(NSDictionary *_Nullable info, NSError *_Nullable error) {
        if (error) { [self presentError:error fromController:vc]; return; }
        NSString *device = [info[@"device"] isKindOfClass:NSString.class] ? info[@"device"] : nil;
        NSString *ip = [info[@"ip"] isKindOfClass:NSString.class] ? info[@"ip"] : nil;
        NSString *location = [info[@"location"] isKindOfClass:NSString.class] ? info[@"location"] : nil;
        [IMQRLoginConfirmViewController pushFrom:vc ticket:ticket.ticket device:device ip:ip location:location];
    }];
}

#pragma mark - 外来码

/// 非本站码：显示原文，**不自动跳转**；是 http(s) 才给"在浏览器中打开"，且先把域名主体亮出来。
+ (void)routeUnknownText:(NSString *)text from:(UIViewController *)vc {
    NSString *content = text.length ? text : @"未能识别该二维码";
    NSString *domain = IMQRUnknownDomain(text);
    NSString *message = domain.length
        ? [NSString stringWithFormat:@"%@\n\n链接来自二维码，可能是钓鱼站点。确认域名「%@」无误再打开。", content, domain]
        : content;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"扫描结果"
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    if (domain.length > 0) {
        NSURL *url = [NSURL URLWithString:[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];
        if (url) {
            [alert addAction:[UIAlertAction actionWithTitle:@"在浏览器中打开" style:UIAlertActionStyleDefault
                                                    handler:^(UIAlertAction *_Nonnull a) {
                [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
            }]];
        }
    }
    if (text.length > 0) {
        [alert addAction:[UIAlertAction actionWithTitle:@"复制内容" style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *_Nonnull a) {
            UIPasteboard.generalPasteboard.string = text;
            [vc im_showToast:@"已复制"];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [vc presentViewController:alert animated:YES completion:nil];
}

@end
