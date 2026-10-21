//  IMConversationSelection.h
//  会话列表「编辑模式」的选择集（纯逻辑、无 UIKit、可单测）。
//  设计 IMServer/docs/design/CONV_LIST_EDIT_MODE_DESIGN.md §2：按会话 ID 记录，切 Tab 清空，
//  全选只管当前列表；三端同口径：im-android `data/ConversationSelection.kt`、im-web `src/convSelection.ts`。

#import <Foundation/Foundation.h>

@class IMConversation;

NS_ASSUME_NONNULL_BEGIN

@interface IMConversationSelection : NSObject

@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly) NSSet<NSString *> *selectedIDs;

/// 会话是否「有未读」：未读数 > 0 或手动标为未读。「已读」按钮的可用判据与单条「设为已读」菜单同一口径。
+ (BOOL)conversationHasUnread:(IMConversation *)conversation;

- (BOOL)isSelected:(NSString *)convID;
/// 勾选 / 取消；返回操作后是否为选中。
- (BOOL)toggle:(NSString *)convID;
- (void)select:(NSString *)convID;
- (void)deselect:(NSString *)convID;
- (void)clear;

/// 选中 list 内全部会话（保留 list 之外已选的项）。
- (void)selectAllIn:(NSArray<IMConversation *> *)list;
/// list 非空且其中每一项都已选中。
- (BOOL)isAllSelectedIn:(NSArray<IMConversation *> *)list;
/// 只保留仍存在于 list 的 ID（他端删除 / 退群 / 切范围后剔除）。返回是否有变化。
- (BOOL)pruneToExistingIn:(NSArray<IMConversation *> *)list;
/// 选中项里至少有一项有未读（「已读」按钮可用）。
- (BOOL)hasUnreadIn:(NSArray<IMConversation *> *)list;
/// 按 list 顺序取出已选会话。
- (NSArray<IMConversation *> *)selectedConversationsIn:(NSArray<IMConversation *> *)list;

@end

NS_ASSUME_NONNULL_END
