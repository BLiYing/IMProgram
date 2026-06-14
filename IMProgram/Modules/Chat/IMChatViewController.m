//  IMChatViewController.m

#import "IMChatViewController.h"
#import "IMSocketManager.h"
#import "IMProtocol.h"
#import "IMMessageModel.h"
#import "IMDatabase.h"
#import "IMLog.h"

#pragma mark - 气泡 Cell

/// 私有消息气泡 Cell：自己的消息靠右（蓝），对方靠左（灰）。
@interface IMBubbleCell : UITableViewCell
- (void)configureWithMessage:(IMMessageModel *)message mine:(BOOL)mine;
@end

@implementation IMBubbleCell {
    UILabel *_bubble;
    UILabel *_status;
    NSLayoutConstraint *_leading;
    NSLayoutConstraint *_trailing;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = UIColor.clearColor;

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
        [NSLayoutConstraint activateConstraints:@[
            [_bubble.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
            [_bubble.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:0.72],
            [_status.topAnchor constraintEqualToAnchor:_bubble.bottomAnchor constant:2],
            [_status.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6],
        ]];
    }
    return self;
}

- (void)configureWithMessage:(IMMessageModel *)message mine:(BOOL)mine {
    // 气泡内文本两侧留白：用 padding 属性化字符串近似实现。
    _bubble.text = [NSString stringWithFormat:@"  %@  ", message.content];
    _bubble.backgroundColor = mine ? UIColor.systemBlueColor : UIColor.secondarySystemBackgroundColor;
    _bubble.textColor = mine ? UIColor.whiteColor : UIColor.labelColor;

    _leading.active = !mine;
    _trailing.active = mine;
    _status.textAlignment = mine ? NSTextAlignmentRight : NSTextAlignmentLeft;
    _status.text = mine ? [self statusTextFor:message] : [NSString stringWithFormat:@"来自 %@", message.from ?: @"?"];

    if (mine) {
        [_status.trailingAnchor constraintEqualToAnchor:_bubble.trailingAnchor].active = YES;
    } else {
        [_status.leadingAnchor constraintEqualToAnchor:_bubble.leadingAnchor].active = YES;
    }
}

- (NSString *)statusTextFor:(IMMessageModel *)message {
    switch (message.status) {
        case IMMessageStatusSending: return @"发送中…";
        case IMMessageStatusSent:    return [NSString stringWithFormat:@"已送达 ✓ · seq#%lld", message.convSeq];
        case IMMessageStatusFailed:  return @"发送失败 ✗";
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
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UITextField *inputField;
@property (nonatomic, strong) NSLayoutConstraint *inputBottom;
@end

@implementation IMChatViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID peerID:(NSString *)peerID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy];
        _userID = [userID copy];
        _peerID = [peerID copy];
        _convID = IMConversationID(userID, peerID);
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
    [inputBar addSubview:self.inputField];

    UIButton *sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    [sendButton setTitle:@"发送" forState:UIControlStateNormal];
    [sendButton addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
    [inputBar addSubview:sendButton];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    self.inputBottom = [inputBar.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:inputBar.topAnchor],

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
    NSString *suffix = @"";
    switch (state) {
        case IMSocketStateConnected:    suffix = @"（已连接）"; break;
        case IMSocketStateConnecting:   suffix = @"（连接中…）"; break;
        case IMSocketStateDisconnected: suffix = @"（未连接）"; break;
    }
    self.title = [NSString stringWithFormat:@"与 %@ 聊天%@", self.peerID, suffix];
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
    [cell configureWithMessage:m mine:mine];
    return cell;
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
}

@end
