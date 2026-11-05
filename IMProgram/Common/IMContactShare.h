//  IMContactShare.h
//  「把一张个人名片发到若干会话」的共享入口（设计文档 §4.3 / §4.4 的入口 ② ③）。
//
//  入口 ② 好友资料页「推荐给朋友」、入口 ③「我」页「分享我的名片」都是同一件事：
//  选会话（**复用**已有的 IMForwardPickerViewController）→ 对每个选中会话发一条 contact。
//  收敛在这里，是因为两个入口分处 Detail / Me 两个模块，各写一遍必然漂移（且都要正确做乐观落库）。
//
//  与聊天页入口 ① 的分工：① 在会话内选**人**（+Contact.m，带卡片式二次确认）；
//  ②③ 在会话外选**会话**（本文件，无二次确认——转发选择页本身就是确认步骤，与转发一致）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMContactShare : NSObject

/// 弹出会话选择页，把 uid/nickname/avatarURL 组成的名片发到选中的每个会话。
/// ⚠️ nickname 必须传**真实昵称**，不能传 displayName（备注不得外发，见 IMContactCard.h）。
/// selfUID：当前登录用户内部 ID（乐观回显行的 from）。host/token 为空或 uid 为空则静默不做。
+ (void)presentPickerFrom:(UIViewController *)host
                   selfUID:(NSString *)selfUID
                    userID:(NSString *)userID
                  username:(nullable NSString *)username
                  nickname:(nullable NSString *)nickname
                 avatarURL:(nullable NSString *)avatarURL;

/// 群二维码 / 群邀请链接页「分享 → 发送给朋友」（SHARE_PICKER_UX_SKETCH ⑤）：选会话 → 每个会话发一条
/// **文本**「邀请你加入群聊「群名」\n<链接>」。链接是 /q/g/<token>，收端在聊天里点开走 App 内的入群预览
/// （IMChatViewController+MediaFlow 的「层3：本站邀请链接」拦截），无需新消息类型。link 为空静默不做。
+ (void)presentGroupInvitePickerFrom:(UIViewController *)host
                             selfUID:(NSString *)selfUID
                              convID:(nullable NSString *)convID
                           groupName:(nullable NSString *)groupName
                                link:(NSString *)link;

/// 群邀请文本（纯函数，可测）：首行邀请语（群名为空用「群聊」），次行链接。
+ (NSString *)groupInviteTextWithGroupName:(nullable NSString *)groupName link:(NSString *)link;

@end

NS_ASSUME_NONNULL_END
