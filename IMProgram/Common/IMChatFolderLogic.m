//  IMChatFolderLogic.m

#import "IMChatFolderLogic.h"
#import "IMConversation.h"
#import "IMChatFolder.h"
#import "IMMuteState.h"

/// 尾部区域占列表宽度的上限（按钮最多 4 个，展开几乎占满整行，须保留可用于切 Tab 的区域）。
static CGFloat const kTailZoneMaxRatio = 0.4;
/// 视为"明确横向"的最小位移：低于它不判定（避免点按抖动误切）。
static CGFloat const kSwipeMinTranslation = 8;

@implementation IMChatFolderLogic

+ (NSArray<IMConversation *> *)conversations:(NSArray<IMConversation *> *)convs inFolder:(IMChatFolder *)folder {
    if (!folder) { return convs; }
    NSMutableArray<IMConversation *> *out = [NSMutableArray array];
    for (IMConversation *c in convs) {
        if ([folder containsConv:c.convID]) { [out addObject:c]; }
    }
    return out;
}

+ (IMChatFolderBadge)badgeForConversations:(NSArray<IMConversation *> *)convs
                                  inFolder:(IMChatFolder *)folder nowMillis:(int64_t)now {
    NSInteger main = 0, mutedSum = 0;
    for (IMConversation *c in convs) {
        if (folder && ![folder containsConv:c.convID]) { continue; }
        // 条数：有未读数用未读数；没有但被手动标未读 → 计 1（Telegram 同）。
        NSInteger n = c.unread > 0 ? c.unread : (c.markedUnread ? 1 : 0);
        if (n <= 0) { continue; }
        if (IMIsMutedNow(c.muted, c.muteUntil, now)) {
            if (c.mentionUnread) { main += 1; } // @我 穿透免打扰，但不放大成条数（同 IMTabUnreadCount）
            else { mutedSum += n; }
        } else {
            main += n;
        }
    }
    IMChatFolderBadge b;
    if (main > 0) { b.count = main; b.muted = NO; }
    else { b.count = mutedSum; b.muted = mutedSum > 0; }
    return b;
}

+ (CGFloat)tailZoneWidthForListWidth:(CGFloat)listWidth actionsWidth:(CGFloat)actionsWidth {
    return MIN(MAX(actionsWidth, 0), listWidth * kTailZoneMaxRatio);
}

+ (IMChatFolderSwipeOutcome)swipeOutcomeForTranslationX:(CGFloat)tx startX:(CGFloat)startX listWidth:(CGFloat)listWidth
                                           actionsWidth:(CGFloat)actionsWidth
                                                hasNext:(BOOL)hasNext hasPrev:(BOOL)hasPrev rowOpen:(BOOL)rowOpen {
    if (fabs(tx) < kSwipeMinTranslation) { return IMChatFolderSwipeOutcomeNone; }
    if (tx < 0) { // 向左滑：下一个 Tab，或滑出该行按钮
        if (rowOpen) { return IMChatFolderSwipeOutcomeRowSwipe; } // 已展开：只用于收起
        if (!hasNext) { return IMChatFolderSwipeOutcomeRowSwipe; } // 没有下一个 Tab：整行都可滑出按钮
        CGFloat tail = [self tailZoneWidthForListWidth:listWidth actionsWidth:actionsWidth];
        return startX >= listWidth - tail ? IMChatFolderSwipeOutcomeRowSwipe : IMChatFolderSwipeOutcomeNextTab;
    }
    // 向右滑：行没有向右的操作，不冲突；已展开时只用于收起
    if (rowOpen) { return IMChatFolderSwipeOutcomeNone; }
    return hasPrev ? IMChatFolderSwipeOutcomePrevTab : IMChatFolderSwipeOutcomeNone;
}

+ (NSInteger)indexOfFolderID:(NSString *)selectedID inFolders:(NSArray<IMChatFolder *> *)folders {
    if (selectedID.length == 0) { return -1; }
    for (NSUInteger i = 0; i < folders.count; i++) {
        if ([folders[i].folderID isEqualToString:selectedID]) { return (NSInteger)i; }
    }
    return -1;
}

@end
