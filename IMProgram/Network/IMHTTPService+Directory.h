//  IMHTTPService+Directory.h
//  集团与组织通讯录 REST（im-spec/PROTOCOL.md §11 `/api/v1/directory/*`，TENANT_DESIGN v2 §8.1）。
//  可见范围全由服务端按身份裁剪，客户端不传身份、不再过滤。错误保留业务码（400101 等按码出文案）。

#import "IMHTTPService.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^IMDirectoryCompletion)(NSDictionary *_Nullable data, NSError *_Nullable error);

@interface IMHTTPService (Directory)

/// GET /directory/me：我的集团与身份。
- (void)directoryMeWithToken:(NSString *)token completion:(IMDirectoryCompletion)completion;
/// POST /directory/redeem {code}：绑定子公司邀请码，成功回与 me 同形。
- (void)redeemInviteCodeWithToken:(NSString *)token code:(NSString *)code completion:(IMDirectoryCompletion)completion;
/// GET /directory/units：我能浏览的单位。
- (void)directoryUnitsWithToken:(NSString *)token completion:(IMDirectoryCompletion)completion;
/// GET /directory/units/{unit}/depts/{dept}：部门页（deptID 传 "root" 为单位顶层）；cursor 空 = 第一页。
- (void)directoryDeptWithToken:(NSString *)token unitID:(NSString *)unitID deptID:(NSString *)deptID
                        cursor:(nullable NSString *)cursor completion:(IMDirectoryCompletion)completion;
/// GET /directory/search?q=：集团内按姓名搜员工。
- (void)directorySearchWithToken:(NSString *)token query:(NSString *)query completion:(IMDirectoryCompletion)completion;
/// POST /directory/notice-ack：确认审计告知。
- (void)directoryNoticeAckWithToken:(NSString *)token completion:(IMDirectoryCompletion)completion;

@end

NS_ASSUME_NONNULL_END
