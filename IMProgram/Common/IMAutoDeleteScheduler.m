//  IMAutoDeleteScheduler.m

#import "IMAutoDeleteScheduler.h"
#import "IMAutoDelete.h"
#import "IMDatabase.h"
#import "IMDatabase+AutoDelete.h"
#import "IMSocketManager.h"
#import "IMSocketManager+BatchDelete.h"   // kIMMsgOpTargetSeqsKey
#import "NSObject+IMCoalescedPerform.h"
#import "IMTimeUtil.h"
#import "IMLog.h"
#import <UIKit/UIKit.h>

const NSTimeInterval IMAutoDeleteSweepInterval = 30;
static const NSTimeInterval kCoalesceDelay = 0.25;

@implementation IMAutoDeleteScheduler {
    NSMutableSet<NSString *> *_pending;   // 主线程访问
    BOOL _pendingAll;
    NSTimer *_timer;
    dispatch_queue_t _queue;
    BOOL _started;
}

+ (instancetype)shared {
    static IMAutoDeleteScheduler *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [IMAutoDeleteScheduler new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _pending = [NSMutableSet set];
        _queue = dispatch_queue_create("com.libeyond.im.autodelete", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)start {
    if (_started) { [self requestSweepForConv:nil]; return; }
    _started = YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onForeground)
                                               name:UIApplicationWillEnterForegroundNotification object:nil];
    _timer = [NSTimer timerWithTimeInterval:IMAutoDeleteSweepInterval target:self selector:@selector(onTick) userInfo:nil repeats:YES];
    _timer.tolerance = 3;
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
    [self requestSweepForConv:nil];
}

- (void)onTick { [self requestSweepForConv:nil]; }
- (void)onForeground { [self requestSweepForConv:nil]; }

- (void)requestSweepForConv:(NSString *)convID {
    if (convID.length > 0) { [_pending addObject:convID]; } else { _pendingAll = YES; }
    [self im_coalescedPerform:@selector(flushPending) afterDelay:kCoalesceDelay];
}

- (void)flushPending {
    NSArray<NSString *> *convs = _pendingAll ? nil : _pending.allObjects;
    [_pending removeAllObjects];
    _pendingAll = NO;
    dispatch_async(_queue, ^{
        NSMutableArray<NSString *> *summaryOnly = [NSMutableArray array];
        NSDictionary<NSString *, NSArray<NSNumber *> *> *removed = [self sweepConvs:convs nowMs:IMNowMillis() summaryOnly:summaryOnly];
        if (removed.count == 0 && summaryOnly.count == 0) { return; }
        dispatch_async(dispatch_get_main_queue(), ^{
            for (NSString *convID in summaryOnly) { // 没有可删的消息行，但会话行预览 / 未读变了：通知列表（与聊天页）按库刷新
                [NSNotificationCenter.defaultCenter postNotificationName:IMSocketDidUpdateConversationNotification
                    object:IMSocketManager.sharedManager userInfo:@{ kIMConvIDKey: convID }];
            }
            for (NSString *convID in removed) {
                NSArray<NSNumber *> *seqs = removed[convID];
                [NSNotificationCenter.defaultCenter postNotificationName:IMSocketDidRemoveMessageNotification
                    object:IMSocketManager.sharedManager
                    userInfo:@{ kIMConvIDKey: convID, kIMMsgOpTargetSeqKey: seqs.firstObject, kIMMsgOpTargetSeqsKey: seqs }];
            }
        });
    });
}

- (NSDictionary<NSString *, NSArray<NSNumber *> *> *)sweepConvs:(NSArray<NSString *> *)convIDs nowMs:(int64_t)nowMs {
    return [self sweepConvs:convIDs nowMs:nowMs summaryOnly:nil];
}

- (NSDictionary<NSString *, NSArray<NSNumber *> *> *)sweepConvs:(NSArray<NSString *> *)convIDs nowMs:(int64_t)nowMs
                                                    summaryOnly:(NSMutableArray<NSString *> *)summaryOnly {
    IMDatabase *db = IMDatabase.sharedDatabase;
    NSMutableDictionary<NSString *, IMAutoDeleteConfig *> *targets = [NSMutableDictionary dictionary];
    if (convIDs) {
        for (NSString *c in convIDs) {
            IMAutoDeleteConfig *cfg = [db autoDeleteConfigForConv:c];
            if (cfg.active) { targets[c] = cfg; }
        }
    } else {
        [targets addEntriesFromDictionary:[db autoDeleteActiveConvs]];
    }
    NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *out = [NSMutableDictionary dictionary];
    for (NSString *convID in targets) {
        IMAutoDeleteConfig *cfg = targets[convID];
        NSArray<NSNumber *> *seqs = [db deleteExpiredMessagesForConv:convID config:cfg nowMs:nowMs];
        if (seqs.count > 0) { out[convID] = seqs; }
        else if ([db refreshAutoDeleteSummaryForConv:convID config:cfg nowMs:nowMs]) { [summaryOnly addObject:convID]; }
    }
    return out;
}

@end
