//
//  IMFailBadgeView.h
//  发送失败红❗（微信式）：气泡左侧 18pt 红底白「!」圆点，**点击 = 重发**。
//
//  收敛此前逐 cell 复制的那 8 行样式 + 各自一套 hidden 开关：文本/文件、单图/视频、相册宫格
//  各抄了一份，名片/链接卡/合并转发卡则整个漏了（=这三类失败后连失败标记都没有）。
//  新增消息 cell 一律用本视图，别再手搓第四份。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMFailBadgeView : UIControl

/// 红❗直径（子类布局用：宽高约束的常量）。
@property (class, nonatomic, assign, readonly) CGFloat diameter;

/// 点击回调。仅 `tappable == YES` 时会触发。
@property (nonatomic, copy, nullable) void (^onTap)(void);

/// 是否可点（= 该条消息可重发，见 `IMResendPolicyForMessage`）。
/// NO 时红❗照显但不吃点击（`userInteractionEnabled=NO`，事件穿透给气泡）——
/// 被拒收的消息重发必然再次被拒，它的恢复入口是气泡下方那行系统行，不是红❗。
@property (nonatomic, assign) BOOL tappable;

@end

NS_ASSUME_NONNULL_END
