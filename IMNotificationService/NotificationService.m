//  NotificationService.m
//  通知扩展：给离线推送加上发送人头像（M5，IMServer/docs/design/PUSH_M5_DESIGN.md §3.6）。
//
//  服务端每条消息推送都带 `mutable-content: 1` 和发送人资料（sender_id / sender_name / sender_avatar，
//  群聊另有 group_avatar / bare_body）。系统先把通知交给这里：下载头像 → 组一个 INSendMessageIntent
//  → 用它把通知改成「通信通知」样式（左边是发送人头像，App 图标缩到右下角），同 iMessage / WhatsApp。
//
//  头像先查缓存（IMPushAvatarCache，按内容寻址的地址存，换头像自动换）；没命中才下载。下载失败
//  （手机连不上 IM 服务器——开发期服务器在局域网，手机锁屏切到蜂窝时最常见）退回这个人 / 群
//  「最近一次的头像」。还是没有（没设头像，或新人头一回发消息、缓存里没有又下载不到）就画 App 内
//  同款首字母头像——通信通知没图时系统会退回 App 图标，看不出是谁。
//
//  **群聊通知固定显示群头像（2026-10-02 改），不管谁发的消息**：同 App 内会话列表（群头像 /
//  群首字母圈，与发消息的人是谁无关），也同主流 IM。之前「群没设群头像时退回发送人头像」会导致
//  同一个群的通知忽而显示这个人、忽而显示那个人，像是来自不同的群；且群聊干脆不下载发送人头像，
//  省一次网络请求。私聊仍是对方头像 → 对方最近一次的头像 → 对方首字母头像。
//  任何一步失败都退回原样展示——头像是锦上添花，绝不能让通知因此丢掉或晚到。系统给扩展约 30 秒，
//  超时会调 serviceExtensionTimeWillExpire，同样原样交出。
//
//  日志：扩展不链接 Pods，用不了 IMLog（IMServer/docs/LOGGING.md 的 iOS 统一入口），只能用 os_log。

#import <UserNotifications/UserNotifications.h>
#import <Intents/Intents.h>
#import <os/log.h>
#import "IMPushSender.h"
#import "IMPushAvatarCache.h"
#import "IMAvatarPlaceholder.h"

/// 取头像（两张并行）的总时限：头像 ≤256px、几十 KB，连得上时远够；连不上时宁可用旧头像也别拖住通知。
static const NSTimeInterval kIMAvatarDeadline = 3;
/// 通话提醒（PUSH_M5_DESIGN §3.8）等头像的上限：来电横幅晚一秒就是少响一秒，到点没取到就用首字母头像，
/// 照样是带头像的通信通知样式（不退回 App 图标）。头像多半已在缓存里（对方给你发过消息），命中是即时的。
static const NSTimeInterval kIMCallAvatarDeadline = 1;
/// 首字母占位头像的边长（像素），与服务端头像同档。
static const CGFloat kIMPlaceholderSide = 256;

@interface NotificationService : UNNotificationServiceExtension
@property (nonatomic, copy) void (^contentHandler)(UNNotificationContent *content);
@property (nonatomic, strong) UNMutableNotificationContent *original;
@end

@implementation NotificationService

static os_log_t IMExtLog(void) {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ log = os_log_create("com.libeyond.IMProgram.NotificationService", "push"); });
    return log;
}

- (void)didReceiveNotificationRequest:(UNNotificationRequest *)request
                   withContentHandler:(void (^)(UNNotificationContent *))contentHandler {
    self.contentHandler = contentHandler;
    self.original = [request.content mutableCopy];
    // 通话提醒也改成带对方头像的通信通知（同消息推送），只是等头像的上限短得多（kIMCallAvatarDeadline）。
    id callID = request.content.userInfo[@"call_id"];
    BOOL isCall = [callID isKindOfClass:NSString.class] && [(NSString *)callID length] > 0;
    NSTimeInterval deadline = isCall ? kIMCallAvatarDeadline : kIMAvatarDeadline;
    IMPushSender *sender = [IMPushSender senderFromUserInfo:request.content.userInfo];
    if (sender == nil) {
        [self finishWith:self.original];
        return;
    }
    [IMPushAvatarCache.shared evictIfNeeded];

    // 群聊只取群头像；私聊只取对方头像——不是对方发的群消息，不该拿它的头像顶群的位置。
    // 两张头像从不同时取（本来也是互斥的），到点还没回来的当没有。
    NSLock *lock = [NSLock new];
    __block NSData *avatar = nil, *groupAvatar = nil;
    dispatch_group_t group = dispatch_group_create();
    if (sender.isGroup) {
        dispatch_group_enter(group);
        [self loadAvatarAtPath:sender.groupAvatarPath owner:[@"g:" stringByAppendingString:sender.convID] completion:^(NSData *data) {
            [lock lock]; groupAvatar = data; [lock unlock];
            dispatch_group_leave(group);
        }];
    } else {
        dispatch_group_enter(group);
        [self loadAvatarAtPath:sender.avatarPath owner:[@"u:" stringByAppendingString:sender.senderID] completion:^(NSData *data) {
            [lock lock]; avatar = data; [lock unlock];
            dispatch_group_leave(group);
        }];
    }
    __weak typeof(self) weakSelf = self;
    __block BOOL done = NO;
    void (^finish)(void) = ^{
        [lock lock];
        BOOL first = !done;
        done = YES;
        NSData *a = avatar, *g = groupAvatar;
        [lock unlock];
        if (!first) { return; }
        NSString *groupTitle = weakSelf.original.title;
        // 都没有（没设头像 / 新人头一回、没缓存又下载不到）：画 App 内同款首字母头像，别让系统退回 App 图标
        BOOL senderPlaceholder = !sender.isGroup && a == nil, groupPlaceholder = sender.isGroup && g == nil;
        if (senderPlaceholder) { a = IMAvatarPlaceholderPNG(sender.senderName, sender.senderID, kIMPlaceholderSide); }
        if (groupPlaceholder) { g = IMAvatarPlaceholderPNG(groupTitle, sender.convID, kIMPlaceholderSide); }
        if (senderPlaceholder || groupPlaceholder) {
            os_log(IMExtLog(), "push_avatar_placeholder sender=%d group=%d", senderPlaceholder, groupPlaceholder);
        }
        [weakSelf finishWithSender:sender
                            avatar:a ? [INImage imageWithImageData:a] : nil
                        groupImage:(sender.isGroup && g) ? [INImage imageWithImageData:g] : nil];
    };
    dispatch_group_notify(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), finish);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(deadline * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), finish);
}

- (void)serviceExtensionTimeWillExpire {
    [self finishWith:self.original];
}

/// 取一张头像：缓存 → 下载（成功即入缓存并记为 owner 最近一次的头像）→ 失败退回 owner 最近一次的头像。
/// path 为空表示此人 / 此群现在没有头像，不退回旧的（那是对方主动删掉的）。
- (void)loadAvatarAtPath:(NSString *)path owner:(NSString *)owner completion:(void (^)(NSData *_Nullable data))completion {
    if (path.length == 0) {
        completion(nil);
        return;
    }
    IMPushAvatarCache *cache = IMPushAvatarCache.shared;
    NSData *cached = [cache dataForAvatarPath:path];
    if (cached != nil) {
        completion(cached);
        return;
    }
    NSURL *url = IMPushSharedAvatarURL(path);
    if (url == nil) {
        completion([cache lastKnownDataForOwner:owner]);
        return;
    }
    NSURLSessionConfiguration *cfg = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    cfg.timeoutIntervalForRequest = kIMAvatarDeadline;
    cfg.timeoutIntervalForResource = kIMAvatarDeadline;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    [[session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        if (error != nil || status != 200 || data.length == 0) {
            NSData *fallback = [cache lastKnownDataForOwner:owner];
            os_log_error(IMExtLog(), "push_avatar_load_failed status=%ld code=%ld fallback=%d",
                         (long)status, (long)error.code, fallback != nil);
            completion(fallback);
            return;
        }
        [cache storeData:data forAvatarPath:path owner:owner];
        completion(data);
    }] resume];
    [session finishTasksAndInvalidate];
}

- (void)finishWithSender:(IMPushSender *)sender avatar:(INImage *)avatar groupImage:(INImage *)groupImage {
    INPersonHandle *handle = [[INPersonHandle alloc] initWithValue:sender.senderID type:INPersonHandleTypeUnknown];
    INPerson *person = [[INPerson alloc] initWithPersonHandle:handle nameComponents:nil displayName:sender.senderName
                                                        image:avatar contactIdentifier:nil
                                             customIdentifier:sender.senderID];
    INSpeakableString *groupName = nil;
    NSArray<INPerson *> *recipients = nil;
    if (sender.isGroup) {
        groupName = [[INSpeakableString alloc] initWithSpokenPhrase:self.original.title];
        // 群聊要有「我」以外的收件人系统才按群展示；收件人的具体身份通知里不显示，占位即可。
        INPerson *me = [[INPerson alloc] initWithPersonHandle:[[INPersonHandle alloc] initWithValue:@"me" type:INPersonHandleTypeUnknown]
                                               nameComponents:nil displayName:nil image:nil
                                            contactIdentifier:nil customIdentifier:nil isMe:YES];
        INPerson *other = [[INPerson alloc] initWithPersonHandle:[[INPersonHandle alloc] initWithValue:sender.convID type:INPersonHandleTypeUnknown]
                                                  nameComponents:nil displayName:self.original.title image:nil
                                               contactIdentifier:nil customIdentifier:nil];
        recipients = @[ me, other ];
    }
    INSendMessageIntent *intent = [[INSendMessageIntent alloc] initWithRecipients:recipients
                                                              outgoingMessageType:INOutgoingMessageTypeOutgoingMessageText
                                                                          content:self.original.body
                                                               speakableGroupName:groupName
                                                           conversationIdentifier:sender.convID
                                                                      serviceName:nil
                                                                           sender:person
                                                                      attachments:nil];
    if (groupImage != nil) {
        [intent setImage:groupImage forParameterNamed:@"speakableGroupName"];
    }
    INInteraction *interaction = [[INInteraction alloc] initWithIntent:intent response:nil];
    interaction.direction = INInteractionDirectionIncoming;
    __weak typeof(self) weakSelf = self;
    [interaction donateInteractionWithCompletion:^(NSError *donateError) {
        if (donateError != nil) {
            os_log_error(IMExtLog(), "push_intent_donate_failed error=%{public}@", donateError.localizedDescription);
        }
        UNMutableNotificationContent *base = [weakSelf.original mutableCopy];
        if (sender.isGroup && sender.bareBody.length > 0) {
            base.body = sender.bareBody; // 通信通知单独显示发送人，正文不再带「名字: 」
        }
        NSError *updateError = nil;
        UNNotificationContent *updated = [base contentByUpdatingWithProvider:intent error:&updateError];
        if (updated == nil) {
            os_log_error(IMExtLog(), "push_communication_update_failed error=%{public}@", updateError.localizedDescription ?: @"");
        }
        [weakSelf finishWith:updated ?: weakSelf.original];
    }];
}

- (void)finishWith:(UNNotificationContent *)content {
    void (^handler)(UNNotificationContent *) = nil;
    @synchronized (self) { // 只交一次：超时回调与下载完成在不同线程，可能先后到
        handler = self.contentHandler;
        self.contentHandler = nil;
    }
    if (handler) { handler(content); }
}

@end
