//  IMPrivacyVisibilityViewController.h
//  隐私 ▸ 谁能看到 · 档位单选页（PRIVACY_VISIBILITY_DESIGN §4）：所有人 / 我的联系人 / 无人，当前项 ✓。
//  选中即保存并返回、不弹确认；保存失败 toast ps.visibility.save_failed 且 ✓ 回滚。上次上线 / 头像共用，仅 kind 不同。
#import <UIKit/UIKit.h>
#import "IMPrivacyVisibility.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMPrivacyVisibilityViewController : UIViewController

/// 当前显示的档位（✓ 所在）。保存在途为乐观值，失败回滚为原值。
@property (nonatomic, copy, readonly) NSString *currentLevel;

/// onSaved：服务端确认后回调（隐私页据此更新行右值），随后本页自行 pop。
- (instancetype)initWithKind:(IMPrivacyVisibilityKind)kind
                currentLevel:(NSString *)level
                     onSaved:(nullable void (^)(NSString *level))onSaved;

/// 选中某档：与当前相同 → 直接返回；否则乐观打 ✓ → PUT（只带本项）→ 成功回调并 pop / 失败 toast + 回滚。
- (void)chooseLevel:(NSString *)level;

@end

NS_ASSUME_NONNULL_END
