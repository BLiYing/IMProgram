//  IMGroupMemberPickerViewController.h
//  **通用好友多选页**：建群选初始成员 / 群内邀请成员 / 会话详情页加成员 / **分享个人名片**共用。
//  （类名带 Group、文件在 Modules/Group/ 是历史遗留——它已服务 4 个群场景 + 1 个非群场景；
//   改名 IMFriendPickerViewController 并移到 Modules/Contacts/ 列 P1，单独一次机械提交做，
//   免得功能 diff 混进一堆 rename 噪声。行为与本页语义无关，页面标题本就是中性的「选择好友」。）
//  列出我的好友（accepted），勾选多个后点右上「确定」回调选中 uid 集。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMGroupMemberPickerViewController : UIViewController

/// excludedIDs：不显示的 uid（如已在群内的成员）；confirmTitle：右上按钮文案（如 创建/邀请）。
/// onDone：用户确认后回调选中的 uid（至少 1 个才可确认）；页面自身不关闭，由调用方决定后续导航。
- (instancetype)initWithHost:(NSString *)host
                      userID:(NSString *)userID
                 excludedIDs:(nullable NSSet<NSString *> *)excludedIDs
                confirmTitle:(NSString *)confirmTitle
                      onDone:(void (^)(NSArray<NSString *> *selectedIDs))onDone NS_DESIGNATED_INITIALIZER;

/// 最多可选人数；**0 = 不限**（默认，建群/邀请场景无所谓）。达到上限后未选中行置灰不可点。
/// 分享名片传 9（与转发选择页多选上限一致）——"一次发 200 张名片"是刷屏。
/// 加法式参数：既有 4 个调用点不传即保持原行为。**须在 present 前设。**
@property (nonatomic, assign) NSUInteger maxSelection;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
