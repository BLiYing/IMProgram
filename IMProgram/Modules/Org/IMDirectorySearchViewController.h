//  IMDirectorySearchViewController.h
//  集团内搜成员（交互稿 I-9）：GET /directory/search?q=，300ms 防抖，1–32 字；副标题 = 「单位 · 部门」。
//  范围由服务端按身份裁剪（客户只搜到所绑子公司的客服）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMDirectorySearchViewController : UIViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

/// 纯函数（单测）：输入框原文 → 要发的查询；空白或超长（> 32 字）返回 nil（不发请求）。
FOUNDATION_EXPORT NSString *_Nullable IMDirectorySearchQuery(NSString *_Nullable raw);

NS_ASSUME_NONNULL_END
