//  IMMsgOpApply.m
//  规则与坑写在头文件注释里，这里只留实现。

#import "IMMsgOpApply.h"
#import "IMMessageModel.h"
#import "IMPinnedMessage.h"
#import "IMProtocol.h"
#import "IMSocketManager.h"   // kIMMsgOp*Key / kIMConvIDKey

static NSString *StringOrNil(id v) { return [v isKindOfClass:NSString.class] ? v : nil; }

@interface IMMsgOpPatch ()
@property (nonatomic, assign, readwrite) IMMsgOpKind kind;
@property (nonatomic, copy, readwrite) NSString *convID;
@property (nonatomic, assign, readwrite) int64_t targetConvSeq;
@property (nonatomic, copy, readwrite, nullable) NSString *clientMsgID;
@property (nonatomic, copy, readwrite, nullable) NSString *by;
@property (nonatomic, assign, readwrite) int64_t recalledAt;
@property (nonatomic, assign, readwrite) int64_t editedAt;
@property (nonatomic, copy, readwrite, nullable) NSString *editedContent;
@property (nonatomic, assign, readwrite) int64_t pinnedAt;
@end

@implementation IMMsgOpPatch

+ (nullable instancetype)patchFromPayload:(NSDictionary *)payload nowMillis:(int64_t)now {
    NSString *convID = StringOrNil(payload[@"conv_id"]) ?: @"";
    int64_t target = [payload[@"target_conv_seq"] longLongValue];
    if (convID.length == 0 || target <= 0) { return nil; }

    IMMsgOpPatch *p = [[IMMsgOpPatch alloc] init];
    p.convID = convID;
    p.targetConvSeq = target;
    p.clientMsgID = StringOrNil(payload[@"client_msg_id"]);
    p.by = StringOrNil(payload[@"by"]);

    NSString *op = StringOrNil(payload[@"op"]) ?: @"";
    if ([op isEqualToString:kIMMsgOpDelete]) {
        p.kind = IMMsgOpKindDelete;
    } else if ([op isEqualToString:kIMMsgOpRecall]) {
        p.kind = IMMsgOpKindRecall;
        p.recalledAt = now;
    } else if ([op isEqualToString:kIMMsgOpEdit]) {
        p.kind = IMMsgOpKindEdit;
        p.editedAt = now;
        p.editedContent = StringOrNil(payload[@"content"]) ?: @"";
    } else if ([op isEqualToString:kIMMsgOpPin]) {
        p.kind = IMMsgOpKindPin;
        BOOL pinned = [payload[@"pinned"] respondsToSelector:@selector(boolValue)] && [payload[@"pinned"] boolValue];
        int64_t ts = [payload[@"timestamp"] respondsToSelector:@selector(longLongValue)] ? [payload[@"timestamp"] longLongValue] : 0;
        p.pinnedAt = pinned ? (ts > 0 ? ts : now) : -1; // 时间取服务端，多端一致；缺省才回退本地时钟
    } else {
        p.kind = IMMsgOpKindUnknown;
    }
    return p;
}

- (NSDictionary *)appliedUserInfo {
    NSMutableDictionary *info = [@{ kIMConvIDKey: self.convID, kIMMsgOpTargetSeqKey: @(self.targetConvSeq) } mutableCopy];
    if (self.recalledAt > 0) {
        info[kIMMsgOpRecalledAtKey] = @(self.recalledAt);
        if (self.by.length > 0) { info[kIMMsgOpRecalledByKey] = self.by; }
    }
    if (self.editedAt > 0) {
        info[kIMMsgOpEditedAtKey] = @(self.editedAt);
        if (self.editedContent) { info[kIMMsgOpContentKey] = self.editedContent; }
    }
    if (self.pinnedAt != 0) { info[kIMMsgOpPinnedAtKey] = @(MAX((int64_t)0, self.pinnedAt)); } // -1(清零)→0=取消置顶
    return info;
}

@end

void IMChatApplyMsgOpToMessage(IMMessageModel *m, NSDictionary *info) {
    NSNumber *recalledAt = info[kIMMsgOpRecalledAtKey];
    NSNumber *editedAt = info[kIMMsgOpEditedAtKey];
    NSNumber *pinnedAt = info[kIMMsgOpPinnedAtKey];
    if (recalledAt) {
        m.recalledAt = recalledAt.longLongValue;
        m.recalledBy = info[kIMMsgOpRecalledByKey];
    }
    if (editedAt) {
        m.editedAt = editedAt.longLongValue;
        NSString *editedContent = info[kIMMsgOpContentKey];
        if (editedContent) { m.content = editedContent; }
        m.mentionSpans = nil; // 偏移相对原文，正文一改全错位
    }
    if (pinnedAt) { m.pinnedAt = pinnedAt.longLongValue; } // 0=取消置顶
}

NSArray<IMPinnedMessage *> *IMChatPinnedItemsDroppingSeq(NSArray<IMPinnedMessage *> *items, int64_t target) {
    NSMutableArray<IMPinnedMessage *> *kept = [NSMutableArray arrayWithCapacity:items.count];
    for (IMPinnedMessage *p in items) { if (p.convSeq != target) { [kept addObject:p]; } }
    return kept;
}

IMChatMsgOpBannerAction IMChatMsgOpBannerPlan(NSDictionary *info, NSArray<IMPinnedMessage *> *items) {
    int64_t target = [info[kIMMsgOpTargetSeqKey] longLongValue];
    BOOL recalled = info[kIMMsgOpRecalledAtKey] != nil;
    BOOL edited = info[kIMMsgOpEditedAtKey] != nil;
    BOOL pinChanged = info[kIMMsgOpPinnedAtKey] != nil;
    BOOL touches = NO;
    if (recalled || edited) {
        for (IMPinnedMessage *p in items) { if (p.convSeq == target) { touches = YES; break; } }
    }
    IMChatMsgOpBannerAction a;
    a.dropTargetLocally = recalled && touches;
    a.reload = pinChanged || touches;
    return a;
}
