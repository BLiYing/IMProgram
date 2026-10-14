//  IMChatFolderEditViewController.h
//  聊天文件夹的创建 / 编辑页（设计 §4.6）：名称 + 已添加的聊天（左滑移除）+「添加聊天」+ 删除。
//  创建模式（folderID=nil）：右上「创建」一次性提交；编辑模式：名称失焦即存，成员增删立即提交。
//  普通 UIViewController + UITableView（push 页别用 UITableViewController：液态标题栏会下移，CODING_STYLE §9）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMChatFolderEditViewController : UIViewController

/// folderID 为 nil = 创建；非 nil = 编辑该文件夹。host/token/userID 用于拉会话列表（选择器数据源）。
- (instancetype)initWithFolderID:(nullable NSString *)folderID
                            host:(nullable NSString *)host
                           token:(nullable NSString *)token
                          userID:(nullable NSString *)userID NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nib bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

/// 创建模式的预填名称（推荐文件夹用）。
@property (nonatomic, copy, nullable) NSString *initialName;

@end

NS_ASSUME_NONNULL_END
