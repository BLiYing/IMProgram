//  IMGroupMemberPickerViewController.h
//  好友多选页（M3 群聊）：建群选初始成员、群内邀请成员共用。
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

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
