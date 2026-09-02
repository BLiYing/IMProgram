//  IMChatSearchState.h
//  会话内搜索的**状态协作对象**（仅 IMChatViewController+Search.m 使用）。
//  搜索的 20 项状态曾直接堆在 IMChatViewController+Private.h 共享类扩展里，触发 pre-commit
//  「共享私有头属性数」预算（>72）——按 CODING_STYLE §7 收进本状态袋：聊天页只持有一个
//  searchState，进入搜索创建、退出置 nil 整体释放。纯状态容器，无行为。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMChatSearchState : NSObject

@property (nonatomic, assign) BOOL searching;                        ///< 搜索态开关
@property (nonatomic, strong, nullable) UIView *searchTopBar;        ///< 顶部搜索栏（自持 IMLiquidNavigationBar，searchMode）
@property (nonatomic, strong, nullable) UISearchTextField *searchField; ///< 标题栏内搜索输入框（支持 UISearchToken）
@property (nonatomic, strong, nullable) UIView *searchNavBar;        ///< 底部命中导航条容器（透明）
@property (nonatomic, strong, nullable) UIView *searchCountPill;     ///< 「第 N / M 条」独立玻璃胶囊
@property (nonatomic, strong, nullable) UILabel *searchCountLabel;   ///< 胶囊内文字
@property (nonatomic, strong, nullable) UIButton *searchPrevButton;  ///< ▲ 上一条（更旧）
@property (nonatomic, strong, nullable) UIButton *searchNextButton;  ///< ▼ 下一条（更新）
@property (nonatomic, strong, nullable) UIButton *searchCalButton;   ///< 📅 日历
@property (nonatomic, strong, nullable) UIButton *searchFromButton;  ///< 👤 来自（仅群聊）
@property (nonatomic, strong, nullable) NSLayoutConstraint *searchNavBottom; ///< 底部导航条随键盘上移
@property (nonatomic, strong, nullable) NSArray<NSNumber *> *searchHits; ///< 命中 conv_seq，升序（旧→新）
@property (nonatomic, assign) NSInteger searchHitIndex;             ///< 当前命中下标（0 基，对应升序）
@property (nonatomic, copy, nullable) NSString *searchKeyword;
@property (nonatomic, copy, nullable) NSString *searchFromUID;      ///< 「来自」过滤发件人（nil=不过滤）
@property (nonatomic, strong, nullable) UIView *searchFromPanel;    ///< 「来自」发件人下拉
@property (nonatomic, strong, nullable) id searchKbObserver;        ///< 搜索态专用键盘观察者
@property (nonatomic, weak, nullable) UIView *hiddenInjectedBar;    ///< 搜索期间被隐藏的注入液态栏（退出恢复）
@property (nonatomic, strong, nullable) NSLayoutConstraint *searchSavedTableBottom; ///< 原「表底=replyBar 顶」约束
@property (nonatomic, strong, nullable) NSLayoutConstraint *searchTableBottom;      ///< 搜索期间「表底=屏幕底」
@property (nonatomic, assign) CGFloat savedBottomInset;   ///< 进搜索前表格原 contentInset.bottom（退出恢复；键盘让位在其上叠加）
/// 降级提示（离线只搜/只显已下载部分）本次搜索会话里是否已弹过——每敲一个字弹一次 toast 是骚扰。
@property (nonatomic, assign) BOOL degradedSearchNoticed;
@property (nonatomic, assign) BOOL degradedCalendarNoticed;

/// 服务端检索只回一页（上限 50，与 im-web 同）。命中数被截断时计数胶囊写「/ 50+ 条」，
/// 否则用户会以为大群里就只有这些命中——数字看着正常、其实是页大小。
@property (nonatomic, assign) BOOL searchHitsTruncated;

/// 服务端日历给的「某天 → 当天第一条 conv_seq」。有缺口时按日期跳转不能只查本地：
/// 那一天的消息可能整天都在缺口里，本地查出来会落到别的日子（且只弹一句"该日期无消息"）。
@property (nonatomic, strong, nullable) NSDictionary<NSNumber *, NSNumber *> *serverDayFirstSeq;

@property (nonatomic, strong, nullable) UITapGestureRecognizer *tapToDismiss; ///< 点列表空白收起键盘（不吞点击）

@end

NS_ASSUME_NONNULL_END
