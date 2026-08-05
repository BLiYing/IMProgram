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

- (void)testContinuousSyncCursorIsOwnerIsolatedAndSurvivesSnapshotReplacement {
    NSURL *url = [self temporaryDatabaseURL];
    IMDatabase *database = [[IMDatabase alloc] initWithFileURL:url];

    [database useOwnerUserID:@"alice"];
    IMConversation *aliceConversation = [self conversationWithID:@"shared-conv" peer:@"bob" content:@"摘要"];
    [database replaceCachedConversations:@[aliceConversation]];
    // 本地偶然先收到 seq=9，不能把 9 当成“1～9 已连续同步”。
    IMMessageModel *sparse = [IMMessageModel new];
    sparse.convID = @"shared-conv";
    sparse.from = @"alice";
    sparse.contentType = @"text";
    sparse.content = @"较新消息";
    sparse.convSeq = 9;
    sparse.timestamp = 9;
    [database saveMessage:sparse];
    XCTAssertEqual([database maxConvSeqForConv:@"shared-conv"], 9);
    XCTAssertEqual([database syncedConvSeqForConv:@"shared-conv"], 0);

    [database advanceSyncedConvSeqForConv:@"shared-conv" toConvSeq:6];
    XCTAssertEqual([database syncedConvSeqForConv:@"shared-conv"], 6);
    [database replaceCachedConversations:@[aliceConversation]];
    XCTAssertEqual([database syncedConvSeqForConv:@"shared-conv"], 6);

    [database useOwnerUserID:@"charlie"];
    IMConversation *charlieConversation = [self conversationWithID:@"shared-conv" peer:@"dave" content:@"另一账号"];
    [database replaceCachedConversations:@[charlieConversation]];
    XCTAssertEqual([database syncedConvSeqForConv:@"shared-conv"], 0);
    [database advanceSyncedConvSeqForConv:@"shared-conv" toConvSeq:3];

    [database useOwnerUserID:@"alice"];
    XCTAssertEqual([database syncedConvSeqForConv:@"shared-conv"], 6);
    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

- (void)testIncomingMessageAndContinuousCursorCommitTogetherWithoutSkippingSparseMessage {
    NSURL *url = [self temporaryDatabaseURL];
    IMDatabase *database = [[IMDatabase alloc] initWithFileURL:url];
    [database useOwnerUserID:@"alice"];
    [database replaceCachedConversations:@[[self conversationWithID:@"u_alice_u_bob" peer:@"bob" content:@""]]];

    IMMessageModel *first = [IMMessageModel new];
    first.convID = @"u_alice_u_bob";
    first.from = @"bob";
    first.to = @"alice";
    first.contentType = @"text";
    first.content = @"one";
    first.convSeq = 1;
    first.timestamp = 1;
    XCTAssertTrue([database saveIncomingMessage:first advancingSyncedConvSeq:1]);

    IMMessageModel *sparse = [IMMessageModel new];
    sparse.convID = first.convID;
    sparse.from = @"bob";
    sparse.to = @"alice";
    sparse.contentType = @"text";
    sparse.content = @"three";
    sparse.convSeq = 3;
    sparse.timestamp = 3;
    XCTAssertTrue([database saveIncomingMessage:sparse advancingSyncedConvSeq:0]);

    XCTAssertEqual([database messagesForConv:first.convID].count, 2);
    XCTAssertEqual([database syncedConvSeqForConv:first.convID], 1);
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

// 消息按**时间戳**排序：被拒收的老消息（conv_seq=0，永远拿不到 conv_seq）必须落在真实时间位置，
// 不能被甩到收到的新消息（conv_seq>0）后面。回归 2026-08-05 复盘的时序 bug
//（1001↔1003 单向删除：1003 的拒收消息永久钉底、1001 的新消息插到上面，用户误以为没收到）。
// 与 im-web App.tsx 的 `timestamp || (convSeq||MAX)` 渲染排序逐条对齐。
- (void)testRejectedMessagesSortByTimestampNotPinnedToBottom {
    NSURL *url = [self temporaryDatabaseURL];
    IMDatabase *database = [[IMDatabase alloc] initWithFileURL:url];
    [database useOwnerUserID:@"1003"];
    NSString *conv = @"u_1001_u_1003";

    // 先发生：1003 发给 1001 两条，被本地拒收（conv_seq=0，failed，时间戳 100/200）。
    IMMessageModel *rej1 = [IMMessageModel new];
    rej1.convID = conv; rej1.clientMsgID = @"rej-1"; rej1.from = @"1003"; rej1.to = @"1001";
    rej1.contentType = @"text"; rej1.content = @"被拒1"; rej1.convSeq = 0; rej1.timestamp = 100;
    rej1.status = IMMessageStatusFailed; rej1.note = @"被对方拒收";
    [database saveMessage:rej1];

    IMMessageModel *rej2 = [IMMessageModel new];
    rej2.convID = conv; rej2.clientMsgID = @"rej-2"; rej2.from = @"1003"; rej2.to = @"1001";
    rej2.contentType = @"text"; rej2.content = @"被拒2"; rej2.convSeq = 0; rej2.timestamp = 200;
    rej2.status = IMMessageStatusFailed; rej2.note = @"被对方拒收";
    [database saveMessage:rej2];

    // 后发生：1001 发给 1003 两条，正常收到（conv_seq 5/6，时间戳 300/400）。
    IMMessageModel *rcv1 = [IMMessageModel new];
    rcv1.convID = conv; rcv1.from = @"1001"; rcv1.to = @"1003";
    rcv1.contentType = @"text"; rcv1.content = @"收到1"; rcv1.convSeq = 5; rcv1.timestamp = 300;
    rcv1.status = IMMessageStatusReceived;
    [database saveMessage:rcv1];

    IMMessageModel *rcv2 = [IMMessageModel new];
    rcv2.convID = conv; rcv2.from = @"1001"; rcv2.to = @"1003";
    rcv2.contentType = @"text"; rcv2.content = @"收到2"; rcv2.convSeq = 6; rcv2.timestamp = 400;
    rcv2.status = IMMessageStatusReceived;
    [database saveMessage:rcv2];

    NSArray<IMMessageModel *> *msgs = [database messagesForConv:conv];
    NSArray<NSString *> *contents = [msgs valueForKey:@"content"];
    // 期望严格按时间戳：被拒的老消息在前，收到的新消息在后（底部=最新）。
    NSArray<NSString *> *want = @[@"被拒1", @"被拒2", @"收到1", @"收到2"];
    XCTAssertEqualObjects(contents, want, @"应按时间戳排序，拒收老消息不得被钉到收到消息之后");

    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

// 同一毫秒时：待发/失败（conv_seq=0）视为最大值垫底，收到的（conv_seq>0）在前
// —— 保住「刚发出的临时消息在底部」原意，等价 im-web 的 `convSeq || MAX_SAFE_INTEGER`。
- (void)testSameTimestampPendingSortsAfterAcked {
    NSURL *url = [self temporaryDatabaseURL];
    IMDatabase *database = [[IMDatabase alloc] initWithFileURL:url];
    [database useOwnerUserID:@"1003"];
    NSString *conv = @"u_1001_u_1003";

    IMMessageModel *pending = [IMMessageModel new]; // 刚发出、还没 ack
    pending.convID = conv; pending.clientMsgID = @"p-1"; pending.from = @"1003"; pending.to = @"1001";
    pending.contentType = @"text"; pending.content = @"待发"; pending.convSeq = 0; pending.timestamp = 500;
    pending.status = IMMessageStatusSending;
    [database saveMessage:pending];

    IMMessageModel *acked = [IMMessageModel new]; // 同一毫秒的已确认消息
    acked.convID = conv; acked.from = @"1001"; acked.to = @"1003";
    acked.contentType = @"text"; acked.content = @"已确认"; acked.convSeq = 9; acked.timestamp = 500;
    acked.status = IMMessageStatusReceived;
    [database saveMessage:acked];

    NSArray<NSString *> *contents = [[database messagesForConv:conv] valueForKey:@"content"];
    XCTAssertEqualObjects(contents, (@[@"已确认", @"待发"]), @"同毫秒时 conv_seq=0 垫底");

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

- (void)testReactivatingSameOwnerInvalidatesPreviousLoginContext {
    NSURL *url = [self temporaryDatabaseURL];
    IMDatabase *database = [[IMDatabase alloc] initWithFileURL:url];

    IMDatabaseAccountContext *first = [database useOwnerUserID:@" alice "];
    IMDatabaseAccountContext *second = [database useOwnerUserID:@"alice"];

    XCTAssertNotNil(first);
    XCTAssertNotEqual(first, second);
    XCTAssertEqualObjects(first.ownerUserID, @"alice");
    XCTAssertEqual(database.currentAccountContext, second);
    __block BOOL executed = NO;
    XCTAssertFalse([database performWithAccountContext:first block:^(IMDatabase *db) {
        (void)db;
        executed = YES;
    }]);
    XCTAssertFalse(executed);
    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

- (void)testStaleAccountContextCannotWriteAfterAToBToA {
    NSURL *url = [self temporaryDatabaseURL];
    IMDatabase *database = [[IMDatabase alloc] initWithFileURL:url];
    IMDatabaseAccountContext *firstAlice = [database useOwnerUserID:@"alice"];

    IMMessageModel *aliceBase = [IMMessageModel new];
    aliceBase.clientMsgID = @"alice-base";
    aliceBase.convID = @"shared-conv";
    aliceBase.contentType = @"text";
    aliceBase.content = @"first activation";
    XCTAssertTrue([database performWithAccountContext:firstAlice block:^(IMDatabase *db) {
        [db saveMessage:aliceBase];
    }]);

    IMDatabaseAccountContext *bob = [database useOwnerUserID:@"bob"];
    IMMessageModel *lateAlice = [IMMessageModel new];
    lateAlice.clientMsgID = @"late-alice";
    lateAlice.convID = @"shared-conv";
    lateAlice.contentType = @"text";
    lateAlice.content = @"must be rejected";
    XCTAssertFalse([database performWithAccountContext:firstAlice block:^(IMDatabase *db) {
        [db saveMessage:lateAlice];
    }]);
    XCTAssertEqual([database messagesForConv:@"shared-conv"].count, 0);

    IMMessageModel *bobMessage = [IMMessageModel new];
    bobMessage.clientMsgID = @"bob-current";
    bobMessage.convID = @"shared-conv";
    bobMessage.contentType = @"text";
    bobMessage.content = @"bob";
    XCTAssertTrue([database performWithAccountContext:bob block:^(IMDatabase *db) {
        [db saveMessage:bobMessage];
    }]);

    IMDatabaseAccountContext *secondAlice = [database useOwnerUserID:@"alice"];
    XCTAssertNotEqual(firstAlice, secondAlice);
    XCTAssertFalse([database performWithAccountContext:firstAlice block:^(IMDatabase *db) {
        [db saveMessage:lateAlice];
    }]);
    NSArray<IMMessageModel *> *aliceMessages = [database messagesForConv:@"shared-conv"];
    XCTAssertEqual(aliceMessages.count, 1);
    XCTAssertEqualObjects(aliceMessages.firstObject.content, @"first activation");
    IMMessageModel *secondAliceMessage = [IMMessageModel new];
    secondAliceMessage.clientMsgID = @"second-alice";
    secondAliceMessage.convID = @"shared-conv";
    secondAliceMessage.contentType = @"text";
    secondAliceMessage.content = @"second activation";
    XCTAssertTrue([database performWithAccountContext:secondAlice block:^(IMDatabase *db) {
        [db saveMessage:secondAliceMessage];
    }]);
    XCTAssertEqual([database messagesForConv:@"shared-conv"].count, 2);
    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

- (void)testAccountSwitchWaitsForValidatedContextOperation {
    NSURL *url = [self temporaryDatabaseURL];
    IMDatabase *database = [[IMDatabase alloc] initWithFileURL:url];
    IMDatabaseAccountContext *alice = [database useOwnerUserID:@"alice"];
    dispatch_semaphore_t operationEntered = dispatch_semaphore_create(0);
    dispatch_semaphore_t releaseOperation = dispatch_semaphore_create(0);
    dispatch_semaphore_t operationFinished = dispatch_semaphore_create(0);
    dispatch_semaphore_t switchStarted = dispatch_semaphore_create(0);
    dispatch_semaphore_t switchFinished = dispatch_semaphore_create(0);

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [database performWithAccountContext:alice block:^(IMDatabase *db) {
            dispatch_semaphore_signal(operationEntered);
            dispatch_semaphore_wait(releaseOperation,
                                    dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NSEC_PER_SEC)));
            IMMessageModel *message = [IMMessageModel new];
            message.clientMsgID = @"linearized-a";
            message.convID = @"shared-conv";
            message.contentType = @"text";
            message.content = @"alice";
            [db saveMessage:message];
        }];
        dispatch_semaphore_signal(operationFinished);
    });
    XCTAssertEqual(dispatch_semaphore_wait(operationEntered,
                                           dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NSEC_PER_SEC))), 0);

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        dispatch_semaphore_signal(switchStarted);
        [database useOwnerUserID:@"bob"];
        dispatch_semaphore_signal(switchFinished);
    });
    XCTAssertEqual(dispatch_semaphore_wait(switchStarted,
                                           dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NSEC_PER_SEC))), 0);
    XCTAssertNotEqual(dispatch_semaphore_wait(switchFinished,
                                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC))), 0);
    dispatch_semaphore_signal(releaseOperation);
    XCTAssertEqual(dispatch_semaphore_wait(operationFinished,
                                           dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NSEC_PER_SEC))), 0);
    XCTAssertEqual(dispatch_semaphore_wait(switchFinished,
                                           dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NSEC_PER_SEC))), 0);

    XCTAssertEqual([database messagesForConv:@"shared-conv"].count, 0);
    [database useOwnerUserID:@"alice"];
    XCTAssertEqualObjects([database messagesForConv:@"shared-conv"].firstObject.content, @"alice");
    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

- (void)testAccountContextCannotBeUsedWithAnotherDatabaseInstance {
    NSURL *firstURL = [self temporaryDatabaseURL];
    NSURL *secondURL = [self temporaryDatabaseURL];
    IMDatabase *firstDatabase = [[IMDatabase alloc] initWithFileURL:firstURL];
    IMDatabase *secondDatabase = [[IMDatabase alloc] initWithFileURL:secondURL];
    IMDatabaseAccountContext *foreignContext = [firstDatabase useOwnerUserID:@"alice"];
    [secondDatabase useOwnerUserID:@"alice"];

    __block BOOL executed = NO;
    XCTAssertFalse([secondDatabase performWithAccountContext:foreignContext block:^(IMDatabase *db) {
        (void)db;
        executed = YES;
    }]);
    XCTAssertFalse(executed);
    [NSFileManager.defaultManager removeItemAtURL:firstURL error:NULL];
    [NSFileManager.defaultManager removeItemAtURL:secondURL error:NULL];
}

@end
