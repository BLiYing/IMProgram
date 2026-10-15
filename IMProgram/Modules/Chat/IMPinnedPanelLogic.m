//  IMPinnedPanelLogic.m
//  规则与来历见头文件注释。

#import "IMPinnedPanelLogic.h"
#import "IMPinnedMessage.h"
#import "IMMessageModel.h"
#import "IMContactCard.h"   // IMContentTypeContact
#import "IMCallRecord.h"    // IMContentTypeCall

NSString * const IMPinnedMenuActionUnpin = @"unpin";
NSString * const IMPinnedMenuActionCopy = @"copy";
NSString * const IMPinnedMenuActionLocate = @"locate";

NSArray<NSString *> *IMPinnedPanelMenuActionIDs(NSString *originalContentType, NSString *content, BOOL canUnpin) {
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    if (canUnpin) { [ids addObject:IMPinnedMenuActionUnpin]; }
    if ([originalContentType isEqualToString:@"text"] && content.length > 0) { [ids addObject:IMPinnedMenuActionCopy]; }
    [ids addObject:IMPinnedMenuActionLocate];
    return ids;
}

IMPinnedPanelChrome IMPinnedPanelChromeForPermission(BOOL canUnpin) {
    IMPinnedPanelChrome c;
    c.showsLongPressHint = canUnpin;
    c.showsUnpinAll = canUnpin;
    return c;
}

BOOL IMPinnedLocateIconOnLeadingSide(BOOL mine) { return mine; }

/// 面板能用聊天页真气泡渲染的类型；其余走类型词兜底。
static BOOL IMPinnedRenderableType(NSString *type) {
    static NSSet<NSString *> *known;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        known = [NSSet setWithArray:@[ @"text", @"image", @"video", @"voice", @"file", @"chat_record",
                                       IMContentTypeContact, IMContentTypeCall ]];
    });
    return type.length > 0 && [known containsObject:type];
}

IMMessageModel *IMPinnedResolveMessage(IMPinnedMessage *item, IMMessageModel *localRow, NSString *convID) {
    if (localRow && localRow.convSeq == item.convSeq) {
        if (localRow.recalledAt > 0) { return nil; } // 已撤回：不出墓碑行
        if (IMPinnedRenderableType(localRow.contentType)) { return localRow; }
    }
    IMMessageModel *remote = item.message;
    if (remote && remote.recalledAt <= 0 && IMPinnedRenderableType(remote.contentType)) {
        if (remote.convID.length == 0) { remote.convID = convID ?: @""; }
        return remote;
    }
    return [item fallbackMessageModelInConv:convID];
}

@interface IMPinnedPanelRow ()
@property (nonatomic, copy, readwrite, nullable) NSString *dayHeader;
@property (nonatomic, strong, readwrite, nullable) IMPinnedMessage *item;
@property (nonatomic, strong, readwrite, nullable) IMMessageModel *message;
@property (nonatomic, assign, readwrite) BOOL mine;
@end

@implementation IMPinnedPanelRow
@end

NSArray<IMPinnedPanelRow *> *IMPinnedPanelBuildRows(NSArray<IMPinnedMessage *> *items,
                                                    IMMessageModel *(^resolve)(IMPinnedMessage *),
                                                    NSString *myUID,
                                                    NSString *(^dayHeaderForMillis)(int64_t),
                                                    BOOL (^sameDay)(int64_t, int64_t)) {
    NSMutableArray<IMPinnedPanelRow *> *rows = [NSMutableArray array];
    int64_t prevTs = 0;
    for (IMPinnedMessage *item in items) {
        IMMessageModel *m = resolve ? resolve(item) : nil;
        if (!m) { continue; }
        int64_t ts = m.timestamp;
        if (ts > 0 && (prevTs <= 0 || !sameDay(prevTs, ts))) {
            NSString *header = dayHeaderForMillis(ts);
            if (header.length > 0) {
                IMPinnedPanelRow *pill = [IMPinnedPanelRow new];
                pill.dayHeader = header;
                [rows addObject:pill];
            }
        }
        if (ts > 0) { prevTs = ts; }
        IMPinnedPanelRow *row = [IMPinnedPanelRow new];
        row.item = item;
        row.message = m;
        row.mine = myUID.length > 0 && [m.from isEqualToString:myUID];
        [rows addObject:row];
    }
    return rows;
}
