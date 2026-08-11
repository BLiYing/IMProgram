//  IMReadReceiptViewController.h
//  群消息「已读 / 未读」名单卡（M4-8）。长按自己发的群消息 → 菜单里的「N 人已读」→ 本卡。
//  半屏 sheet + 原生 UISegmentedControl 分段（与 IMChatDetailViewController 页签同款），可上滑放大。
//
//  **不显示读取时刻**：已读位点语义是"读到 conv_seq 为止"，无法反推某人何时读到这一条。
//  设计依据：IMServer/docs/GROUP_READ_UX_SKETCH.html §05。

#import <UIKit/UIKit.h>

@class IMGroupInfo;

NS_ASSUME_NONNULL_BEGIN

@interface IMReadReceiptViewController : UIViewController

/// group      群资料（把 uid 解析成昵称/头像/角色标）。
/// readUIDs   已读成员 uid；unreadUIDs 未读成员 uid（均由服务端按当前成员集算好）。
/// onTapMember 点某行的回调（进成员资料页）；可空。
- (instancetype)initWithGroup:(nullable IMGroupInfo *)group
                     readUIDs:(NSArray<NSString *> *)readUIDs
                   unreadUIDs:(NSArray<NSString *> *)unreadUIDs
                  onTapMember:(nullable void (^)(NSString *userID))onTapMember NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithNibName:(nullable NSString *)n bundle:(nullable NSBundle *)b NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
