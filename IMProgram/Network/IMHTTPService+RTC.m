//  IMHTTPService+RTC.m

#import "IMHTTPService+RTC.h"
#import "IMHTTPService+Private.h"
#import "IMLocalization.h"

@implementation IMHTTPService (RTC)

- (void)rtcTokenWithToken:(NSString *)token
                completion:(void (^)(NSDictionary *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/rtc/token" method:@"POST" token:token body:@{}];
    [self runDataRequest:req fallback:IMLocalized(@"rtc.error.token_fetch_failed") completion:completion];
}

@end
