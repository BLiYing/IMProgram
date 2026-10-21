#import <UIKit/UIKit.h>

@class IMSysSegment;

NS_ASSUME_NONNULL_BEGIN

@interface IMSystemCell : UITableViewCell
- (void)configureWithText:(NSString *)text;
- (void)configureWithText:(NSString *)text reeditHandler:(nullable void (^)(void))reeditHandler;

/// 分段渲染（群系统消息）：带 uid 的段用 `displayNameForUID` 换成本地显示名（备注 > 群昵称 > 昵称），
/// 染强调色并可点；其余段原样。`segments` 为空时回退 `configureWithText:`（历史消息就是这条路）。
/// onTapUID 为空则不挂点击。
- (void)configureWithSegments:(nullable NSArray<IMSysSegment *> *)segments
                 fallbackText:(NSString *)fallbackText
             displayNameForUID:(NSString *_Nonnull (^_Nullable)(NSString *uid, NSString *fallbackName))displayNameForUID
                     onTapUID:(nullable void (^)(NSString *uid))onTapUID;

/// 日期分隔胶囊（与 `IMBubbleCell` 同款：今天/昨天/M月d日）。非空 = 在系统行上方多画一枚；nil/空 = 不画。
/// 系统消息可能就是当天首条（新建群的「xx 创建了群聊」），不画则整天没有日期分隔。
/// 与 configure 系列互不影响（先后顺序无关）；复用时 prepareForReuse 自动复位。
- (void)applyDayHeader:(nullable NSString *)dayHeader;
@end

NS_ASSUME_NONNULL_END
