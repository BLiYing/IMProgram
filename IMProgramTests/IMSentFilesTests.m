#import <XCTest/XCTest.h>

#import "IMDatabase.h"
#import "IMFilePickerViewController.h"
#import "IMMessageModel.h"
#import "IMMediaUtil.h"
#import "UIViewController+IMPageLog.h"

@interface IMSentFilesTests : XCTestCase
@end

@implementation IMSentFilesTests

- (void)testPageLoggerNeverTouchesSystemDocumentPickerControllers {
    XCTAssertTrue(IMShouldLogPageClassName(@"IMFilePickerViewController"));
    XCTAssertFalse(IMShouldLogPageClassName(@"UIDocumentPickerViewController"));
    XCTAssertFalse(IMShouldLogPageClassName(@"DOCRemoteContainerViewController"));
    XCTAssertFalse(IMShouldLogPageClassName(@"DOCRemoteViewController"));
}

- (void)testSystemDocumentPickerUsesStableFullScreenBrowserPresentation {
    UIDocumentPickerViewController *picker = [IMFilePickerViewController systemDocumentPicker];

    XCTAssertEqual(picker.modalPresentationStyle, UIModalPresentationFullScreen);
    XCTAssertFalse(picker.allowsMultipleSelection);
    XCTAssertTrue(picker.shouldShowFileExtensions);
}

- (NSURL *)temporaryDatabaseURL {
    NSString *name = [NSString stringWithFormat:@"sent-files-%@.sqlite", NSUUID.UUID.UUIDString];
    return [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
}

- (void)testFileMetadataSurvivesModelAndSQLiteRoundTrip {
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
    message.fileSize = 7340032;
    message.timestamp = 1000;
    [database saveMessage:message];

    IMMessageModel *loaded = [database messagesForConv:message.convID].firstObject;
    XCTAssertEqualObjects(loaded.fileName, @"季度报表.xlsx");
    XCTAssertEqual(loaded.fileSize, 7340032);
    IMMessageModel *decoded = [IMMessageModel messageFromDictionary:message.dictionaryRepresentation];
    XCTAssertEqualObjects(decoded.fileName, @"季度报表.xlsx");
    XCTAssertEqual(decoded.fileSize, 7340032);
}

- (void)testServerSyncBackfillsFileSizeWithoutDuplicatingOptimisticMessage {
    NSURL *url = [self temporaryDatabaseURL];
    IMDatabase *database = [[IMDatabase alloc] initWithFileURL:url];
    [database useOwnerUserID:@"alice"];

    IMMessageModel *optimistic = [IMMessageModel new];
    optimistic.clientMsgID = @"client-1";
    optimistic.convID = @"u_alice_bob";
    optimistic.from = @"alice";
    optimistic.to = @"bob";
    optimistic.contentType = @"file";
    optimistic.content = @"/uploads/report.xlsx";
    optimistic.fileName = @"季度报表.xlsx";
    optimistic.fileSize = 0;
    optimistic.convSeq = 9;
    optimistic.timestamp = 900;
    optimistic.status = IMMessageStatusSent;
    [database saveMessage:optimistic];

    IMMessageModel *authoritative = [IMMessageModel receivedMessageWithNewMsgData:@{
        @"server_msg_id": @"server-9", @"conv_id": optimistic.convID, @"conv_seq": @9,
        @"from": @"alice", @"content_type": @"file", @"content": optimistic.content,
        @"file_name": @"季度报表.xlsx", @"file_size": @7340032, @"timestamp": @901,
    }];
    [database saveMessage:authoritative];

    NSArray<IMMessageModel *> *messages = [database messagesForConv:optimistic.convID];
    XCTAssertEqual(messages.count, 1);
    XCTAssertEqual(messages.firstObject.fileSize, 7340032);
    XCTAssertEqualObjects(messages.firstObject.fileName, @"季度报表.xlsx");
    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

- (void)testBackfilledHistoryUsesConversationSequenceOrder {
    NSURL *url = [self temporaryDatabaseURL];
    IMDatabase *database = [[IMDatabase alloc] initWithFileURL:url];
    [database useOwnerUserID:@"alice"];
    for (NSNumber *seq in @[@9, @7, @8]) {
        IMMessageModel *message = [IMMessageModel new];
        message.convID = @"u_alice_bob";
        message.from = @"bob";
        message.contentType = @"text";
        message.content = seq.stringValue;
        message.convSeq = seq.longLongValue;
        message.timestamp = seq.longLongValue;
        [database saveMessage:message];
    }
    NSArray<IMMessageModel *> *messages = [database messagesForConv:@"u_alice_bob"];
    XCTAssertEqualObjects([messages valueForKey:@"content"], (@[@"7", @"8", @"9"]));
    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

- (void)testSentFileCacheIsOwnerIsolatedAndDeduplicated {
    IMDatabase *database = [[IMDatabase alloc] initWithFileURL:[self temporaryDatabaseURL]];
    NSDictionary *file = @{
        @"server_msg_id": @"server-1", @"url": @"/uploads/one.pdf",
        @"name": @"合同.pdf", @"size": @2048, @"timestamp": @1000,
    };
    [database useOwnerUserID:@"alice"];
    [database cacheSentFiles:@[file]];
    [database cacheSentFiles:@[@{
        @"server_msg_id": @"server-authoritative", @"url": @"/uploads/one.pdf",
        @"name": @"合同.pdf", @"size": @4096, @"timestamp": @1000,
    }]];
    XCTAssertEqual([database cachedSentFiles].count, 1);
    NSDictionary *cached = [database cachedSentFiles].firstObject;
    XCTAssertEqualObjects(cached[@"name"], @"合同.pdf");
    XCTAssertEqualObjects(cached[@"server_msg_id"], @"server-authoritative");
    XCTAssertEqualObjects(cached[@"size"], @4096);

    [database useOwnerUserID:@"bob"];
    XCTAssertEqual([database cachedSentFiles].count, 0);
}

- (void)testFileMetadataFormattingUsesPersistedBytesAndMinutePrecision {
    XCTAssertEqualObjects(IMFormatFileSize(1024), @"1 KB");
    XCTAssertEqualObjects(IMFormatFileSize(1536), @"1.5 KB");
    XCTAssertEqualObjects(IMFormatFileSize(5 * 1024 * 1024), @"5 MB");
    XCTAssertEqualObjects(IMFormatFileSize((int64_t)(1.5 * 1024 * 1024 * 1024)), @"1.5 GB");
    XCTAssertEqualObjects(IMFormatFileSize(0), @"0 KB");

    NSString *dateTime = IMFormatFileDateTime(1700000000000);
    XCTAssertEqual(dateTime.length, 16);
    XCTAssertEqual([dateTime componentsSeparatedByString:@":"].count, 2);
}

@end
