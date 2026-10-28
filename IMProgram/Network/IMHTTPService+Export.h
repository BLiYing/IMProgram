//  IMHTTPService+Export.h
//  导出我的数据 REST（DATA_EXPORT_DESIGN §2）。全部 completion 回主线程。

#import "IMHTTPService.h"
#import "IMDataExport.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMHTTPService (Export)

/// POST /api/v1/users/me/exports。成功回任务对象。密码错 200002；已有进行中 200010；冷却内 200011
/// （error.userInfo[IMErrorRetryAfterSecKey] 为 retry_after_sec，回包没带则无此键）。
- (void)startExportWithToken:(NSString *)token
                    password:(NSString *)password
                includeMedia:(BOOL)includeMedia
                     formats:(NSArray<NSString *> *)formats
                  completion:(void (^)(IMExportJob *_Nullable job, NSError *_Nullable error))completion;

/// GET /api/v1/users/me/exports/latest。成功但没有任务（data:null）回 (nil, nil)。
- (void)fetchLatestExportWithToken:(NSString *)token
                        completion:(void (^)(IMExportJob *_Nullable job, NSError *_Nullable error))completion;

/// POST /api/v1/users/me/exports/{id}/cancel（幂等）。
- (void)cancelExport:(NSString *)jobID token:(NSString *)token completion:(void (^)(NSError *_Nullable error))completion;

/// POST /api/v1/users/me/exports/{id}/download_url。回相对路径 url（含一次性 token）与有效秒数。
- (void)exportDownloadURLForJob:(NSString *)jobID token:(NSString *)token
                     completion:(void (^)(NSString *_Nullable url, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
