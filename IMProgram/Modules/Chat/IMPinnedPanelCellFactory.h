//  IMPinnedPanelCellFactory.h
//  置顶面板的行装配：复用聊天页**真实**消息 cell（readOnly），按聊天页 +DataSource 同一套参数配置，
//  并在气泡旁挂「定位到聊天位置」圆钮（32×32，底 surfaceElevated + 软阴影，图标 18 accent）。
//  与聊天页装配的差异只在面板语义：群聊对方消息**每条**都显头像 + 昵称（面板里没有连续段合并）、
//  不画已读勾 / 发送状态、文件不画下载环、语音不显未播红点、所有内容回调不挂（只读）。

#import <UIKit/UIKit.h>
#import "IMPinnedPanelViewController.h" // IMPinnedPanelHost

@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

@interface IMPinnedPanelCellFactory : NSObject

/// 注册面板用到的全部 cell 类（聊天页同款 + 日期胶囊行）。
+ (void)registerCellsInTableView:(UITableView *)tableView;

/// 日期胶囊行（与聊天页日期分隔同款：accent 64% 底、12 semibold、高 24、圆角 12）。
+ (UITableViewCell *)dayPillCellWithText:(NSString *)text tableView:(UITableView *)tableView indexPath:(NSIndexPath *)indexPath;

/// 消息行。onLocate：点定位圆钮；onLayoutChange：异步内容（媒体尺寸 / 链接预览）回来需刷行高。
+ (UITableViewCell *)messageCellForMessage:(IMMessageModel *)message
                                      mine:(BOOL)mine
                                      host:(id<IMPinnedPanelHost>)host
                                 tableView:(UITableView *)tableView
                                 indexPath:(NSIndexPath *)indexPath
                                  onLocate:(void (^)(void))onLocate
                            onLayoutChange:(void (^)(void))onLayoutChange;

/// 行里的气泡本体（定位圆钮贴它、点击 / 长按按它命中、菜单锚它）。日期行 / 非消息 cell 返回 nil。
+ (nullable UIView *)bubbleViewInCell:(UITableViewCell *)cell;

/// point（cell 坐标系）是否落在气泡上（有 IMBubbleHitTesting 的用其精确判定，否则按气泡矩形）。
+ (BOOL)cell:(UITableViewCell *)cell bubbleContainsPoint:(CGPoint)point;

@end

NS_ASSUME_NONNULL_END
