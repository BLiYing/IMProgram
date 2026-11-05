//  IMShareContactListViewController.h
//  分享选择页的两个子页：「我的好友」（A–Z 分组 + 索引尺）/「我的群聊」（SHARE_PICKER_UX_SKETCH ②）。
//  push 在选择页自己的导航栈里；勾选状态、上限、单选确认、多选发送都委托回主选择页（IMSharePickerHost），
//  所以三页读写的是**同一份** IMShareSelection——在哪页勾的，别的页看到的都是已勾选。

#import <UIKit/UIKit.h>

@class IMConversation;
@class IMShareSelection;
@class IMShareTargetDirectory;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, IMShareContactListKind) {
    IMShareContactListFriends,
    IMShareContactListGroups,
};

/// 主选择页实现。子页只管展示，选中集与发送流程都在主页。
@protocol IMSharePickerHost <NSObject>
@property (nonatomic, readonly) IMShareSelection *shareSelection;
@property (nonatomic, readonly) BOOL shareMultiSelect;
/// 点行：多选态切换勾选（满了吐司）；单选态弹确认框后发送。presenter = 当前可见页（弹框 / 吐司挂它上面）。
- (void)shareHostDidTapTarget:(IMConversation *)target from:(UIViewController *)presenter;
/// 已选栏 ✕。
- (void)shareHostRemoveConvID:(NSString *)convID from:(UIViewController *)presenter;
/// 已选栏「发送(N)」→ 确认面板。
- (void)shareHostSendFrom:(UIViewController *)presenter;
@end

@interface IMShareContactListViewController : UIViewController

- (instancetype)initWithKind:(IMShareContactListKind)kind
                   directory:(IMShareTargetDirectory *)directory
                        host:(id<IMSharePickerHost>)host NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nib bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

/// 选中集变了（自己或别处改的）→ 刷新勾选、已选栏、标题副标题。
- (void)selectionDidChangeScrollToEnd:(BOOL)scrollToEnd;

@end

NS_ASSUME_NONNULL_END
