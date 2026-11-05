//  IMContactShare.m

#import "IMContactShare.h"
#import "IMLocalization.h"
#import "IMContactCard.h"
#import "IMForwardPickerViewController.h"
#import "IMConversation.h"
#import "IMMessageModel.h"
#import "IMSocketManager.h"
#import "IMHTTPService.h"
#import "IMDatabase.h"
#import "UIViewController+IMToast.h"

@implementation IMContactShare

+ (void)presentPickerFrom:(UIViewController *)host
                   selfUID:(NSString *)selfUID
                    userID:(NSString *)userID
                  username:(nullable NSString *)username
                  nickname:(NSString *)nickname
                 avatarURL:(NSString *)avatarURL {
    NSString *content = IMContactCardBuild(userID, username, nickname, avatarURL);
    // 名片主人本人不作目标（分享自己的名片时 userID == selfUID，本就不在好友 / 单聊里，无副作用）。
    [self presentPickerFrom:host selfUID:selfUID content:content contentType:IMContentTypeContact
                    preview:IMContactCardPreview(content) excludedUserIDs:(userID.length ? [NSSet setWithObject:userID] : nil)
                excludedConvIDs:nil];
}

+ (void)presentGroupInvitePickerFrom:(UIViewController *)host selfUID:(NSString *)selfUID convID:(NSString *)convID
                           groupName:(NSString *)groupName link:(NSString *)link {
    if (link.length == 0) { return; }
    NSString *text = [self groupInviteTextWithGroupName:groupName link:link];
    [self presentPickerFrom:host selfUID:selfUID content:text contentType:@"text" preview:text excludedUserIDs:nil
                excludedConvIDs:(convID.length ? [NSSet setWithObject:convID] : nil)];
}

+ (NSString *)groupInviteTextWithGroupName:(NSString *)groupName link:(NSString *)link {
    NSString *name = [groupName stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *line = IMLocalizedFormat(@"share.group_invite.text", name.length > 0 ? name : IMLocalized(@"common.group_chat"));
    return [NSString stringWithFormat:@"%@\n%@", line, link ?: @""];
}

/// 名片与群邀请共用：选会话 → 逐个发 + 乐观落库 → 吐司。
+ (void)presentPickerFrom:(UIViewController *)host selfUID:(NSString *)selfUID content:(NSString *)content
              contentType:(NSString *)contentType preview:(NSString *)preview
          excludedUserIDs:(NSSet<NSString *> *)excludedUserIDs excludedConvIDs:(NSSet<NSString *> *)excludedConvIDs {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (content.length == 0 || token.length == 0 || !host) { return; }
    __weak UIViewController *wsHost = host;
    IMForwardPickerViewController *picker = [[IMForwardPickerViewController alloc]
        initWithHost:IMHTTPService.sharedService.host token:token
              onDone:^(NSArray<IMConversation *> *selected) {
        if (selected.count == 0) { return; }
        for (IMConversation *c in selected) {
            [self sendContent:content contentType:contentType selfUID:selfUID
                       toConv:c.convID toUser:(c.isGroup ? @"" : (c.peer ?: @""))];
        }
        // 这里**要**吐司：与入口 ① 不同，用户此刻不在目标会话里，看不到气泡这个天然反馈。
        [wsHost im_showToast:selected.count == 1 ? IMLocalized(@"common.sent")
                                                : IMLocalizedFormat(@"common.sent_to_chats", (long)selected.count)];
    }];
    picker.previewText = preview;
    picker.excludedUserIDs = excludedUserIDs;
    picker.excludedConvIDs = excludedConvIDs;
    picker.selfUID = selfUID; // 与发送时回显行的 from 同一来源，不再另取 socket 的 userID
    [host presentViewController:[[UINavigationController alloc] initWithRootViewController:picker]
                       animated:YES completion:nil];
}

/// 发一条消息 + 乐观落库（口径同 IMFavoritesViewController.sendFavoriteContent:）。
/// 落库是必须的：用户此刻不在目标会话，不落库的话进那个会话前这条消息本机不存在
/// （服务端不回显自己发的消息），要等下次 sync 才补回来。
+ (void)sendContent:(NSString *)content contentType:(NSString *)contentType selfUID:(NSString *)selfUID
             toConv:(NSString *)convID toUser:(NSString *)toUser {
    IMDatabaseAccountContext *ctx = IMDatabase.sharedDatabase.currentAccountContext;
    if (!ctx) { return; }
    IMMessageModel *m = [IMMessageModel new];
    int64_t sentAt = (int64_t)([NSDate date].timeIntervalSince1970 * 1000);
    NSString *cmid = [IMSocketManager.sharedManager forwardContent:content contentType:contentType
                                                           toConv:convID toUser:toUser forwardFrom:@""
                                                         fileName:nil fileSize:0 attributes:nil
                                                       completion:^(BOOL success, NSError *error, int64_t convSeq) {
        m.status = success ? IMMessageStatusSent : IMMessageStatusFailed;
        m.convSeq = convSeq;
        [IMDatabase.sharedDatabase performWithAccountContext:ctx block:^(IMDatabase *db) { [db saveMessage:m]; }];
    }];
    m.clientMsgID = cmid; m.convID = convID; m.to = toUser; m.from = selfUID;
    m.content = content; m.contentType = contentType;
    m.status = IMMessageStatusSending; m.timestamp = sentAt;
    [IMDatabase.sharedDatabase performWithAccountContext:ctx block:^(IMDatabase *db) { [db saveMessage:m]; }];
}

@end
