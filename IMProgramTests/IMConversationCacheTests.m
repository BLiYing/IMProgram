#import <XCTest/XCTest.h>

#import "IMConversation.h"
#import "IMDatabase.h"
#import "IMMessageModel.h"

@interface IMConversationCacheTests : XCTestCase
@end

@implementation IMConversationCacheTests

- (NSURL *)temporaryDatabaseURL {
    NSString *name = [NSString stringWithFormat:@"im-test-%@.sqlite", NSUUID.UUID.UUIDString];
    return [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
}

- (IMConversation *)conversationWithID:(NSString *)convID peer:(NSString *)peer content:(NSString *)content {
    IMConversation *conversation = [IMConversation new];
    conversation.convID = convID;
    conversation.peer = peer;
    conversation.peerNickname = [@"昵称-" stringByAppendingString:peer];
    conversation.lastContent = content;
    conversation.lastContentType = @"text";
    conversation.latestConvSeq = 7;
    conversation.readSeq = 5;
    conversation.unread = 2;
    conversation.timestamp = 123456789;
    return conversation;
}

- (void)testConversationSnapshotPersistsAcrossDatabaseInstances {
    NSURL *url = [self temporaryDatabaseURL];
    IMDatabase *writer = [[IMDatabase alloc] initWithFileURL:url];
    [writer useOwnerUserID:@"alice"];
    IMConversation *conversation = [self conversationWithID:@"u_alice_bob" peer:@"bob" content:@"离线可见"];
    [writer replaceCachedConversations:@[conversation]];

    IMDatabase *reader = [[IMDatabase alloc] initWithFileURL:url];
    [reader useOwnerUserID:@"alice"];
    IMConversation *loaded = reader.cachedConversations.firstObject;

    XCTAssertEqual(reader.cachedConversations.count, 1);
    XCTAssertEqualObjects(loaded.convID, @"u_alice_bob");
    XCTAssertEqualObjects(loaded.peerNickname, @"昵称-bob");
    XCTAssertEqualObjects(loaded.lastContent, @"离线可见");
    XCTAssertEqual(loaded.unread, 2);
    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

- (void)testConversationAndMessagesAreIsolatedByOwner {
    NSURL *url = [self temporaryDatabaseURL];
    IMDatabase *database = [[IMDatabase alloc] initWithFileURL:url];

    [database useOwnerUserID:@"alice"];
    [database replaceCachedConversations:@[[self conversationWithID:@"alice-conv" peer:@"bob" content:@"A"]]];
    IMMessageModel *aliceMessage = [IMMessageModel new];
    aliceMessage.clientMsgID = @"same-client-id";
    aliceMessage.convID = @"shared-conv";
    aliceMessage.contentType = @"text";
    aliceMessage.content = @"alice-message";
    [database saveMessage:aliceMessage];

    [database useOwnerUserID:@"charlie"];
    XCTAssertEqual(database.cachedConversations.count, 0);
    XCTAssertEqual([database messagesForConv:@"shared-conv"].count, 0);
    [database replaceCachedConversations:@[[self conversationWithID:@"charlie-conv" peer:@"dave" content:@"C"]]];
    IMMessageModel *charlieMessage = [IMMessageModel new];
    charlieMessage.clientMsgID = @"same-client-id";
    charlieMessage.convID = @"shared-conv";
    charlieMessage.contentType = @"text";
    charlieMessage.content = @"charlie-message";
    [database saveMessage:charlieMessage];

    [database useOwnerUserID:@"alice"];
    XCTAssertEqualObjects(database.cachedConversations.firstObject.convID, @"alice-conv");
    XCTAssertEqualObjects([database messagesForConv:@"shared-conv"].firstObject.content, @"alice-message");
    [database useOwnerUserID:@"charlie"];
    XCTAssertEqualObjects(database.cachedConversations.firstObject.convID, @"charlie-conv");
    XCTAssertEqualObjects([database messagesForConv:@"shared-conv"].firstObject.content, @"charlie-message");
    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

- (void)testAuthoritativeEmptySnapshotClearsOnlyCurrentOwner {
    NSURL *url = [self temporaryDatabaseURL];
    IMDatabase *database = [[IMDatabase alloc] initWithFileURL:url];
    [database useOwnerUserID:@"alice"];
    [database replaceCachedConversations:@[[self conversationWithID:@"alice-conv" peer:@"bob" content:@"A"]]];
    [database useOwnerUserID:@"charlie"];
    [database replaceCachedConversations:@[[self conversationWithID:@"charlie-conv" peer:@"dave" content:@"C"]]];

    [database replaceCachedConversations:@[]];
    XCTAssertEqual(database.cachedConversations.count, 0);
    [database useOwnerUserID:@"alice"];
    XCTAssertEqual(database.cachedConversations.count, 1);
    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

- (void)testIncomingMessageUpdatesConversationOnceAndMovesItToFront {
    NSURL *url = [self temporaryDatabaseURL];
    IMDatabase *database = [[IMDatabase alloc] initWithFileURL:url];
    [database useOwnerUserID:@"alice"];
    IMConversation *older = [self conversationWithID:@"u_alice_carol" peer:@"carol" content:@"旧会话"];
    IMConversation *target = [self conversationWithID:@"u_alice_bob" peer:@"bob" content:@"旧消息"];
    target.unread = 0;
    [database replaceCachedConversations:@[older, target]];

    IMMessageModel *message = [IMMessageModel new];
    message.convID = target.convID;
    message.from = @"bob";
    message.contentType = @"text";
    message.content = @"离线新消息";
    message.convSeq = 8;
    message.timestamp = 223456789;
    message.status = IMMessageStatusReceived;
    [database saveMessage:message];
    [database saveMessage:message]; // new_msg 与聊天页重复落库不得重复加未读

    IMConversation *loaded = database.cachedConversations.firstObject;
    XCTAssertEqualObjects(loaded.convID, target.convID);
    XCTAssertEqualObjects(loaded.lastContent, @"离线新消息");
    XCTAssertEqual(loaded.latestConvSeq, 8);
    XCTAssertEqual(loaded.unread, 1);
    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

- (void)testMessageCreatesMinimalSingleAndGroupConversations {
    NSURL *url = [self temporaryDatabaseURL];
    IMDatabase *database = [[IMDatabase alloc] initWithFileURL:url];
    [database useOwnerUserID:@"alice"];

    IMMessageModel *single = [IMMessageModel new];
    single.convID = @"u_alice_bob";
    single.from = @"bob";
    single.contentType = @"image";
    single.content = @"/uploads/new.jpg";
    single.convSeq = 1;
    single.timestamp = 100;
    single.status = IMMessageStatusReceived;
    [database saveMessage:single];

    IMMessageModel *group = [IMMessageModel new];
    group.convID = @"g_new";
    group.from = @"carol";
    group.fromNickname = @"小卡";
    group.contentType = @"text";
    group.content = @"群消息";
    group.convSeq = 1;
    group.timestamp = 200;
    group.status = IMMessageStatusReceived;
    [database saveMessage:group];

    NSArray<IMConversation *> *loaded = database.cachedConversations;
    XCTAssertEqual(loaded.count, 2);
    XCTAssertEqualObjects(loaded[0].convID, @"g_new");
    XCTAssertTrue(loaded[0].isGroup);
    XCTAssertEqualObjects(loaded[0].name, @"群聊");
    XCTAssertEqualObjects(loaded[1].peer, @"bob");
    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

- (void)testOutgoingMessageUpdatesSummaryWithoutUnreadAndReadPositionPersists {
    NSURL *url = [self temporaryDatabaseURL];
    IMDatabase *database = [[IMDatabase alloc] initWithFileURL:url];
    [database useOwnerUserID:@"alice"];

    IMMessageModel *message = [IMMessageModel new];
    message.clientMsgID = @"out-1";
    message.convID = @"u_alice_bob";
    message.from = @"alice";
    message.to = @"bob";
    message.contentType = @"text";
    message.content = @"我发出的消息";
    message.timestamp = 300;
    message.status = IMMessageStatusSending;
    [database saveMessage:message];
    IMConversation *loaded = database.cachedConversations.firstObject;
    XCTAssertEqualObjects(loaded.lastContent, @"我发出的消息");
    XCTAssertEqual(loaded.unread, 0);

    message.convSeq = 9;
    message.status = IMMessageStatusSent;
    [database saveMessage:message];
    [database markConversation:message.convID readUpToConvSeq:9];
    loaded = database.cachedConversations.firstObject;
    XCTAssertEqual(loaded.latestConvSeq, 9);
    XCTAssertEqual(loaded.readSeq, 9);
    XCTAssertEqual(loaded.unread, 0);
    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

- (void)testServerSnapshotUnreadDoesNotDoubleWhenHistorySynchronizes {
    NSURL *url = [self temporaryDatabaseURL];
    IMDatabase *database = [[IMDatabase alloc] initWithFileURL:url];
    [database useOwnerUserID:@"alice"];
    IMConversation *conversation = [self conversationWithID:@"u_alice_bob" peer:@"bob" content:@"服务端最后一条"];
    conversation.latestConvSeq = 10;
    conversation.readSeq = 7;
    conversation.unread = 3;
    [database replaceCachedConversations:@[conversation]];

    for (int64_t seq = 8; seq <= 10; seq++) {
        IMMessageModel *message = [IMMessageModel new];
        message.convID = conversation.convID;
        message.from = @"bob";
        message.contentType = @"text";
        message.content = [NSString stringWithFormat:@"历史-%lld", seq];
        message.convSeq = seq;
        message.timestamp = seq;
        message.status = IMMessageStatusReceived;
        [database saveMessage:message];
    }

    XCTAssertEqual(database.cachedConversations.firstObject.unread, 3);
    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

- (void)testLocalGapMessagesAllIncreaseUnreadBeforeAuthoritativeSnapshot {
    NSURL *url = [self temporaryDatabaseURL];
    IMDatabase *database = [[IMDatabase alloc] initWithFileURL:url];
    [database useOwnerUserID:@"alice"];
    for (NSNumber *seqNumber in @[@10, @8, @9]) {
        IMMessageModel *message = [IMMessageModel new];
        message.convID = @"u_alice_bob";
        message.from = @"bob";
        message.contentType = @"text";
        message.content = @"乱序补拉";
        message.convSeq = seqNumber.longLongValue;
        message.timestamp = seqNumber.longLongValue;
        message.status = IMMessageStatusReceived;
        [database saveMessage:message];
    }

    IMConversation *loaded = database.cachedConversations.firstObject;
    XCTAssertEqual(loaded.latestConvSeq, 10);
    XCTAssertEqual(loaded.unread, 3);
    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

- (void)testReadPositionOnlySubtractsMessagesActuallyReadLocally {
    NSURL *url = [self temporaryDatabaseURL];
    IMDatabase *database = [[IMDatabase alloc] initWithFileURL:url];
    [database useOwnerUserID:@"alice"];
    IMConversation *conversation = [self conversationWithID:@"u_alice_bob" peer:@"bob" content:@"服务端摘要"];
    conversation.latestConvSeq = 10;
    conversation.readSeq = 5;
    conversation.unread = 5;
    [database replaceCachedConversations:@[conversation]];

    for (int64_t seq = 6; seq <= 7; seq++) {
        IMMessageModel *message = [IMMessageModel new];
        message.convID = conversation.convID;
        message.from = @"bob";
        message.contentType = @"text";
        message.content = @"已加载";
        message.convSeq = seq;
        message.timestamp = seq;
        message.status = IMMessageStatusReceived;
        [database saveMessage:message];
    }
    [database markConversation:conversation.convID readUpToConvSeq:6];

    IMConversation *loaded = database.cachedConversations.firstObject;
    XCTAssertEqual(loaded.readSeq, 6);
    XCTAssertEqual(loaded.unread, 4);
    [database markConversationFullyRead:conversation.convID upToConvSeq:10];
    loaded = database.cachedConversations.firstObject;
    XCTAssertEqual(loaded.readSeq, 10);
    XCTAssertEqual(loaded.unread, 0);
    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

- (void)testCarbonMessageCanCreateConversationFromConversationID {
    NSURL *url = [self temporaryDatabaseURL];
    IMDatabase *database = [[IMDatabase alloc] initWithFileURL:url];
    [database useOwnerUserID:@"alice"];
    IMMessageModel *message = [IMMessageModel new];
    message.convID = @"u_alice_u_bob_smith";
    message.from = @"alice";
    message.contentType = @"text";
    message.content = @"另一台设备发出";
    message.convSeq = 1;
    message.timestamp = 1;
    message.status = IMMessageStatusReceived;
    [database saveMessage:message];

    IMConversation *loaded = database.cachedConversations.firstObject;
    XCTAssertEqualObjects(loaded.peer, @"bob_smith");
    XCTAssertEqual(loaded.unread, 0);
    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

- (void)testMessageOperationUpdatesLastMessagePreview {
    NSURL *url = [self temporaryDatabaseURL];
    IMDatabase *database = [[IMDatabase alloc] initWithFileURL:url];
    [database useOwnerUserID:@"alice"];
    IMConversation *conversation = [self conversationWithID:@"u_alice_bob" peer:@"bob" content:@"编辑前"];
    conversation.latestConvSeq = 7;
    [database replaceCachedConversations:@[conversation]];
    IMMessageModel *message = [IMMessageModel new];
    message.convID = conversation.convID;
    message.from = @"bob";
    message.contentType = @"text";
    message.content = @"编辑前";
    message.convSeq = 7;
    message.status = IMMessageStatusReceived;
    [database saveMessage:message];

    [database applyMsgOpForConv:conversation.convID targetConvSeq:7 recalledAt:0 recalledBy:nil
                       editedAt:100 pinnedAt:0 newContent:@"编辑后"];
    XCTAssertEqualObjects(database.cachedConversations.firstObject.lastContent, @"编辑后");
    [database applyMsgOpForConv:conversation.convID targetConvSeq:7 recalledAt:200 recalledBy:@"bob"
                       editedAt:0 pinnedAt:0 newContent:nil];
    XCTAssertTrue(database.cachedConversations.firstObject.lastRecalled);
    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

- (void)testReceiptAndConversationSettingsPersistLocally {
    NSURL *url = [self temporaryDatabaseURL];
    IMDatabase *database = [[IMDatabase alloc] initWithFileURL:url];
    [database useOwnerUserID:@"alice"];
    IMConversation *conversation = [self conversationWithID:@"u_alice_bob" peer:@"bob" content:@"摘要"];
    [database replaceCachedConversations:@[conversation]];

    [database markConversation:conversation.convID peerReadUpToConvSeq:6];
    [database applyCachedSettingsForConversation:conversation.convID pinnedAt:99 muted:YES markedUnread:YES];
    IMConversation *loaded = database.cachedConversations.firstObject;
    XCTAssertEqual(loaded.peerReadSeq, 6);
    XCTAssertEqual(loaded.pinnedAt, 99);
    XCTAssertTrue(loaded.muted);
    XCTAssertTrue(loaded.markedUnread);

    [database deleteCachedConversation:conversation.convID];
    XCTAssertEqual(database.cachedConversations.count, 0);
    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

@end
