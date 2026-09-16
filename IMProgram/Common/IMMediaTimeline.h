//  IMMediaTimeline.h
//  在「会话媒体时间线」里定位一条消息的判据（媒体查看器左右翻页用）。
//
//  ## 为什么要有这一份
//  查看器翻页要先回答「点中的这条是时间线里的第几张」。时间线是**现查数据库**得到的
//  （`mediaMessagesForConv:`），而点中的那条来自聊天页自己的那一窗——**两次查询、两批对象**。
//  原先这里用的是 `indexOfObjectIdenticalTo:`（指针相等），于是它恒 `NSNotFound`，
//  每次都掉进「找不到就单开一个查看器」的兜底分支：**聊天页点图片打开的查看器从来不能翻页**，
//  而媒体库那条路（直接按下标开）一直正常。2026-09-16 用户报「iOS 点图片不能翻页，
//  媒体库的翻页不是有吗」，就是这一条。
//
//  错得静默是它的性质：兜底分支本身是对的，界面照常，只是少了翻页——编译、测试、review 都看不出。
//
//  ## 口径（与 im-web `src/album.ts` 的 `msgKey` 同源，IMServer/docs/SYMMETRY.md 有登记）
//  **身份优先用 `conv_seq`**（服务端分配、会话内唯一）。Web 那侧记着同一条真账：
//  入站消息的 `clientMsgId` 恒为空，拿它当 key 会让所有入站消息都命中"第一条空值"，
//  表现是点最后一张却定位到第一张。本端的对应风险是自己发的那条——ack 之前 `convSeq` 还是 0，
//  此时只有 `clientMsgID` 认得出它，故作第二档。

#import <Foundation/Foundation.h>

@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

/**
 在媒体时间线里找出 `target` 的下标。

 @param timeline 会话媒体时间线（`mediaMessagesForConv:` 的结果，升序）。
 @param target   点中的那条消息，通常来自**另一批**查询，故不可用指针相等去找。
 @return 下标；不在时间线里（或入参为空）返回 `NSNotFound`。

 匹配顺序：① `convSeq > 0` 按 `convSeq`；② 否则按非空 `clientMsgID`；③ 都没有时退回指针相等。
 */
extern NSUInteger IMMediaTimelineIndexOfMessage(NSArray<IMMessageModel *> *_Nullable timeline,
                                                IMMessageModel *_Nullable target);

NS_ASSUME_NONNULL_END
