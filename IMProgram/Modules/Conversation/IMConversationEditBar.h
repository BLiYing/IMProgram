//  IMConversationEditBar.h
//  会话列表编辑模式的底部选择栏：左「全选 / 取消全选」，右「已读」「删除」，均为文字钮（液态玻璃胶囊）。
//  设计 IMServer/docs/design/CONV_LIST_EDIT_MODE_DESIGN.md §3：**独立一条、不与列表重叠**——页面底色 + 顶 0.5 分隔线，
//  高 = 48 + 底部留白（内容区 48 固定；留白 = 窗口的底部安全区，由宿主经 bottomInset 给——
//  不跟页面安全区走：TabBar 隐藏动画期间页面安全区仍含 TabBar 高度，会让按钮行悬在半空）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 栏内内容区高度（同聊天多选栏 kIMSelectionBarH）。
extern const CGFloat kIMConversationEditBarContentHeight;

@interface IMConversationEditBar : UIView

@property (nonatomic, readonly) UIButton *selectAllButton;
@property (nonatomic, readonly) UIButton *readButton;
@property (nonatomic, readonly) UIButton *deleteButton;

/// 按钮行下方的留白（home 条高度）；宿主在进入编辑 / 安全区变化时更新。
@property (nonatomic) CGFloat bottomInset;

/// 按当前选择态刷新三个钮：全选钮文案、已读 / 删除可用性（不可用 35% 透明）。
- (void)updateAllSelected:(BOOL)allSelected canSelectAll:(BOOL)canSelectAll canRead:(BOOL)canRead canDelete:(BOOL)canDelete;

@end

NS_ASSUME_NONNULL_END
