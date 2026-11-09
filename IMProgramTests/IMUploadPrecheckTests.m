//  IMUploadPrecheckTests.m
//  S3a 上传策略的发送前预检（IMUploadPrecheck）与分片上传「策略拒绝不重启会话」判定。
//  钉死：判定顺序（开关 → 扩展名 → 大小，与服务端 upload_policy.go 同序）、语音只看开关、
//  扩展名大小写不敏感、体积未知不判大小、上限文案 GB / MB、500001/2/3 不换会话重传。

#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>

#import "../IMProgram/Common/IMUploadPrecheck.h"
#import "../IMProgram/Common/IMLocalization.h"
#import "../IMProgram/Common/UIViewController+IMToast.h"
#import "../IMProgram/Network/IMChunkedUploader.h"
#import "../IMProgram/Network/IMServerConfigStore.h"

/// 记 refresh 调用次数的替身（不发网络）。
@interface IMRefreshSpyConfigStore : IMServerConfigStore
@property (nonatomic, assign) NSInteger refreshCount;
@end
@implementation IMRefreshSpyConfigStore
- (void)refresh { self.refreshCount += 1; }
@end

// IMChatViewController+Compose.m 的文件级纯函数（同 IMChatSelectedMessages 的套路，免构造真 VC）。
FOUNDATION_EXPORT NSArray<NSData *> *_Nullable IMChatEncodePastedImagesForSend(NSArray<UIImage *> *images,
                                                                            NSString *_Nullable (^check)(long long bytes),
                                                                            NSString *_Nullable *_Nullable outReason);

static const long long kGiB = 1024LL * 1024 * 1024;
static const long long kMiB = 1024LL * 1024;

@interface IMUploadPrecheckTests : XCTestCase
@end

@implementation IMUploadPrecheckTests

- (NSArray<NSString *> *)blocked { return @[ @".exe", @".apk", @".sh" ]; }

#pragma mark - 判定

- (void)testAllowedPassesWithNil {
    XCTAssertNil(IMUploadPrecheckMessage(@"a.jpg", 10 * kMiB, NO, YES, 2 * kGiB, self.blocked));
    XCTAssertEqual(IMUploadPrecheckEvaluate(@"a.jpg", 10 * kMiB, NO, YES, 2 * kGiB, self.blocked), IMUploadPrecheckOK);
}

- (void)testDisabledWinsOverEverything {
    // 开关最先判：被禁扩展名 + 超限时也报「已暂停」（服务端 check 同序）。
    XCTAssertEqual(IMUploadPrecheckEvaluate(@"a.exe", 9 * kGiB, NO, NO, kGiB, self.blocked), IMUploadPrecheckDisabled);
    XCTAssertEqualObjects(IMUploadPrecheckMessage(@"a.jpg", 1, NO, NO, kGiB, nil), IMLocalized(@"err.500003"));
}

- (void)testBlockedExtensionCaseInsensitive {
    XCTAssertEqual(IMUploadPrecheckEvaluate(@"Setup.EXE", 1, NO, YES, kGiB, self.blocked), IMUploadPrecheckBlockedType);
    XCTAssertEqual(IMUploadPrecheckEvaluate(@"x.Apk", 0, NO, YES, kGiB, self.blocked), IMUploadPrecheckBlockedType);
    XCTAssertEqual(IMUploadPrecheckEvaluate(@"x.APK", 0, NO, YES, kGiB, @[ @".APK" ]), IMUploadPrecheckBlockedType);
    XCTAssertEqualObjects(IMUploadPrecheckMessage(@"a.sh", 1, NO, YES, kGiB, self.blocked),
                          IMLocalized(@"upload.precheck.blocked_type"));
}

- (void)testBlockedTypeCheckedBeforeSize {
    XCTAssertEqual(IMUploadPrecheckEvaluate(@"a.exe", 9 * kGiB, NO, YES, kGiB, self.blocked), IMUploadPrecheckBlockedType);
}

- (void)testNonBlockedOrNoExtensionPasses {
    XCTAssertEqual(IMUploadPrecheckEvaluate(@"readme", 1, NO, YES, kGiB, self.blocked), IMUploadPrecheckOK);
    XCTAssertEqual(IMUploadPrecheckEvaluate(@"exe.txt", 1, NO, YES, kGiB, self.blocked), IMUploadPrecheckOK);
    XCTAssertEqual(IMUploadPrecheckEvaluate(nil, 1, NO, YES, kGiB, self.blocked), IMUploadPrecheckOK);
    XCTAssertEqual(IMUploadPrecheckEvaluate(@"a.exe", 1, NO, YES, kGiB, @[]), IMUploadPrecheckOK, @"开关关着时列表为空");
    XCTAssertEqual(IMUploadPrecheckEvaluate(@"trailing.", 1, NO, YES, kGiB, self.blocked), IMUploadPrecheckOK);
}

- (void)testDotfileExtensionMatchesServer {
    // 服务端 filepath.Ext(".sh") == ".sh" → 500002；pathExtension 会给 ""，端上必须同口径拦下。
    XCTAssertEqual(IMUploadPrecheckEvaluate(@".sh", 1, NO, YES, kGiB, self.blocked), IMUploadPrecheckBlockedType);
    XCTAssertEqual(IMUploadPrecheckEvaluate(@"dir/.EXE", 1, NO, YES, kGiB, self.blocked), IMUploadPrecheckBlockedType);
}

- (void)testTooLargeBoundary {
    XCTAssertEqual(IMUploadPrecheckEvaluate(@"v.mp4", 100 * kMiB, NO, YES, 100 * kMiB, nil), IMUploadPrecheckOK, @"恰好等于上限放行");
    XCTAssertEqual(IMUploadPrecheckEvaluate(@"v.mp4", 100 * kMiB + 1, NO, YES, 100 * kMiB, nil), IMUploadPrecheckTooLarge);
    XCTAssertEqual(IMUploadPrecheckEvaluate(@"v.mp4", 0, NO, YES, 1, nil), IMUploadPrecheckOK, @"体积未知不判大小");
}

- (void)testNonPositiveMaxFallsBackTo2GiB {
    XCTAssertEqual(IMUploadPrecheckEvaluate(@"v.mp4", 2 * kGiB, NO, YES, 0, nil), IMUploadPrecheckOK);
    XCTAssertEqual(IMUploadPrecheckEvaluate(@"v.mp4", 2 * kGiB + 1, NO, YES, -1, nil), IMUploadPrecheckTooLarge);
    XCTAssertEqualObjects(IMUploadPrecheckMessage(@"v.mp4", 3 * kGiB, NO, YES, 0, nil),
                          IMLocalizedFormat(@"upload.precheck.too_large", @"2 GB"));
}

- (void)testVoiceOnlyChecksMasterSwitch {
    // 语音不吃扩展名与单文件上限（服务端另有固定 16 MB）。
    XCTAssertEqual(IMUploadPrecheckEvaluate(@"voice.exe", 9 * kGiB, YES, YES, kMiB, self.blocked), IMUploadPrecheckOK);
    XCTAssertEqual(IMUploadPrecheckEvaluate(@"voice.m4a", 1, YES, NO, kGiB, nil), IMUploadPrecheckDisabled);
    XCTAssertEqualObjects(IMUploadPrecheckMessage(@"voice.m4a", 1, YES, NO, kGiB, nil), IMLocalized(@"err.500003"));
}

#pragma mark - 文案

- (void)testTooLargeMessageCarriesFormattedLimit {
    NSString *msg = IMUploadPrecheckMessage(@"f.zip", 600 * kMiB, NO, YES, 500 * kMiB, nil);
    XCTAssertEqualObjects(msg, IMLocalizedFormat(@"upload.precheck.too_large", @"500 MB"));
    XCTAssertTrue([msg containsString:@"500 MB"], @"%@", msg);
}

- (void)testLimitLabel {
    XCTAssertEqualObjects(IMUploadLimitLabel(2 * kGiB), @"2 GB");
    XCTAssertEqualObjects(IMUploadLimitLabel(kGiB), @"1 GB");
    XCTAssertEqualObjects(IMUploadLimitLabel(10 * kGiB), @"10 GB");
    XCTAssertEqualObjects(IMUploadLimitLabel(1536 * kMiB), @"1536 MB", @"非 GiB 整数倍 → MB");
    XCTAssertEqualObjects(IMUploadLimitLabel(500 * kMiB), @"500 MB");
    XCTAssertEqualObjects(IMUploadLimitLabel(3 * kMiB / 2), @"1.5 MB", @"非整 MiB 保留一位小数（同服务端 uploadLimitLabel）");
    XCTAssertEqualObjects(IMUploadLimitLabel(500 * kMiB + 123), @"500.0 MB");
}

#pragma mark - 粘贴图：预检在清空输入栏之前（体积要 JPEG 编码后才知道）

static UIImage *SolidImage(CGFloat side) {
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat preferredFormat];
    f.scale = 1;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side) format:f]
        imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            [UIColor.redColor setFill];
            [ctx fillRect:CGRectMake(0, 0, side, side)];
        }];
}

/// 回归：粘贴图 + 配文、图编码后超限 → 旧实现先清空输入栏再在上传路径里拦，图和配文一起丢了。
/// 现在发送键入口先编码并预检，任一张不过就返回 nil（调用方据此原样保留输入栏），且检查拿到的是**编码后体积**。
- (void)testPastedImagesOverLimitRejectedBeforeAnythingIsCleared {
    NSMutableArray<NSNumber *> *seen = [NSMutableArray array];
    NSString *reason = nil;
    NSArray<NSData *> *out = IMChatEncodePastedImagesForSend(@[ SolidImage(64) ], ^NSString *(long long bytes) {
        [seen addObject:@(bytes)];
        return IMUploadPrecheckMessage(@"pasted.jpg", bytes, NO, YES, 1, nil); // 上限 1 字节：必超
    }, &reason);
    XCTAssertNil(out, @"超限必须整批不发");
    XCTAssertEqualObjects(reason, IMUploadPrecheckMessage(@"pasted.jpg", kGiB, NO, YES, 1, nil));
    XCTAssertNotNil(reason);
    XCTAssertEqual(seen.count, 1u);
    XCTAssertGreaterThan(seen.firstObject.longLongValue, 1, @"判的是 JPEG 编码后的真实体积，不是 0（未知）");
}

- (void)testPastedImagesPassReturnEncodedBytesInOrder {
    NSString *reason = nil;
    NSArray<UIImage *> *imgs = @[ SolidImage(16), SolidImage(48) ];
    NSArray<NSData *> *out = IMChatEncodePastedImagesForSend(imgs, ^NSString *(long long bytes) {
        return IMUploadPrecheckMessage(@"pasted.jpg", bytes, NO, YES, 2 * kGiB, nil);
    }, &reason);
    XCTAssertNil(reason);
    XCTAssertEqual(out.count, 2u);
    XCTAssertEqualObjects(out[0], UIImageJPEGRepresentation(imgs[0], 0.8), @"上传复用这份字节，免二次编码");
    XCTAssertEqualObjects(out[1], UIImageJPEGRepresentation(imgs[1], 0.8));
}

- (void)testPastedImagesDisabledSwitchRejects {
    NSString *reason = nil;
    NSArray<NSData *> *out = IMChatEncodePastedImagesForSend(@[ SolidImage(8), SolidImage(8) ], ^NSString *(long long bytes) {
        return IMUploadPrecheckMessage(@"pasted.jpg", bytes, NO, NO, 2 * kGiB, nil);
    }, &reason);
    XCTAssertNil(out);
    XCTAssertEqualObjects(reason, IMLocalized(@"err.500003"));
}

#pragma mark - 本地拦下即重拉配置（防过期缓存一直拦）

/// 回归：管理员关了上传又打开，端上缓存仍是 upload_enabled=false → 每次都在本地拦、请求到不了服务端，
/// 要等下次重连 / 回前台才自愈。现在每次本地拦下都触发 refresh（去重交给 refresh 自己）。
- (void)testLocalRejectionTriggersConfigRefresh {
    IMRefreshSpyConfigStore *s = [IMRefreshSpyConfigStore new];
    [s applyServerConfig:@{ @"upload_enabled": @NO }];
    XCTAssertEqualObjects(IMUploadPrecheckWithStore(s, @"a.jpg", 1, NO), IMLocalized(@"err.500003"));
    XCTAssertEqual(s.refreshCount, 1);

    [s applyServerConfig:@{ @"upload_max_file_bytes": @(kMiB), @"upload_blocked_extensions": @[ @".exe" ] }];
    XCTAssertNotNil(IMUploadPrecheckWithStore(s, @"a.exe", 1, NO));
    XCTAssertNotNil(IMUploadPrecheckWithStore(s, @"a.mp4", 2 * kMiB, NO));
    XCTAssertEqual(s.refreshCount, 3, @"类型被禁 / 超限同样可能是过期缓存");
}

- (void)testPassDoesNotTriggerRefresh {
    IMRefreshSpyConfigStore *s = [IMRefreshSpyConfigStore new];
    XCTAssertNil(IMUploadPrecheckWithStore(s, @"a.jpg", 1, NO));
    XCTAssertNil(IMUploadPrecheckWithStore(s, @"voice.m4a", 0, YES));
    XCTAssertEqual(s.refreshCount, 0, @"放行不额外请求");
}

#pragma mark - 策略拒绝码 / 分片不重启

- (NSError *)businessError:(NSInteger)code {
    // 与 IMHTTPService 的业务错误同形：domain = IMHTTPService、code > 0。
    return [NSError errorWithDomain:@"IMHTTPService" code:code userInfo:@{ NSLocalizedDescriptionKey: @"x" }];
}

- (void)testPolicyRejectionCodes {
    XCTAssertTrue(IMUploadIsPolicyRejectionCode(500001));
    XCTAssertTrue(IMUploadIsPolicyRejectionCode(500002));
    XCTAssertTrue(IMUploadIsPolicyRejectionCode(500003));
    XCTAssertFalse(IMUploadIsPolicyRejectionCode(100001));
    XCTAssertFalse(IMUploadIsPolicyRejectionCode(-1));
}

- (void)testChunkedUploaderDoesNotRestartOnPolicyRejection {
    for (NSNumber *code in @[ @500001, @500002, @500003 ]) {
        XCTAssertFalse([IMChunkedUploader shouldRestartSessionForError:[self businessError:code.integerValue] restartCount:0],
                       @"code %@ 换会话也一样被拒，不能重启", code);
    }
}

- (void)testChunkedUploaderStillRestartsOnSessionLost {
    NSError *lost = [self businessError:100001]; // 会话不存在 / 过期 / 非法 offset 一类
    XCTAssertTrue([IMChunkedUploader shouldRestartSessionForError:lost restartCount:0]);
    XCTAssertTrue([IMChunkedUploader shouldRestartSessionForError:lost restartCount:1]);
    XCTAssertFalse([IMChunkedUploader shouldRestartSessionForError:lost restartCount:2], @"最多重启 2 次");
}

- (void)testChunkedUploaderNetworkErrorIsNotARestart {
    NSError *net = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil];
    XCTAssertFalse([IMChunkedUploader shouldRestartSessionForError:net restartCount:0]);
    NSError *unknown = [NSError errorWithDomain:@"IMHTTPService" code:-1 userInfo:nil];
    XCTAssertFalse([IMChunkedUploader shouldRestartSessionForError:unknown restartCount:0]);
}

- (void)testToastDedupCollapsesBurst {
    NSString *last = nil; CFTimeInterval at = 0;
    XCTAssertTrue(IMToastDedup(@"A", 100.0, &last, &at, 1.0));   // 第一次弹
    XCTAssertFalse(IMToastDedup(@"A", 100.05, &last, &at, 1.0)); // 续传多条同时失败：不再弹
    XCTAssertFalse(IMToastDedup(@"A", 100.9, &last, &at, 1.0));
    XCTAssertTrue(IMToastDedup(@"B", 100.95, &last, &at, 1.0));  // 换一句：照弹
    XCTAssertTrue(IMToastDedup(@"A", 101.0, &last, &at, 1.0));
    XCTAssertTrue(IMToastDedup(@"A", 102.5, &last, &at, 1.0));   // 用户隔 1 秒以上手动重试：照弹
    XCTAssertTrue(IMToastDedup(@"A", 50.0, &last, &at, 1.0));    // 时钟倒退不吞
}

- (void)testServerRejectionMessageIsLocalized {
    NSArray *blocked = @[@".exe", @".apk"];
    XCTAssertEqualObjects(IMUploadServerRejectionMessage(500003, @"管理员已暂停发送文件", @"a.png", kGiB, blocked),
                          IMLocalized(@"err.500003"));
    XCTAssertEqualObjects(IMUploadServerRejectionMessage(500001, @"文件过大（上限 1GB）", @"a.zip", kGiB, blocked),
                          IMLocalizedFormat(@"upload.precheck.too_large", @"1 GB"));
    XCTAssertEqualObjects(IMUploadServerRejectionMessage(500002, @"管理员已禁止发送安装包和可执行文件", @"X.APK", kGiB, blocked),
                          IMLocalized(@"upload.precheck.blocked_type"));
    // 500002 但扩展名不在禁用表（本就不支持的格式）：保留服务端原文
    XCTAssertEqualObjects(IMUploadServerRejectionMessage(500002, @"不支持的文件格式", @"a.html", kGiB, blocked), @"不支持的文件格式");
    XCTAssertNil(IMUploadServerRejectionMessage(500002, nil, @"a.html", kGiB, blocked));
}

@end
