#import <XCTest/XCTest.h>

#import "IMDatabase.h"
#import "IMMessageModel.h"

@interface IMSentFilesTests : XCTestCase
@end

@implementation IMSentFilesTests

- (NSURL *)temporaryDatabaseURL {
    NSString *name = [NSString stringWithFormat:@"sent-files-%@.sqlite", NSUUID.UUID.UUIDString];
    return [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
}

- (void)testFileNameSurvivesModelAndSQLiteRoundTrip {
    NSURL *url = [self temporaryDatabaseURL];
    IMDatabase *database = [[IMDatabase alloc] initWithFileURL:url];
    [database useOwnerUserID:@"alice"];
    IMMessageModel *message = [IMMessageModel new];
    message.clientMsgID = @"client-1";
    message.convID = @"u_alice_bob";
    message.from = @"alice";
    message.to = @"bob";
    message.contentType = @"file";
    message.content = @"/uploads/random-id.xlsx";
    message.fileName = @"季度报表.xlsx";
    message.timestamp = 1000;
    [database saveMessage:message];

    IMMessageModel *loaded = [database messagesForConv:message.convID].firstObject;
    XCTAssertEqualObjects(loaded.fileName, @"季度报表.xlsx");
    XCTAssertEqualObjects([IMMessageModel messageFromDictionary:message.dictionaryRepresentation].fileName,
                          @"季度报表.xlsx");
}

- (void)testSentFileCacheIsOwnerIsolatedAndDeduplicated {
    IMDatabase *database = [[IMDatabase alloc] initWithFileURL:[self temporaryDatabaseURL]];
    NSDictionary *file = @{
        @"server_msg_id": @"server-1", @"url": @"/uploads/one.pdf",
        @"name": @"合同.pdf", @"timestamp": @1000,
    };
    [database useOwnerUserID:@"alice"];
    [database cacheSentFiles:@[file]];
    [database cacheSentFiles:@[@{
        @"server_msg_id": @"server-authoritative", @"url": @"/uploads/one.pdf",
        @"name": @"合同.pdf", @"timestamp": @1000,
    }]];
    XCTAssertEqual([database cachedSentFiles].count, 1);
    NSDictionary *cached = [database cachedSentFiles].firstObject;
    XCTAssertEqualObjects(cached[@"name"], @"合同.pdf");
    XCTAssertEqualObjects(cached[@"server_msg_id"], @"server-authoritative");

    [database useOwnerUserID:@"bob"];
    XCTAssertEqual([database cachedSentFiles].count, 0);
}

@end
