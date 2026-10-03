//  IMMuteDurationMenu.h
//  定时免打扰时长菜单（NOTIFICATIONS_P1_DESIGN §4.1/§4.2）：会话列表左滑/右键、聊天详情页「免打扰」行、
//  「添加例外」选完会话后，三个入口共用同一份 ActionSheet + 同一份时长→mute_until 映射。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 已拍板 ④：1 小时 / 8 小时 / 1 天 / 7 天 / 永久，不做「自定义到某天」（§8.3/§8.4）。
typedef NS_ENUM(NSInteger, IMMuteDurationOption) {
    IMMuteDurationOneHour,
    IMMuteDurationEightHours,
    IMMuteDurationOneDay,
    IMMuteDurationSevenDays,
    IMMuteDurationForever,
};

/// 纯函数：选项 → 绝对到期时间戳（毫秒）。`now` 必须是**客户端当前时间**（§4.1：由客户端算出绝对
/// 时间戳再发给服务端，不是让服务端加时长）。永久固定返回 0，与协议 mute_until=0 同义。
FOUNDATION_EXPORT int64_t IMMuteUntilForDurationOption(IMMuteDurationOption option, int64_t nowMs);

/// 时长菜单（自绘底部弹层 IMActionListSheet，对齐 Android；不用系统 ActionSheet，因其 iOS 26 / 18 外观不同）。
@interface IMMuteDurationMenu : NSObject

/// 弹出菜单。title = notif.mute.sheet_title 代入会话显示名。
/// showUnmuteFirst=YES 时最上面插一条红色「取消免打扰」（用于已在定时免打扰中的会话调整时长/改永久，
/// §4.1：列表左滑/右键在已免打扰时**不弹本菜单**，直接是「取消免打扰」——那种场景不走本方法，
/// 本参数服务的是聊天信息页「免打扰」行——已免打扰时点它弹的还是这同一个菜单，只是多这一条）。
/// completion 恰好回调一次：unmuted=YES 时忽略 muteUntil（视为取消）；否则 muteUntil 为所选时长
/// 换算出的到期时间戳。用户点「取消」（ActionSheet 的 Cancel）不回调。
/// sourceView/sourceRect 用于 iPad popover 定位；host.view 为 nil 时退回 host.view 中下部。
+ (void)presentFromViewController:(UIViewController *)host
                        sourceView:(nullable UIView *)sourceView
                        sourceRect:(CGRect)sourceRect
                  conversationName:(NSString *)conversationName
                   showUnmuteFirst:(BOOL)showUnmuteFirst
                        completion:(void (^)(BOOL unmuted, int64_t muteUntil))completion;

@end

NS_ASSUME_NONNULL_END
