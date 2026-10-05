//  IMSettingsViewController.h
//  "我"页：当前 uid + 编辑资料入口 + 退出登录。

#import <UIKit/UIKit.h>
#import "IMScopedSearch.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMSettingsViewController : UIViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID;

/// 底部搜索 tab（「我」范围）的数据源：本页各设置项（标题=当前语言），不含「退出登录」。
- (NSArray<IMSettingsSearchEntry *> *)searchEntries;
/// 命中后跳转：等同点击该行（rowId 取自 searchEntries）。未知 id 返回 NO。
- (BOOL)performEntryWithID:(NSString *)rowId;

@end

NS_ASSUME_NONNULL_END
