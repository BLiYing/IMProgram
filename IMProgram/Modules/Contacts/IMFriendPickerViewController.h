//  IMFriendPickerViewController.h
//  **通用好友多选页**：建群选初始成员 / 群内邀请成员 / 会话详情页加成员 / **分享个人名片**共用。
//  （原名 IMGroupMemberPickerViewController、在 Modules/Group/ 下，2026-08-29 改名并移来 Contacts/：
//   它服务 4 个群场景 + 1 个非群场景，页面标题本就是中性的「选择好友」，名不副实。行为零变化。）
//
//  ⚠️ **本页自身不关闭**，由调用方决定后续导航：全部调用点都是 `pushViewController:` +
//  在 onDone 里 `popToViewController:` 收起。**不要改成模态 present**——present 出来又不收起，
//  紧接着在同一个 VC 上 present 别的东西会被 UIKit 以「已在 presenting」拒绝（名片入口曾因此
//  点「发送」毫无反应，2026-08-29）。
//  列出我的好友（accepted），勾选多个后点右上「确定」回调选中 uid 集。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMFriendPickerViewController : UIViewController

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
