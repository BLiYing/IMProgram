//  IMCallRecordCell.h
//  音视频通话记录气泡（content_type=call，仅单聊）：普通气泡壳 + 电话/摄像机图标 + 一句话 + 时间勾，点击按原类型回拨。
//  群通话记录不走这里——居中系统条（IMSystemCell）。文案 / 红字判定全在 IMCallRecord（纯函数，三端同一份向量）。
//  与 IMContactCardCell / IMChatRecordCell 同族、同签名——签名不一致会漏掉群聊头像列与未读分割线。

#import <UIKit/UIKit.h>
#import "IMMessageCell.h"

@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

@interface IMCallRecordCell : IMMessageCell
/// 长按菜单高亮/收起动画的目标视图（=气泡本体）。
@property (nonatomic, strong, readonly) UIView *previewTargetView;
/// 点气泡 → 按记录里的类型（语音/视频）回拨。解析失败的兜底气泡不挂。
@property (nonatomic, copy, nullable) void (^onTap)(BOOL video);
// onAvatarTap 由 IMMessageCell 基类提供。

/// displayName 与名片 cell 同签名，本 cell 不用（通话记录没有「对方名字」这一栏，只有「看的人」视角）。
- (void)configureWithMessage:(IMMessageModel *)message mine:(BOOL)mine
                 displayName:(nullable NSString *)displayName
                 peerReadSeq:(int64_t)peerReadSeq
                  senderName:(nullable NSString *)senderName
                  senderRole:(IMGroupRole)senderRole;

- (void)applyGroupAvatarURL:(nullable NSString *)url
                       seed:(NSString *)seed
                       name:(nullable NSString *)name
                 showAvatar:(BOOL)showAvatar
                     gutter:(BOOL)gutter;
@end

NS_ASSUME_NONNULL_END
