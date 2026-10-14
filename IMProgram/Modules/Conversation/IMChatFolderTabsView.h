//  IMChatFolderTabsView.h
//  会话列表顶部的文件夹 Tab 条：首位恒为「全部」，其后是各文件夹；每个 Tab 带未读消息总数角标。
//  复用 IMLiquidSegmentedControl（药丸选中、放不下横向滚动），本类只管数据映射与长按。
//  设计见 IMServer/docs/design/CHAT_FOLDERS_DESIGN.md §4.1–§4.2。

#import <UIKit/UIKit.h>

@class IMChatFolder, IMConversation;

NS_ASSUME_NONNULL_BEGIN

/// Tab 条自身高度：控件 40 + 下留白 6（上留白由搜索入口容器的 6pt 底部留白承担，上下相等）。
FOUNDATION_EXPORT const CGFloat kIMChatFolderTabsHeight;

@interface IMChatFolderTabsView : UIView

/// 用户点选某个 Tab（0 = 「全部」，i = 第 i 个文件夹）。
@property (nonatomic, copy, nullable) void (^onSelect)(NSInteger index);
/// 长按某个文件夹 Tab（「全部」不触发）：folderIndex 为 folders 下标；sourceRect 在本视图坐标系。
@property (nonatomic, copy, nullable) void (^onLongPressFolder)(NSInteger folderIndex, CGRect sourceRect);

/// 重绘：folders 为全部文件夹；convs 为全部会话（算角标）；selectedIndex 0 = 全部。
- (void)configureWithFolders:(NSArray<IMChatFolder *> *)folders
               conversations:(NSArray<IMConversation *> *)convs
               selectedIndex:(NSInteger)selectedIndex;

- (void)setSelectedIndex:(NSInteger)index animated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
