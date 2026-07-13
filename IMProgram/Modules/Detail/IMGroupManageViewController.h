//  IMGroupManageViewController.h
//  群管理二级页（仅群主/管理员可进）。当前后端已支持项：修改群名 / 设置群头像。
//  （进群确认、全员禁言、群公告待后端字段落地后再加，见 docs/TASKS。）
//  改动成功经群事件 / 重拉群资料回流到上一页与聊天页。

#import <UIKit/UIKit.h>

@class IMGroupInfo;

NS_ASSUME_NONNULL_BEGIN

@interface IMGroupManageViewController : UIViewController

/// group：当前群资料快照（用于回填群名/头像与权限判断）。onChanged：改名/改头像成功后回调（上一页据此刷新）。
- (instancetype)initWithHost:(NSString *)host
                      userID:(NSString *)userID
                      convID:(NSString *)convID
                       group:(IMGroupInfo *)group
                   onChanged:(nullable void (^)(void))onChanged;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
