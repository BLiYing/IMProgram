//  IMChatViewController.m

#import "IMChatViewController.h"
#import "IMSocketManager.h"
#import "IMProtocol.h"
#import "IMMessageModel.h"
#import "IMDatabase.h"
#import "IMLog.h"

#pragma mark - 气泡 Cell

/// 私有消息气泡 Cell：自己的消息靠右（蓝），对方靠左（灰）。
/// 顶部可选「未读消息」分割线；自己的消息按对端已读位点显示 已送达/已读。
@interface IMBubbleCell : UITableViewCell
- (void)configureWithMessage:(IMMessageModel *)message
                        mine:(BOOL)mine
                 peerReadSeq:(int64_t)peerReadSeq
          showsUnreadDivider:(BOOL)showsDivider;
@end

@implementation IMBubbleCell {
    UILabel *_divider;
    NSLayoutConstraint *_dividerHeight;
    UILabel *_bubble;
    UILabel *_status;
    NSLayoutConstraint *_leading;
    NSLayoutConstraint *_trailing;
    NSLayoutConstraint *_statusLeading;
    NSLayoutConstraint *_statusTrailing;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = UIColor.clearColor;

        _divider = [UILabel new];
        _divider.translatesAutoresizingMaskIntoConstraints = NO;
        _divider.font = [UIFont systemFontOfSize:12];
        _divider.textColor = [UIColor colorWithRed:0.898 green:0.224 blue:0.208 alpha:1]; // #e53935
        _divider.textAlignment = NSTextAlignmentCenter;
        _divider.text = @"—— 未读消息 ——";
        _divider.clipsToBounds = YES;
        [self.contentView addSubview:_divider];

        _bubble = [UILabel new];
        _bubble.translatesAutoresizingMaskIntoConstraints = NO;
        _bubble.numberOfLines = 0;
        _bubble.layer.cornerRadius = 14;
        _bubble.layer.masksToBounds = YES;
        [self.contentView addSubview:_bubble];

        _status = [UILabel new];
        _status.translatesAutoresizingMaskIntoConstraints = NO;
        _status.font = [UIFont systemFontOfSize:11];
        _status.textColor = UIColor.secondaryLabelColor;
        [self.contentView addSubview:_status];

        _leading = [_bubble.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12];
        _trailing = [_bubble.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12];
        _statusLeading = [_status.leadingAnchor constraintEqualToAnchor:_bubble.leadingAnchor];
        _statusTrailing = [_status.trailingAnchor constraintEqualToAnchor:_bubble.trailingAnchor];
        _dividerHeight = [_divider.heightAnchor constraintEqualToConstant:0];
        [NSLayoutConstraint activateConstraints:@[
            [_divider.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_divider.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_divider.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            _dividerHeight,
            [_bubble.topAnchor constraintEqualToAnchor:_divider.bottomAnchor constant:6],
            [_bubble.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:0.72],
            [_status.topAnchor constraintEqualToAnchor:_bubble.bottomAnchor constant:2],
            [_status.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6],
        ]];
    }
    return self;
}

- (void)configureWithMessage:(IMMessageModel *)message
                        mine:(BOOL)mine
                 peerReadSeq:(int64_t)peerReadSeq
          showsUnreadDivider:(BOOL)showsDivider {
    _divider.hidden = !showsDivider;
    _dividerHeight.constant = showsDivider ? 28 : 0;

    // 气泡内文本两侧留白：用首尾空格近似 padding。
    _bubble.text = [NSString stringWithFormat:@"  %@  ", message.content];
    _bubble.backgroundColor = mine ? UIColor.systemBlueColor : UIColor.secondarySystemBackgroundColor;
    _bubble.textColor = mine ? UIColor.whiteColor : UIColor.labelColor;

    _leading.active = !mine;
    _trailing.active = mine;
    _status.textAlignment = mine ? NSTextAlignmentRight : NSTextAlignmentLeft;
    _status.text = mine ? [self statusTextFor:message peerReadSeq:peerReadSeq]
                        : [NSString stringWithFormat:@"来自 %@", message.from ?: @"?"];
    _statusLeading.active = !mine;
    _statusTrailing.active = mine;
}

- (NSString *)statusTextFor:(IMMessageModel *)message peerReadSeq:(int64_t)peerReadSeq {
    switch (message.status) {
        case IMMessageStatusSending: return @"发送中…";
        case IMMessageStatusFailed:  return @"发送失败 ✗";
        case IMMessageStatusSent:
            // 对端已读到本条 → 已读双勾；否则已送达单勾。
            if (message.convSeq > 0 && message.convSeq <= peerReadSeq) { return @"已读 ✓✓"; }
            return [NSString stringWithFormat:@"已送达 ✓ · seq#%lld", message.convSeq];
        default:                     return @"";
    }
}

@end

#pragma mark - 聊天页

@interface IMChatViewController () <IMSocketManagerDelegate, UITableViewDataSource, UITextFieldDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy) NSString *peerID;
@property (nonatomic, strong) NSMutableArray<IMMessageModel *> *messages;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *seenConvSeqs; // 按 conv_seq 去重，避免推送+同步重复
@property (nonatomic, copy) NSString *convID;
@property (nonatomic, assign) int64_t entryReadSeq;   // 进入前已读位点（定位未读分割线，进会话锁定一次）
@property (nonatomic, assign) NSInteger entryUnread;   // 进入时未读数
@property (nonatomic, assign) int64_t peerReadSeq;     // 对端已读位点（用于「已读」双勾）
@property (nonatomic, assign) BOOL peerOnline;         // 对端在线
@property (nonatomic, assign) IMSocketState connState; // 连接态（与在线点共同决定标题）
@property (nonatomic, assign) BOOL didInitialPosition; // 已做进会话定位（只定位一次）
@property (nonatomic, assign) NSTimeInterval lastTypingSent; // typing 节流
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UITextField *inputField;
@property (nonatomic, strong) NSLayoutConstraint *inputBottom;
@property (nonatomic, strong) UILabel *typingLabel;
@property (nonatomic, strong) NSLayoutConstraint *typingHeight;
@end

@implementation IMChatViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID peerID:(NSString *)peerID
                     readSeq:(int64_t)readSeq unread:(NSInteger)unread {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.hidesBottomBarWhenPushed = YES; // 进聊天页隐藏底部 TabBar（push 时全屏）
        _host = [host copy];
        _userID = [userID copy];
        _peerID = [peerID copy];
        _convID = IMConversationID(userID, peerID);
        _entryReadSeq = readSeq;
        _entryUnread = unread;
        // 本地落库：进入即秒显历史。
        _messages = [[IMDatabase.sharedDatabase messagesForConv:_convID] mutableCopy];
        _seenConvSeqs = [NSMutableSet set];
        for (IMMessageModel *m in _messages) {
            if (m.convSeq > 0) { [_seenConvSeqs addObject:@(m.convSeq)]; }
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.title = [NSString stringWithFormat:@"与 %@ 聊天", self.peerID];
    [self setupUI];
    [self observeKeyboard];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    IMSocketManager.sharedManager.delegate = self;
    [IMSocketManager.sharedManager connectToHost:self.host userID:self.userID];
    // 登记本会话：以本地已存最大 conv_seq 为同步起点（断点续传），自动增量拉回缺失消息。
    int64_t synced = [IMDatabase.sharedDatabase maxConvSeqForConv:self.convID];
    [IMSocketManager.sharedManager trackConversation:self.convID syncedSeq:synced];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self positionInitialIfNeeded]; // 进会话定位：有未读停首条未读，否则到底
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.isMovingFromParentViewController) {
        [IMSocketManager.sharedManager disconnect];
        if (IMSocketManager.sharedManager.delegate == self) {
            IMSocketManager.sharedManager.delegate = nil;
        }
    }
}

#pragma mark - UI

- (void)setupUI {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.allowsSelection = NO;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.tableView registerClass:IMBubbleCell.class forCellReuseIdentifier:@"bubble"];
    [self.view addSubview:self.tableView];

    // 「对方正在输入」提示条（默认高度 0，typing 时展开）。
    self.typingLabel = [UILabel new];
    self.typingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.typingLabel.font = [UIFont systemFontOfSize:12];
    self.typingLabel.textColor = UIColor.secondaryLabelColor;
    self.typingLabel.text = @"对方正在输入…";
    self.typingLabel.clipsToBounds = YES;
    [self.view addSubview:self.typingLabel];

    UIView *inputBar = [UIView new];
    inputBar.translatesAutoresizingMaskIntoConstraints = NO;
    inputBar.backgroundColor = UIColor.secondarySystemBackgroundColor;
    [self.view addSubview:inputBar];

    self.inputField = [UITextField new];
    self.inputField.translatesAutoresizingMaskIntoConstraints = NO;
    self.inputField.borderStyle = UITextBorderStyleRoundedRect;
    self.inputField.placeholder = @"输入消息…";
    self.inputField.returnKeyType = UIReturnKeySend;
    self.inputField.delegate = self;
    [self.inputField addTarget:self action:@selector(inputChanged) forControlEvents:UIControlEventEditingChanged];
    [inputBar addSubview:self.inputField];

    UIButton *sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    [sendButton setTitle:@"发送" forState:UIControlStateNormal];
    [sendButton addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
    [inputBar addSubview:sendButton];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    self.inputBottom = [inputBar.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor];
    self.typingHeight = [self.typingLabel.heightAnchor constraintEqualToConstant:0];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.typingLabel.topAnchor],

        [self.typingLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.typingLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.typingLabel.bottomAnchor constraintEqualToAnchor:inputBar.topAnchor],
        self.typingHeight,

        [inputBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [inputBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        self.inputBottom,
        [inputBar.heightAnchor constraintEqualToConstant:56],

        [self.inputField.leadingAnchor constraintEqualToAnchor:inputBar.leadingAnchor constant:12],
        [self.inputField.centerYAnchor constraintEqualToAnchor:inputBar.centerYAnchor],
        [self.inputField.trailingAnchor constraintEqualToAnchor:sendButton.leadingAnchor constant:-8],
        [sendButton.trailingAnchor constraintEqualToAnchor:inputBar.trailingAnchor constant:-12],
        [sendButton.centerYAnchor constraintEqualToAnchor:inputBar.centerYAnchor],
    ]];
}

#pragma mark - 发送 / 接收

/// 输入变化 → 发「正在输入」（2s 节流，避免每次按键都发）。
- (void)inputChanged {
    if (self.inputField.text.length == 0) { return; }
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (now - self.lastTypingSent > 2.0) {
        self.lastTypingSent = now;
        [IMSocketManager.sharedManager sendTypingForConv:self.convID];
    }
}

- (void)sendTapped {
    NSString *text = [self.inputField.text stringByTrimmingCharactersInSet:
                      NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (text.length == 0) { return; }

    __block NSString *clientMsgID = nil;
    __weak typeof(self) weakSelf = self;
    clientMsgID = [IMSocketManager.sharedManager sendText:text toUser:self.peerID
                                               completion:^(BOOL success, NSError *error, int64_t convSeq) {
        [weakSelf handleSendResult:success convSeq:convSeq forClientMsgID:clientMsgID];
    }];

    IMMessageModel *m = [IMMessageModel new];
    m.clientMsgID = clientMsgID;
    m.convID = self.convID;
    m.to = self.peerID;
    m.content = text;
    m.from = self.userID;
    m.contentType = @"text";
    m.status = IMMessageStatusSending;
    [IMDatabase.sharedDatabase saveMessage:m]; // 落库（sending）
    [self.messages addObject:m];
    self.inputField.text = @"";
    [self appendReloadAndScroll];
}

- (void)handleSendResult:(BOOL)success convSeq:(int64_t)convSeq forClientMsgID:(NSString *)clientMsgID {
    for (IMMessageModel *m in self.messages) {
        if ([m.clientMsgID isEqualToString:clientMsgID]) {
            m.status = success ? IMMessageStatusSent : IMMessageStatusFailed;
            m.convSeq = convSeq;
            [IMDatabase.sharedDatabase saveMessage:m]; // upsert：更新状态/conv_seq
            if (convSeq > 0) { [self.seenConvSeqs addObject:@(convSeq)]; } // 防 sync 重复回显自己发的
            break;
        }
    }
    [self.tableView reloadData];
}

#pragma mark - IMSocketManagerDelegate（主线程回调）

- (void)socketManager:(IMSocketManager *)manager didChangeState:(IMSocketState)state {
    self.connState = state;
    [self updateTitle];
    if (state == IMSocketStateConnected) {
        [self reportReadLatest]; // 连上后上报已读（打开即全部已读 + 对端看到已读双勾）
    }
}

/// 标题：在线点 + 对方 uid + 连接态。
- (void)updateTitle {
    NSString *dot = self.peerOnline ? @"🟢 " : @"";
    NSString *suffix = @"";
    switch (self.connState) {
        case IMSocketStateConnected:    suffix = self.peerOnline ? @"（在线）" : @""; break;
        case IMSocketStateConnecting:   suffix = @"（连接中…）"; break;
        case IMSocketStateDisconnected: suffix = @"（未连接）"; break;
    }
    self.title = [NSString stringWithFormat:@"%@%@%@", dot, self.peerID, suffix];
}

- (void)socketManager:(IMSocketManager *)manager didReceiveMessage:(IMMessageModel *)message {
    [IMDatabase.sharedDatabase saveMessage:message]; // 任何会话的消息都落库（按 conv_seq 幂等）
    if (![message.convID isEqualToString:self.convID]) { return; } // 非本会话不在此页显示
    // 同一条消息可能既被 new_msg 推送、又被 sync_resp 拉到，按 conv_seq 去重。
    if (message.convSeq > 0) {
        NSNumber *key = @(message.convSeq);
        if ([self.seenConvSeqs containsObject:key]) { return; }
        [self.seenConvSeqs addObject:key];
    }
    [self.messages addObject:message];
    [self appendReloadAndScroll];
    if (![message.from isEqualToString:self.userID]) { [self reportReadLatest]; } // 正在看 → 标记已读
}

/// 对端已读到 upToConvSeq → 记录并刷新（已送达 → 已读）。
- (void)socketManager:(IMSocketManager *)manager didReadConv:(NSString *)convID by:(NSString *)from upToConvSeq:(int64_t)convSeq {
    if (![convID isEqualToString:self.convID] || [from isEqualToString:self.userID]) { return; }
    if (convSeq > self.peerReadSeq) {
        self.peerReadSeq = convSeq;
        [self.tableView reloadData];
    }
}

/// 对端正在输入 → 展开提示条，3s 后自动收起。
- (void)socketManager:(IMSocketManager *)manager didTypingInConv:(NSString *)convID by:(NSString *)from {
    if (![convID isEqualToString:self.convID] || [from isEqualToString:self.userID]) { return; }
    self.typingHeight.constant = 20;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideTyping) object:nil];
    [self performSelector:@selector(hideTyping) withObject:nil afterDelay:3.0];
}

- (void)hideTyping {
    self.typingHeight.constant = 0;
}

/// 对端在线状态变化 → 更新标题在线点。
- (void)socketManager:(IMSocketManager *)manager didChangePresenceForUser:(NSString *)user online:(BOOL)online {
    if (![user isEqualToString:self.peerID]) { return; }
    self.peerOnline = online;
    [self updateTitle];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self sendTapped];
    return NO;
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.messages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMBubbleCell *cell = [tableView dequeueReusableCellWithIdentifier:@"bubble" forIndexPath:indexPath];
    IMMessageModel *m = self.messages[indexPath.row];
    BOOL mine = [m.from isEqualToString:self.userID];
    BOOL showsDivider = (indexPath.row == [self firstUnreadRow]);
    [cell configureWithMessage:m mine:mine peerReadSeq:self.peerReadSeq showsUnreadDivider:showsDivider];
    return cell;
}

/// 首条未读所在行：conv_seq > entryReadSeq 的第一条「对端」消息；无未读返回 -1。
- (NSInteger)firstUnreadRow {
    if (self.entryUnread <= 0) { return -1; }
    for (NSInteger i = 0; i < (NSInteger)self.messages.count; i++) {
        IMMessageModel *m = self.messages[i];
        if (m.convSeq > self.entryReadSeq && ![m.from isEqualToString:self.userID]) { return i; }
    }
    return -1;
}

/// 进会话定位（只做一次）：有未读则停在首条未读，否则到底（CHAT_UX §3）。
- (void)positionInitialIfNeeded {
    if (self.didInitialPosition || self.messages.count == 0) { return; }
    self.didInitialPosition = YES;
    NSInteger unreadRow = [self firstUnreadRow];
    NSInteger target = unreadRow >= 0 ? unreadRow : (NSInteger)self.messages.count - 1;
    UITableViewScrollPosition pos = unreadRow >= 0 ? UITableViewScrollPositionTop : UITableViewScrollPositionBottom;
    [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:target inSection:0]
                          atScrollPosition:pos animated:NO];
}

/// 上报已读到本会话最新位点（打开即全部已读：清未读 + 对端看到已读双勾）。
- (void)reportReadLatest {
    int64_t maxSeq = 0;
    for (IMMessageModel *m in self.messages) {
        if (![m.from isEqualToString:self.userID] && m.convSeq > maxSeq) { maxSeq = m.convSeq; }
    }
    if (maxSeq > 0) { [IMSocketManager.sharedManager markReadConv:self.convID upToConvSeq:maxSeq]; }
}

#pragma mark - 辅助

- (void)appendReloadAndScroll {
    [self.tableView reloadData];
    if (self.messages.count == 0) { return; }
    NSIndexPath *last = [NSIndexPath indexPathForRow:self.messages.count - 1 inSection:0];
    [self.tableView scrollToRowAtIndexPath:last atScrollPosition:UITableViewScrollPositionBottom animated:YES];
}

- (void)observeKeyboard {
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardWillChange:)
                                               name:UIKeyboardWillChangeFrameNotification object:nil];
}

- (void)keyboardWillChange:(NSNotification *)note {
    CGRect endFrame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat overlap = CGRectGetHeight(self.view.bounds) - [self.view convertRect:endFrame fromView:nil].origin.y;
    self.inputBottom.constant = -MAX(0, overlap - self.view.safeAreaInsets.bottom);
    [self.view layoutIfNeeded];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

@end
