//  IMChatFolderLogic.h
//  会话文件夹的纯逻辑（无 self、可单测）：成员过滤、Tab 未读口径、左右滑判定。
//  三端同口径：im-android `data/ChatFolderLogic.kt`、im-web `src/chatFolders.ts`（设计 §3.3 / §4.3）。

#import <UIKit/UIKit.h>

@class IMConversation, IMChatFolder;

NS_ASSUME_NONNULL_BEGIN

/// 文件夹 Tab 的未读角标：count=0 不显示；muted=YES 表示主数值为 0、仅静音会话有未读（灰色，数值=静音会话未读之和）。
typedef struct {
    NSInteger count;
    BOOL muted;
} IMChatFolderBadge;

/// 横滑手势判定结果。
typedef NS_ENUM(NSInteger, IMChatFolderSwipeOutcome) {
    IMChatFolderSwipeOutcomeNone = 0,   ///< 不处理（保持各自原行为）
    IMChatFolderSwipeOutcomeNextTab,    ///< 切到下一个 Tab
    IMChatFolderSwipeOutcomePrevTab,    ///< 切到上一个 Tab
    IMChatFolderSwipeOutcomeRowSwipe,   ///< 交给行滑动（滑出按钮）
};

@interface IMChatFolderLogic : NSObject

/// 按会话顺序保序过滤出 folder 内的会话（folder=nil 即「全部」，原样返回）。
+ (NSArray<IMConversation *> *)conversations:(NSArray<IMConversation *> *)convs inFolder:(nullable IMChatFolder *)folder;

/// 某范围（folder=nil = 全部）的 Tab 角标。口径（设计 §3.3）：未读**消息条数**之和；
/// 静音会话不计入主数值（@我 仍计 1，同 IMTabUnreadCount）；手动「标为未读」计 1；只有静音会话有未读时灰显。
+ (IMChatFolderBadge)badgeForConversations:(NSArray<IMConversation *> *)convs
                                  inFolder:(nullable IMChatFolder *)folder nowMillis:(int64_t)now;

/// 尾部区域宽度 = min(行按钮组展开宽度, 列表宽 × 40%)。
+ (CGFloat)tailZoneWidthForListWidth:(CGFloat)listWidth actionsWidth:(CGFloat)actionsWidth;

/// 横滑判定（设计 §4.3 全表）。translationX<0 为向左滑。
/// startX：起手点在列表坐标系的 x；rowOpen：当前已有某行按钮展开。
+ (IMChatFolderSwipeOutcome)swipeOutcomeForTranslationX:(CGFloat)translationX
                                                 startX:(CGFloat)startX
                                              listWidth:(CGFloat)listWidth
                                           actionsWidth:(CGFloat)actionsWidth
                                                hasNext:(BOOL)hasNext hasPrev:(BOOL)hasPrev
                                                rowOpen:(BOOL)rowOpen;

/// 当前文件夹选择按 id 保持：列表数据换新后，选中的文件夹被删了就回到「全部」(-1)，否则返回它的新下标（0 起，
/// 不含「全部」）。selectedID=nil 表示「全部」。
+ (NSInteger)indexOfFolderID:(nullable NSString *)selectedID inFolders:(NSArray<IMChatFolder *> *)folders;

@end

NS_ASSUME_NONNULL_END
