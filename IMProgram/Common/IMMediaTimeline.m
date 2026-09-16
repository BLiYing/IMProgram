//  IMMediaTimeline.m

#import "IMMediaTimeline.h"

#import "IMMessageModel.h"

NSUInteger IMMediaTimelineIndexOfMessage(NSArray<IMMessageModel *> *timeline, IMMessageModel *target) {
    if (timeline.count == 0 || target == nil) { return NSNotFound; }

    // ① 已确认的消息：conv_seq 是服务端分配的会话内唯一序号，跨查询批次仍然认得出同一条。
    if (target.convSeq > 0) {
        NSUInteger i = 0;
        for (IMMessageModel *m in timeline) {
            if (m.convSeq == target.convSeq) { return i; }
            i++;
        }
        return NSNotFound;
    }

    // ② 还没 ack 的（conv_seq 尚为 0）：只有客户端 UUID 认得出它。
    //    **必须要求非空**——空串会命中时间线里第一条同样没有 UUID 的行（Web 那侧的原样事故）。
    if (target.clientMsgID.length > 0) {
        NSUInteger i = 0;
        for (IMMessageModel *m in timeline) {
            if ([m.clientMsgID isEqualToString:target.clientMsgID]) { return i; }
            i++;
        }
        return NSNotFound;
    }

    // ③ 两个身份都没有：只可能是调用方手上那批对象自己，指针相等仍是对的。
    return [timeline indexOfObjectIdenticalTo:target];
}
