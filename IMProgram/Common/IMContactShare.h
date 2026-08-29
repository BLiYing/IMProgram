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
                  nickname:(nullable NSString *)nickname
                 avatarURL:(nullable NSString *)avatarURL;

@end

NS_ASSUME_NONNULL_END
