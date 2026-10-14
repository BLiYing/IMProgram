//  IMChatFoldersViewController.h
//  「我」→ 聊天文件夹 管理页（设计 §4.5）：文件夹列表（拖动排序、左滑删除）+「创建新文件夹」；
//  空态给「推荐文件夹」名称建议（点一下以该名称进创建页）。普通 UIViewController + 手放 UITableView。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMChatFoldersViewController : UIViewController

- (instancetype)initWithHost:(nullable NSString *)host userID:(nullable NSString *)userID NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nib bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
