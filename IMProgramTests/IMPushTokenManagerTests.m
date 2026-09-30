//  IMPushTokenManagerTests.m
//  纯函数：APNs device token → hex；embedded.mobileprovision 原始字节 → environment（M5）。
//  两者都不依赖网络/单例/真机签名包，用构造的样例数据驱动。

#import <XCTest/XCTest.h>

#import "../IMProgram/Network/IMPushTokenManager.h"

@interface IMPushTokenManagerTests : XCTestCase
@end

@implementation IMPushTokenManagerTests

#pragma mark - IMPushTokenHexFromData

- (void)testHexFromDataLowercaseAndZeroPadded {
    const unsigned char bytes[] = {0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x0F};
    NSData *data = [NSData dataWithBytes:bytes length:sizeof(bytes)];
    XCTAssertEqualObjects(IMPushTokenHexFromData(data), @"deadbeef000f");
}

- (void)testHexFromEmptyDataIsEmptyString {
    XCTAssertEqualObjects(IMPushTokenHexFromData([NSData data]), @"");
    XCTAssertEqualObjects(IMPushTokenHexFromData(nil), @"");
}

#pragma mark - IMPushEnvironmentFromMobileProvisionData

/// 构造一段「类 CMS」样例：前后各垫一些非 ASCII 二进制垃圾（模拟真实 mobileprovision 的签名信封），
/// 中间嵌一段合法 `<?xml … </plist>`，与真机文件的结构一致（PUSH_M5_DESIGN §1.1）。
- (NSData *)mobileProvisionDataWithApsEnvironment:(nullable NSString *)apsEnvironment {
    NSString *entitlementsXML = apsEnvironment.length > 0
        ? [NSString stringWithFormat:@"<key>Entitlements</key><dict><key>aps-environment</key><string>%@</string></dict>", apsEnvironment]
        : @"<key>Entitlements</key><dict><key>get-task-allow</key><false/></dict>"; // 无 aps-environment 字段
    NSString *plist = [NSString stringWithFormat:
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
         "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">"
         "<plist version=\"1.0\"><dict>%@</dict></plist>", entitlementsXML];
    NSMutableData *data = [NSMutableData data];
    const unsigned char junkPrefix[] = {0x30, 0x82, 0x0F, 0xFF, 0x00, 0x01, 0xA0, 0x82}; // 模拟 DER/CMS 二进制头
    [data appendBytes:junkPrefix length:sizeof(junkPrefix)];
    [data appendData:[plist dataUsingEncoding:NSISOLatin1StringEncoding]];
    const unsigned char junkSuffix[] = {0x00, 0xFF, 0x7E, 0x01};
    [data appendBytes:junkSuffix length:sizeof(junkSuffix)];
    return data;
}

- (void)testDevelopmentEntitlementMapsToSandbox {
    NSData *data = [self mobileProvisionDataWithApsEnvironment:@"development"];
    XCTAssertEqualObjects(IMPushEnvironmentFromMobileProvisionData(data), @"sandbox");
}

- (void)testProductionEntitlementMapsToProduction {
    NSData *data = [self mobileProvisionDataWithApsEnvironment:@"production"];
    XCTAssertEqualObjects(IMPushEnvironmentFromMobileProvisionData(data), @"production");
}

- (void)testMissingApsEnvironmentFieldFallsBackToProduction {
    NSData *data = [self mobileProvisionDataWithApsEnvironment:nil];
    XCTAssertEqualObjects(IMPushEnvironmentFromMobileProvisionData(data), @"production");
}

- (void)testEmptyDataFallsBackToProduction {
    XCTAssertEqualObjects(IMPushEnvironmentFromMobileProvisionData([NSData data]), @"production");
    XCTAssertEqualObjects(IMPushEnvironmentFromMobileProvisionData(nil), @"production");
}

- (void)testDataWithoutPlistMarkersFallsBackToProduction {
    // App Store 包没有这个文件时便利入口回 production；此处直接喂"看起来像文件但没有 <?xml>…</plist>"的字节。
    NSData *junk = [@"not a provisioning profile at all" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(IMPushEnvironmentFromMobileProvisionData(junk), @"production");
}

- (void)testTruncatedPlistBetweenMarkersFallsBackToProduction {
    // <?xml 存在但 </plist> 之前的内容不是合法 XML：解析失败应保守回退，而不是崩溃或误判 sandbox。
    NSData *broken = [@"<?xml version=\"1.0\"?><plist><dict><key>Entitlements" dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *withEnd = [broken mutableCopy];
    [withEnd appendData:[@"</plist>" dataUsingEncoding:NSUTF8StringEncoding]];
    XCTAssertEqualObjects(IMPushEnvironmentFromMobileProvisionData(withEnd), @"production");
}

@end
