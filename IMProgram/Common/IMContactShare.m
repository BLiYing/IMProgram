//  IMContactShare.m

#import "IMContactShare.h"
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
                  nickname:(NSString *)nickname
                 avatarURL:(NSString *)avatarURL {
    NSString *content = IMContactCardBuild(userID, nickname, avatarURL);
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (content.length == 0 || token.length == 0 || !host) { return; }
    __weak UIViewController *wsHost = host;
    IMForwardPickerViewController *picker = [[IMForwardPickerViewController alloc]
        initWithHost:IMHTTPService.sharedService.host token:token
              onDone:^(NSArray<IMConversation *> *selected) {
        if (selected.count == 0) { return; }
        for (IMConversation *c in selected) {
            [self sendContactContent:content selfUID:selfUID
                              toConv:c.convID toUser:(c.isGroup ? @"" : (c.peer ?: @""))];
        }
        // 这里**要**吐司：与入口 ① 不同，用户此刻不在目标会话里，看不到气泡这个天然反馈。
        [wsHost im_showToast:selected.count == 1 ? @"已发送"
                                                : [NSString stringWithFormat:@"已发送到 %lu 个会话", (unsigned long)selected.count]];
    }];
    [host presentViewController:[[UINavigationController alloc] initWithRootViewController:picker]
                       animated:YES completion:nil];
}

/// 发一条 contact + 乐观落库（口径同 IMFavoritesViewController.sendFavoriteContent:）。
/// 落库是必须的：用户此刻不在目标会话，不落库的话进那个会话前这条消息本机不存在
/// （服务端不回显自己发的消息），要等下次 sync 才补回来。
+ (void)sendContactContent:(NSString *)content selfUID:(NSString *)selfUID
                    toConv:(NSString *)convID toUser:(NSString *)toUser {
    IMDatabaseAccountContext *ctx = IMDatabase.sharedDatabase.currentAccountContext;
    if (!ctx) { return; }
    IMMessageModel *m = [IMMessageModel new];
    int64_t sentAt = (int64_t)([NSDate date].timeIntervalSince1970 * 1000);
    NSString *cmid = [IMSocketManager.sharedManager forwardContent:content contentType:IMContentTypeContact
                                                           toConv:convID toUser:toUser forwardFrom:@""
                                                         fileName:nil fileSize:0 attributes:nil
                                                       completion:^(BOOL success, NSError *error, int64_t convSeq) {
        m.status = success ? IMMessageStatusSent : IMMessageStatusFailed;
        m.convSeq = convSeq;
        [IMDatabase.sharedDatabase performWithAccountContext:ctx block:^(IMDatabase *db) { [db saveMessage:m]; }];
    }];
    m.clientMsgID = cmid; m.convID = convID; m.to = toUser; m.from = selfUID;
    m.content = content; m.contentType = IMContentTypeContact;
    m.status = IMMessageStatusSending; m.timestamp = sentAt;
    [IMDatabase.sharedDatabase performWithAccountContext:ctx block:^(IMDatabase *db) { [db saveMessage:m]; }];
}

@end
