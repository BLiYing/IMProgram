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
@end

NS_ASSUME_NONNULL_END
