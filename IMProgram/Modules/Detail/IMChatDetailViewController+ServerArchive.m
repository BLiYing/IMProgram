//  IMChatDetailViewController+ServerArchive.m

#import "IMChatDetailViewController+ServerArchive.h"
#import "IMDetailServerArchive.h"
#import "IMChatDetailTabs.h"
#import "IMConvQuerySource.h"
#import "IMDatabase+Ranges.h"
#import "IMDatabase+ClearFloor.h"
#import "IMChatWindowPlan.h"
#import "IMNetworkMonitor.h"
#import "IMSocketManager.h"
#import "IMDatabase.h"
#import "IMLocalization.h"
#import "UIViewController+IMToast.h"

/// 离底多少 pt 就开始续拉（约 1~2 屏）。
static const CGFloat kArchiveLoadThreshold = 600;

@implementation IMChatDetailViewController (ServerArchive)

- (void)im_startServerArchiveIfNeeded {
    if (self.serverArchive || self.convID.length == 0) { return; }
    NSString *convID = self.convID;
    __block BOOL complete = YES;
    __block int64_t cleared = 0;
    int64_t serverFloor = [IMSocketManager.sharedManager historyFloorForConv:convID]; // 块外读（块里持账号锁，反向等锁会死）
    [self performDatabaseOperation:^(IMDatabase *database) {
        complete = [database isConvComplete:convID floor:serverFloor];
        cleared = [database clearedUpToForConv:convID];
    }];
    BOOL online = IMNetworkMonitor.shared.currentType != IMNetworkTypeNone;
    IMConvQuerySource src = IMPickConvQuerySource(complete, online);
    if (src == IMConvQuerySourceLocalDegraded) {
        [self im_showToast:IMLocalized(@"media.viewer.offline_partial_notice")]; // 离线且有缺口：只看得到已下载的，说出来
        return;
    }
    if (src != IMConvQuerySourceServer) { return; }
    IMDetailServerArchive *archive = [[IMDetailServerArchive alloc] initWithConvID:convID clearedUpTo:cleared];
    self.serverArchive = archive;
    __weak typeof(self) ws = self;
    [archive loadFirstPages:^{
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        [self rebuildTabs]; // 服务端带来的类型可能让语音 / 名片等页签第一次出现
        [self.tableView reloadData];
    }];
}

- (NSArray<IMMessageModel *> *)im_archiveMergedWithLocal:(NSArray<IMMessageModel *> *)local {
    return self.serverArchive ? [self.serverArchive mergedWithLocal:local] : local;
}

- (void)im_loadMoreArchiveIfNearBottom:(UIScrollView *)scrollView {
    IMDetailServerArchive *archive = self.serverArchive;
    if (!archive || self.tabs.count == 0 || self.selectedTab >= (NSInteger)self.tabs.count) { return; }
    IMDetailTabKind kind = self.tabs[self.selectedTab].kind;
    if (![IMDetailServerArchive kindIsArchived:kind] || ![archive hasMoreForKind:kind] || [archive isLoadingKind:kind]) { return; }
    CGFloat remaining = scrollView.contentSize.height - scrollView.contentOffset.y - scrollView.bounds.size.height;
    if (scrollView.bounds.size.height <= 0 || remaining > kArchiveLoadThreshold) { return; }
    __weak typeof(self) ws = self;
    [archive loadMoreForKind:kind completion:^(NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) { [self im_showToast:IMLocalized(@"media.viewer.offline_partial_notice")]; }
        [self recomputeTabContent];
        [self.tableView reloadData];
    }];
}

@end
