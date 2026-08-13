//  IMChatViewController.h
//  聊天页：连上 IMSocketManager 收发文本。单聊（peerID）与群聊（群 convID）共用一页，
//  群聊差异：标题=群名（N人）、右上 ⓘ 进群资料、对方气泡带发送者昵称、发送按 conv_id 路由。

#import <UIKit/UIKit.h>

@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

/// 会话历史被清空（资料页「清空聊天记录」）→ 聊天页据此清空内存并刷新。userInfo[kIMConvIDKey]=会话 id。
extern NSNotificationName const IMChatConversationClearedNotification;

@interface IMChatViewController : UIViewController

/// host 形如 "localhost:8080"；userID 我方 uid；peerID 对方 uid。
/// readSeq：进入前的已读位点（定位未读分割线 + 可见即读的起点，首条未读=conv_seq>readSeq）；unread：进入时未读数；
/// peerReadSeq：对端已读位点（进会话即据此显示"我发的"已读双勾，避免对方早前已读、本端没收到实时回执时漏显）。
- (instancetype)initWithHost:(NSString *)host
                      userID:(NSString *)userID
                      peerID:(NSString *)peerID
                     readSeq:(int64_t)readSeq
                      unread:(NSInteger)unread
                 peerReadSeq:(int64_t)peerReadSeq NS_DESIGNATED_INITIALIZER;

/// 群聊入口：convID=群 topic_id（g_xxx），name=群名（可空，进入后拉群资料刷新）。
/// readSeq/unread 语义同上。groupReadSeq=群「全员已读位点」min(其他成员已读位点)，用于
/// 「全员都读过→我发的消息显绿✓✓」；非实时（随会话列表快照播种，无来源时传 0）。
- (instancetype)initWithHost:(NSString *)host
                      userID:(NSString *)userID
                 groupConvID:(NSString *)convID
                   groupName:(nullable NSString *)name
                     readSeq:(int64_t)readSeq
                      unread:(NSInteger)unread
                groupReadSeq:(int64_t)groupReadSeq;

/// 单聊对端资料（会话列表进入时透传，供右上信息按钮打开的资料页显示昵称/头像；可空回退 uid）。群聊忽略。
@property (nonatomic, copy, nullable) NSString *peerNickname;
@property (nonatomic, copy, nullable) NSString *peerAvatarURL;

/// 群头像（会话列表进入时透传，供右上头像按钮**立即显真头像、免闪首字母**；空则回退首字母，进入后 reloadGroupInfo 补正）。
@property (nonatomic, copy, nullable) NSString *groupAvatarURL;

/// 供统一自定义导航栏读取群聊副标题（成员人数）；不改变聊天业务状态。
- (BOOL)im_isGroupChat;
- (nullable NSString *)im_navigationSubtitle;

/// 本会话 id（单聊=IMConversationID(uid,peer)，群聊=群 topic_id）。供详情页在导航栈里反查本聊天页。
@property (nonatomic, copy, readonly) NSString *convID;

/// 转发一条消息：present 转发选择页并把选中的会话逐一回声。**presenter** 是实际弹出选择页的 VC
/// （详情页文件列表复用本逻辑时传自己，保证呈现上下文正确、toast 落在可见页）。
- (void)presentForwardPickerForMessage:(IMMessageModel *)message fromViewController:(UIViewController *)presenter;

/// 定位到本会话某条消息：滚到该 conv_seq 行并高亮一闪。详情页「定位到聊天」pop 回本页后调用。
- (void)jumpToConvSeq:(int64_t)convSeq;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
