//  IMHTTPService+Envelope.m
//  带业务码的整包解信封（注销 / 邮箱 / 两步验证 / 导出 / 手机号共用）与错误附加信息的统一入口。
//  声明在 IMHTTPService+Private.h。放在单独文件而不是 IMHTTPService.m：通用层不反向依赖各业务域的头。

#import "IMHTTPService+Private.h"
#import "IMHTTPService+Account.h"
#import "IMHTTPService+TwoStep.h"
#import "IMHTTPService+Email.h"
#import "IMHTTPService+Phone.h"
#import "IMLocalization.h"

NSError *IMErrorByAttachingEnvelopeInfo(NSError *error, NSDictionary *body) {
    // 四组键名互不相交，顺序无关；各 attach 对 data 缺失 / 无对应字段原样返回。
    NSError *err = IMErrorByAttachingAccountInfo(error, body);
    err = IMErrorByAttachingTwoStepInfo(err, body);
    err = IMErrorByAttachingEmailInfo(err, body);
    return IMErrorByAttachingPhoneInfo(err, body);
}

@implementation IMHTTPService (Envelope)

- (void)runEnvelopeRequest:(NSURLRequest *)req completion:(void (^)(id, NSError *))completion {
    [self runEnvelopeRequest:req decorateError:nil completion:completion];
}

- (void)runEnvelopeRequest:(NSURLRequest *)req
             decorateError:(NSError *(^)(NSError *, NSDictionary *))decorate
                completion:(void (^)(id, NSError *))completion {
    if (!req) {
        [self callOnMain:^{ completion(nil, [self errorWithMessage:IMLocalized(@"net.error.invalid_server")]); }];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [self runRequest:req completion:^(NSDictionary *body, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (error) { [self callOnMain:^{ completion(nil, error); }]; return; }
        // 信封缺 code（网关 / 代理回了别的 JSON）不能当成功：如注销成功会触发本机清库 + 登出，必须有明确的 code=0。
        BOOL hasCode = [body[@"code"] isKindOfClass:NSNumber.class] || [body[@"code"] isKindOfClass:NSString.class];
        NSInteger code = hasCode ? [body[@"code"] integerValue] : -1;
        if (code == 0) { [self callOnMain:^{ completion(body[@"data"], nil); }]; return; }
        NSError *err = [self errorWithCode:code message:[self messageFrom:body fallback:IMLocalized(@"common.action_failed")]];
        err = IMErrorByAttachingEnvelopeInfo(err, body);
        if (decorate) { err = decorate(err, body); }
        [self callOnMain:^{ completion(nil, err); }];
    }];
}

@end
