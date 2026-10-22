//  IMChatDetailViewController+Settings.m
//  会话设置的读取（置顶/免打扰/标未读/备注/自动删除档位）与「自动删除消息」行。
//  从主文件拆出：主文件加这一行时触了 1500 行门禁（CODING_STYLE §7）。

#import "IMChatDetailViewController+Private.h"
#import "IMAutoDelete.h"
#import "IMAutoDeleteScheduler.h"
#import "IMAutoDeleteTierViewController.h"
#import "IMDatabase.h"
#import "IMDatabase+AutoDelete.h"
#import "IMHTTPService.h"
#import "IMHTTPService+AutoDelete.h"
#import "IMConversation.h"
#import "IMLocalization.h"
#import "UIViewController+IMToast.h"

@implementation IMChatDetailViewController (Settings)

#pragma mark - 读取

- (void)loadConversationSettings {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    __weak typeof(self) ws = self;
    // 单会话设置端点（GET …/{id}/settings）：只要几个布尔，不再拉整张会话列表遍历查找。
    [IMHTTPService.sharedService conversationSettingsWithToken:token convID:self.convID
                                                    completion:^(NSDictionary *data, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) {
            // 兜底走老路（全量会话列表）：新 GET 端点是 2026-08-18 才加的，连到未重启的旧后端会 404。
            // **不能**静默保留 0/NO 默认——开关会渲染错，且随后的提交是整体替换 PUT，会拿错误基线
            // 悄悄清掉服务端的置顶/标未读（PUT 路由旧后端就有，写得进去）。
            [self loadConversationSettingsViaListFallback:token];
            return;
        }
        self.pinnedAt = [data[@"pinned_at"] longLongValue];
        self.muted = [data[@"muted"] boolValue];
        self.muteUntil = [data[@"mute_until"] longLongValue];
        self.markedUnread = [data[@"marked_unread"] boolValue]; // PUT 整体替换，提交时须回传
        [self adoptAutoDeleteConfig:IMAutoDeleteConfigFromJSON(data[@"auto_delete_sec"], data[@"auto_delete_from"])];
        NSString *rmk = [data[@"remark"] isKindOfClass:[NSString class]] ? data[@"remark"] : nil;
        self.convRemark = rmk.length > 0 ? rmk : nil; // 群备注（G1）：替代群名显示
        [self reloadSettingsAndPills];
        [self refreshHeaderTexts]; // 备注变化 → 头部标题即时跟随
    }];
}

/// 旧后端兼容：按老方式拉全量会话列表找本会话的设置（仅在单会话端点失败时走）。
- (void)loadConversationSettingsViaListFallback:(NSString *)token {
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService conversationsWithToken:token completion:^(NSArray<IMConversation *> *convs, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self || error) { return; }
        for (IMConversation *c in convs) {
            if ([c.convID isEqualToString:self.convID]) {
                self.pinnedAt = c.pinnedAt;
                self.muted = c.muted;
                self.muteUntil = c.muteUntil;
                self.markedUnread = c.markedUnread;
                [self adoptAutoDeleteConfig:[IMAutoDeleteConfig configWithSec:c.autoDeleteSec from:c.autoDeleteFrom]];
                self.convRemark = c.remark.length > 0 ? c.remark : nil;
                [self reloadSettingsAndPills];
                [self refreshHeaderTexts];
                break;
            }
        }
    }];
}

/// 采纳服务端权威设置（sec + from 成对）：落本机小表；变了（别的成员 / 设备改的，或本机刚改）且 sec>0 就立即清理本会话。
- (void)adoptAutoDeleteConfig:(IMAutoDeleteConfig *)cfg {
    self.autoDeleteSec = cfg.sec;
    self.autoDeleteFrom = cfg.from;
    BOOL changed = [IMDatabase.sharedDatabase setAutoDeleteConfig:cfg forConv:self.convID];
    if (changed && cfg.active) { [IMAutoDeleteScheduler.shared requestSweepForConv:self.convID]; }
}

#pragma mark - 自动删除消息行

- (void)configureAutoDeleteCell:(UITableViewCell *)cell {
    cell.textLabel.text = IMLocalized(@"ps.row.auto_delete_messages");
    cell.detailTextLabel.text = IMAutoDeleteTierTitle(self.autoDeleteSec);
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.accessibilityIdentifier = @"detail.autodel";
}

/// 群聊里本机已知不是群主 / 管理员 → 只读。群资料还没加载到（角色未知）先放行，权限以服务端 300204 为准。
- (BOOL)autoDeleteIsReadOnly {
    return self.isGroup && self.group != nil && ![self canManageGroup];
}

- (void)openAutoDeleteTier {
    __weak typeof(self) ws = self;
    NSString *footer = IMLocalized(self.isGroup ? @"autodel.conv.footer_group" : @"autodel.conv.footer");
    IMAutoDeleteTierViewController *vc = [[IMAutoDeleteTierViewController alloc]
        initWithCurrentSec:self.autoDeleteSec footer:footer optimistic:NO
        onSelect:^(int64_t sec, void (^done)(BOOL)) {
            __strong typeof(ws) self = ws;
            if (!self) { done(NO); return; }
            if (!IMAutoDeleteNeedsConfirm(self.autoDeleteSec, sec)) { [self saveAutoDeleteSec:sec done:done]; return; }
            [self confirmAutoDeleteSec:sec done:done];
        }];
    if ([self autoDeleteIsReadOnly]) {
        vc.onReadOnlyTap = ^{ [ws im_showToast:IMLocalized(@"autodel.group_admin_only")]; }; // 只读：不发 PUT
    }
    [self.navigationController pushViewController:vc animated:YES];
}

/// 开启 / 改档位：说明性确认框（v2 不追溯，确认后不会删任何历史消息，主按钮「开启」非 destructive；取消不改任何东西）。
- (void)confirmAutoDeleteSec:(int64_t)sec done:(void (^)(BOOL))done {
    NSString *messageKey = self.isGroup ? @"autodel.confirm.message_group" : @"autodel.confirm.message";
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:IMLocalized(@"autodel.confirm.title")
        message:IMLocalizedFormat(messageKey, IMAutoDeletePeriodWord(sec))
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.cancel") style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction *a) { done(NO); }]];
    __weak typeof(self) ws = self;
    [alert addAction:[UIAlertAction actionWithTitle:IMLocalized(@"autodel.confirm.action") style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
        __strong typeof(ws) self = ws;
        if (!self) { done(NO); return; }
        [self saveAutoDeleteSec:sec done:done];
    }]];
    [self.navigationController.topViewController presentViewController:alert animated:YES completion:nil];
}

/// 保存本会话档位：整体替换 PUT（其余字段原样回传，muteUntil 传 nil 让服务端保留未到期定时免打扰；只有这里带 auto_delete_sec）；
/// 成功后用回包 sec+from 落本机并立即清理（通常无事可清），失败 toast + 回滚（300204 = 无权限）。
- (void)saveAutoDeleteSec:(int64_t)sec done:(void (^)(BOOL))done {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { [self im_showToast:IMLocalized(@"autodel.save_failed")]; done(NO); return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService updateConversationSettingsWithToken:token convID:self.convID
        pinnedAt:self.pinnedAt muted:self.muted muteUntil:nil markedUnread:self.markedUnread autoDeleteSec:@(sec)
        completion:^(NSDictionary *data, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { done(NO); return; }
        if (error) {
            [self im_showToast:IMLocalized(error.code == 300204 ? @"autodel.group_admin_only" : @"autodel.save_failed")];
            done(NO); return;
        }
        [self adoptSavedAutoDeleteReply:data requestedSec:sec];
        [self reloadSettingsAndPills];
        done(YES);
    }];
}

/// PUT 回包带 sec+from 就直接采纳；回包缺字段（老服务端）时先按所选档位显示，并重拉设置取权威 from。
- (void)adoptSavedAutoDeleteReply:(NSDictionary *)data requestedSec:(int64_t)sec {
    if ([data[@"auto_delete_sec"] isKindOfClass:NSNumber.class] && [data[@"auto_delete_from"] isKindOfClass:NSNumber.class]) {
        [self adoptAutoDeleteConfig:IMAutoDeleteConfigFromJSON(data[@"auto_delete_sec"], data[@"auto_delete_from"])];
        return;
    }
    self.autoDeleteSec = sec;
    [self loadConversationSettings];
}

@end
