//  IMChatDetailViewController.h
//  会话详情页（单聊 / 群聊共用一套骨架，仿 Telegram 视觉 + 微信浅层管理）。
//  从聊天页右上信息按钮 / 点标题进入。特性：
//   · 滚动驱动头像形变（有头像：方→圆→水滴吸附灵动岛；无群头像：圆默认态直接吸附）+ 锚点触感；
//   · 操作排 静音 / 搜索 / 更多（更多按端定制、红项二次确认）；
//   · 置顶 / 免打扰开关（接 M4.5 会话设置，conv_update 多端同步）；
//   · 分类页签**按会话内实际消息类型动态生成**（群聊「成员」恒第一），tap 切换；
//   · 群聊：成员页签管理（设/撤管理员、转让、移除、邀请）+ 群管理二级页（改名 / 设群头像）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMChatDetailViewController : UIViewController

/// 单聊详情。peerNickname/peerAvatarURL 由会话列表透传（可空→回退 uid 首字母圈）。
- (instancetype)initSingleWithHost:(NSString *)host
                            userID:(NSString *)userID
                            peerID:(NSString *)peerID
                      peerNickname:(nullable NSString *)peerNickname
                     peerAvatarURL:(nullable NSString *)peerAvatarURL;

/// 群聊详情。convID=群 topic_id（g_xxx）；groupName/groupAvatarURL 由聊天页透传（避免头像加载前闪回退圈）；
/// 成员等其余进入后拉群资料填充。
- (instancetype)initGroupWithHost:(NSString *)host
                           userID:(NSString *)userID
                          convID:(NSString *)convID
                       groupName:(nullable NSString *)groupName
                  groupAvatarURL:(nullable NSString *)groupAvatarURL;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)n bundle:(nullable NSBundle *)b NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)c NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
