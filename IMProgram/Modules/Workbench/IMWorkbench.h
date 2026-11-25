//  IMWorkbench.h
//  工作台的纯规则（im-spec/design/WORKBENCH_DESIGN.md §1.1 / §3 / §6），不碰 UI，单测直接调。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 应用商店里添加 / 移除了应用：工作台首页收到后重拉（object = unit_id）。
FOUNDATION_EXPORT NSNotificationName const IMWorkbenchDidChangeNotification;

/// 工作台 / 应用商店的一段：标题 + 这一段的应用（服务端下发的字典原样保留）。
@interface IMWorkbenchSection : NSObject
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSArray<NSDictionary *> *apps;
- (instancetype)initWithTitle:(NSString *)title apps:(NSArray<NSDictionary *> *)apps;
@end

@interface IMWorkbench : NSObject

/// 服务端 groups（[{name, apps}]，已按组顺序排好、没分组的在最后且 name 为空）→ 页面分段。
/// 没分组的段标题 = otherTitle；只有这一段时用 soleTitle（工作台传「我的应用」，商店传 nil = 仍叫「其他」）。空段丢掉。
+ (NSArray<IMWorkbenchSection *> *)sectionsFromGroups:(nullable NSArray *)groups
                                           otherTitle:(NSString *)otherTitle
                                            soleTitle:(nullable NSString *)soleTitle;

/// 应用 / 轮播链接能否在内置浏览器里打开：https（带主机），或指向本机 / 内网的 http（开发环境演示应用；生产服务端不会下发 http）。
+ (BOOL)isAllowedWebURL:(nullable NSURL *)url;


/// 去掉地址里的 im_ticket（「用浏览器打开」时不把一次性票据带出 App）。
+ (NSURL *)urlByRemovingTicket:(NSURL *)url;

/// 多家公司时选哪家：saved 还在列表里就用它，否则第一家；列表空返回 nil。units 每项 {unit_id, name}。
+ (nullable NSString *)pickUnitIDFrom:(NSArray<NSDictionary<NSString *, NSString *> *> *)units saved:(nullable NSString *)saved;

/// 记住 / 读出某用户上次选的公司（UserDefaults，按用户分开）。
+ (nullable NSString *)savedUnitIDForUser:(NSString *)userID;
+ (void)saveUnitID:(NSString *)unitID forUser:(NSString *)userID;

@end

NS_ASSUME_NONNULL_END
