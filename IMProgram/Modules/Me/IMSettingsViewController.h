//  IMSettingsViewController.h
//  "我"页：当前 uid + 编辑资料入口 + 退出登录。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMSettingsViewController : UIViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID;

/// 本页非破坏性行的 id（不含「退出登录」）。设置项搜索登记表（IMSettingsSearchRegistry）与它的对账用（单测）。
- (NSArray<NSString *> *)nonDestructiveRowIDs;
/// 触发某一级行的动作（等同点击）。设置项搜索命中**纯动作行**（分享我的名片，不 push 页面）时用；未知 id / 破坏性行返回 NO。
- (BOOL)performEntryWithID:(NSString *)rowId;

@end

NS_ASSUME_NONNULL_END
