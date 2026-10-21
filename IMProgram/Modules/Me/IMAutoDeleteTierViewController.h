//  IMAutoDeleteTierViewController.h
//  自动删除消息 · 档位选择页（AUTO_DELETE_DESIGN §3.3 B）：关闭 / 1 天 / 1 周 / 1 个月 单选。
//  账号默认（隐私页入口）与单会话（资料页入口）共用同一页，只有页脚文案与保存动作不同——
//  样式沿用 IMLanguageViewController（inset-grouped + ✓），不新造组件。
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 选中档位后的保存回调：owner 做网络保存 / 确认框，结束后调 done(saved)。saved=NO（失败或取消）时本页把 ✓ 回滚到原档位。
typedef void (^IMAutoDeleteTierSelect)(int64_t sec, void (^done)(BOOL saved));

@interface IMAutoDeleteTierViewController : UIViewController

/// footer：账号默认传 autodel.default.footer，单会话传 autodel.conv.footer。
/// optimistic：YES=点中立即打 ✓（账号默认，不弹确认）；NO=等 owner 确认并保存成功后才打 ✓（会话级有确认框）。
/// 保存成功后本页自己 pop 返回。
- (instancetype)initWithCurrentSec:(int64_t)currentSec
                            footer:(NSString *)footer
                        optimistic:(BOOL)optimistic
                          onSelect:(IMAutoDeleteTierSelect)onSelect;

/// 账号默认档位的选择页（隐私页入口 / 设置搜索直达共用）：自己负责 GET 回显（进页时取最新值）与 PUT 保存，
/// 选中即存（不弹确认）、失败 toast `autodel.save_failed` 并回滚；成功后调 onSaved(sec) 再返回上一页。
+ (instancetype)accountDefaultPickerWithInitialSec:(int64_t)sec onSaved:(nullable void (^)(int64_t sec))onSaved;

@end

NS_ASSUME_NONNULL_END
