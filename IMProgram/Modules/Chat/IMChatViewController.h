//  IMChatViewController.h
//  聊天页：连上 IMSocketManager 收发文本。单聊（peerID）与群聊（群 convID）共用一页，
//  群聊差异：标题=群名（N人）、右上 ⓘ 进群资料、对方气泡带发送者昵称、发送按 conv_id 路由。

#import <UIKit/UIKit.h>

@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

/// 会话历史被清空（资料页「清空聊天记录」）→ 聊天页据此清空内存并刷新。userInfo[kIMConvIDKey]=会话 id。
extern NSNotificationName const IMChatConversationClearedNotification;

@interface IMChatViewController : UIViewController

/// 统一「进会话」入口（对标 Telegram navigateToChatController 的 useExisting + 折叠中间聊天页）：
/// - 同会话已在本栈：popToViewController 复用（中间页出栈），并刷新其显示身份 / 从库合并被压期间
///   错过的消息 / 重锚到底部（修复旧实例陈旧空洞与死播种）。
/// - 不同会话：**折叠**——截掉栈里最底部的聊天页及其之上的所有页（资料页等），把新会话接到它原来的
///   位置。于是「群聊A→成员资料→发消息C」返回时直达会话列表，而非退回 A（Telegram 行为）；
///   也保证**同一导航栈内至多一个聊天页**。
/// 说明：去重/折叠只作用于**单个** UINavigationController；各 Tab 有独立栈，跨 Tab 仍可能各存一个同会话
/// 实例（数据不丢：被压实例在 viewWillAppear 按 synced 游标从库合并自愈）。
/// **所有进聊天页的调用点一律走这里，禁止直接 alloc+push**（指定初始化器已收进 .m 类扩展，外部无法直接构造）。
/// 返回实际落位的聊天页（nav 为空返回 nil）。
+ (nullable instancetype)openInNavigationController:(nullable UINavigationController *)nav
                                               host:(NSString *)host
                                             userID:(NSString *)userID
                                             peerID:(NSString *)peerID
                                            readSeq:(int64_t)readSeq
                                             unread:(NSInteger)unread
                                        peerReadSeq:(int64_t)peerReadSeq
                                       peerNickname:(nullable NSString *)peerNickname
                                      peerAvatarURL:(nullable NSString *)peerAvatarURL;

/// 群聊版统一入口，语义同上。
+ (nullable instancetype)openInNavigationController:(nullable UINavigationController *)nav
                                               host:(NSString *)host
                                             userID:(NSString *)userID
                                        groupConvID:(NSString *)convID
                                          groupName:(nullable NSString *)name
                                            readSeq:(int64_t)readSeq
                                             unread:(NSInteger)unread
                                       groupReadSeq:(int64_t)groupReadSeq
                                     groupAvatarURL:(nullable NSString *)groupAvatarURL;

/// 在导航栈里反查承载 convID 的聊天页（自栈顶逆序，取最靠上的匹配）。详情页转发/定位复用它，
/// 与统一入口共用同一份查找口径，避免各处自行遍历导致方向不一致。
+ (nullable instancetype)existingChatForConvID:(NSString *)convID
                        inNavigationController:(nullable UINavigationController *)nav;

/// 单聊对端资料（会话列表进入时透传，供右上信息按钮打开的资料页显示昵称/头像；可空回退 uid）。群聊忽略。
@property (nonatomic, copy, nullable) NSString *peerNickname;
@property (nonatomic, copy, nullable) NSString *peerAvatarURL;

/// 群头像（会话列表进入时透传，供右上头像按钮**立即显真头像、免闪首字母**；空则回退首字母，进入后 reloadGroupInfo 补正）。
@property (nonatomic, copy, nullable) NSString *groupAvatarURL;

/// 本会话 id（单聊=IMConversationID(uid,peer)，群聊=群 topic_id）。供详情页在导航栈里反查本聊天页。
@property (nonatomic, copy, readonly) NSString *convID;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

// 以下公开方法实现在分文件 category（非主 @implementation）。声明放在对应 category 接口而非主 @interface，
// 主实现 TU 才不会报「方法未实现 / category 抢实现主类方法」——外部调用方 import 本头即可见，行为不变。

/// 统一自定义导航栏读取的展示能力（实现在 +Socket.m）：群聊判定 + 副标题（在线态/连接态/成员数/输入中）。
@interface IMChatViewController (NavigationBar)
- (BOOL)im_isGroupChat;
- (nullable NSString *)im_navigationSubtitle;
@end

/// 消息路由入口（实现在 +MediaFlow.m），详情页/媒体库复用：
@interface IMChatViewController (Routing)
/// 转发一条消息：present 转发选择页并把选中的会话逐一回声。**presenter** 是实际弹出选择页的 VC
/// （详情页文件列表复用本逻辑时传自己，保证呈现上下文正确、toast 落在可见页）。
- (void)presentForwardPickerForMessage:(IMMessageModel *)message fromViewController:(UIViewController *)presenter;
/// 定位到本会话某条消息：滚到该 conv_seq 行并高亮一闪。详情页「定位到聊天」pop 回本页后调用。
- (void)jumpToConvSeq:(int64_t)convSeq;
@end

NS_ASSUME_NONNULL_END
