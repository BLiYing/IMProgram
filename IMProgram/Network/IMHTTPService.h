//  IMHTTPService.h
//  非实时 HTTP 接口（登录、会话列表）。实时收发走 IMSocketManager。

#import <Foundation/Foundation.h>

@class IMConversation;

NS_ASSUME_NONNULL_BEGIN

@interface IMHTTPService : NSObject

+ (instancetype)sharedService;

/// 服务器地址 host:port（如 192.168.1.3:8080）。
@property (nonatomic, copy) NSString *host;

/// 开发期免密登录，换取 JWT。completion 在主线程回调。
- (void)loginWithUserID:(NSString *)userID
             completion:(void (^)(NSString *_Nullable token, NSError *_Nullable error))completion;

/// 拉取会话列表（Bearer token）。completion 在主线程回调。
- (void)conversationsWithToken:(NSString *)token
                    completion:(void (^)(NSArray<IMConversation *> *_Nullable conversations, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
