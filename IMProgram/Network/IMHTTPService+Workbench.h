//  IMHTTPService+Workbench.h
//  工作台 REST（im-spec/design/WORKBENCH_DESIGN.md §4.1 `/api/v1/workbench*`）。能看哪家公司由服务端判，
//  错误保留业务码（400131 不能移除、400141 已下架、400102 看不到这家公司）。

#import "IMHTTPService.h"

NS_ASSUME_NONNULL_BEGIN

/// 工作台相关业务码（CONVENTIONS / WORKBENCH_DESIGN §5）；文案走 IMHTTPService 的统一映射（err.<码>）。
typedef NS_ENUM(NSInteger, IMWorkbenchErrorCode) {
    IMWorkbenchErrorOrgNotVisible  = 400102, ///< 这家公司的工作台看不到了（被移出 / 公司关了工作台）
    IMWorkbenchErrorAppFixed       = 400131, ///< 强制安装、不可移除
    IMWorkbenchErrorAppUnavailable = 400141, ///< 应用已下架 / 停用 / 不在我的工作台里
};

typedef void (^IMWorkbenchCompletion)(NSDictionary *_Nullable data, NSError *_Nullable error);

@interface IMHTTPService (Workbench)

/// GET /workbench?unit_id=：{unit, banners, groups}。
- (void)workbenchHomeWithToken:(NSString *)token unitID:(NSString *)unitID completion:(IMWorkbenchCompletion)completion;
/// GET /workbench/store?unit_id=：{groups}。
- (void)workbenchStoreWithToken:(NSString *)token unitID:(NSString *)unitID completion:(IMWorkbenchCompletion)completion;
/// POST /workbench/apps/{id}/add|remove {unit_id}。add=NO 即移除。
- (void)workbenchSetAppWithToken:(NSString *)token unitID:(NSString *)unitID appID:(NSString *)appID
                            add:(BOOL)add completion:(IMWorkbenchCompletion)completion;
/// POST /workbench/apps/{id}/open {unit_id}：{url}（可能带一次性票据，拿到立即打开、不缓存）。
- (void)workbenchOpenAppWithToken:(NSString *)token unitID:(NSString *)unitID appID:(NSString *)appID
                       completion:(IMWorkbenchCompletion)completion;

@end

NS_ASSUME_NONNULL_END
