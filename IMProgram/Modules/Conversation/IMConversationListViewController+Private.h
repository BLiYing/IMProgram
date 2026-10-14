//  IMConversationListViewController+Private.h
//  会话列表的共享类扩展（属性）与跨文件私有方法登记：主文件 + `+Folders.m`（聊天文件夹）共用。
//  存储属性只放类扩展 `()`，别放进 category（CODING_STYLE §3）；category 段只放方法声明。

#import "IMConversationListViewController.h"
#import "IMSocketManager.h"

@class IMDatabaseAccountContext, IMConversation, IMChatFolder, IMChatFolderTabsView, IMMenuAction;

NS_ASSUME_NONNULL_BEGIN

@interface IMConversationListViewController () <UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy) NSString *token;
@property (nonatomic, strong) IMDatabaseAccountContext *databaseContext;
@property (nonatomic, strong) NSArray<IMConversation *> *conversations;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
/// 本次登录后拉成过一次服务端会话列表。**空态是结论**：新装包首登时本地缓存必空，只凭缓存就会先闪
/// 「还没有会话」再改口（Android 同一个洞，2026-09-15 用户报；对端判据 im-android `ConversationListPhase`）。
@property (nonatomic, assign) BOOL serverListed;
/// 常驻订阅的 block token（见 startTabDotObservers）。**必须是 block token、不能 addObserver:self**：
/// viewWillDisappear 按 name 摘 self 的订阅，会连这组一起摘掉。
@property (nonatomic, copy) NSArray<id<NSObject>> *tabDotObservers;
@property (nonatomic, assign) BOOL offscreenRefreshPending;
@property (nonatomic, assign) BOOL visible; // 在屏时才响应新消息刷新（避免进聊天页时无谓拉取）
@property (nonatomic, strong) NSMutableSet<NSString *> *trackedConvIDs; // 已登记增量同步的会话（每会话只登记一次）
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *outboxStates; // conv → 0无/1发送中/2失败（去抖用）
@property (nonatomic, assign) IMSocketState connState; // 连接态（走副标题，同聊天页「在线」位置）
// —— 聊天文件夹（设计 §4.1 / §4.3）：当前 Tab 选中某文件夹时，表格只显示它的会话；「全部」时与 conversations 同一对象。
@property (nonatomic, copy, nullable) NSString *selectedFolderID;          // nil = 「全部」
@property (nonatomic, strong) NSArray<IMConversation *> *displayedConversations; // 表格数据源（所有按 row 取会话处都读它）
@property (nonatomic, strong) IMChatFolderTabsView *folderTabs;
@property (nonatomic, strong) UIView *searchContainer;                     // 固定的搜索入口（不随列表滚动）
@property (nonatomic, strong) UIPanGestureRecognizer *folderPan;           // 横滑切 Tab（IMFolderSwipePanRecognizer，起点见 folderSwipeStartX）
@property (nonatomic, assign) BOOL folderHeaderShown;                       // 表格当前是否带 Tab 条 section header
@property (nonatomic, assign) BOOL rowSwipeOpen;                           // 某行的滑动按钮已展开
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSValue *> *folderScrollOffsets; // Tab → 滚动位置
@end

/// 主文件里实现、`+Folders.m` 要调用的内部方法。
@interface IMConversationListViewController (Internal)
- (void)rebuildDisplayedConversations;
- (nullable IMChatFolder *)selectedFolder;
- (void)refreshListIndicators;
- (void)refreshVisibleRowsOrReload;
- (NSArray<IMMenuAction *> *)conversationActionsFor:(IMConversation *)c;
- (void)reload;
@end

/// `+Folders.m` 实现、主文件要调用的方法（聊天文件夹，设计 CHAT_FOLDERS_DESIGN.md §4）。
@interface IMConversationListViewController (Folders)
- (void)setUpFolderTabs;
- (void)refreshFolderTabs;
- (void)onFoldersChanged;
- (CGFloat)folderSwipeStartX;
- (BOOL)leftSwipeBelongsToTabsAtStartX:(CGFloat)startX;
- (NSArray<IMMenuAction *> *)folderMenuActionsFor:(IMConversation *)c;
@end

NS_ASSUME_NONNULL_END
