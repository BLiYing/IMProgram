//  IMForwardPickerViewController.m

#import "IMForwardPickerViewController.h"
#import "IMHTTPService.h"
#import "IMConversation.h"
#import "UIViewController+IMToast.h"

static const NSUInteger kIMForwardMaxSelection = 9;

@interface IMForwardPickerViewController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation IMForwardPickerViewController {
    NSString *_host;
    NSString *_token;
    void (^_onDone)(NSArray<IMConversation *> *);
    NSArray<IMConversation *> *_convs;
    NSMutableArray<IMConversation *> *_selected; // 多选顺序集
    BOOL _multiSelect;
    UITableView *_tableView;
}

- (instancetype)initWithHost:(NSString *)host token:(NSString *)token onDone:(void (^)(NSArray<IMConversation *> *))onDone {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _host = [host copy];
        _token = [token copy];
        _onDone = [onDone copy];
        _selected = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"转发到";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelTapped)];
    [self updateRightButton];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [_tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"conv"];
    [self.view addSubview:_tableView];

    [self loadConversations];
}

- (void)loadConversations {
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService conversationsWithToken:_token completion:^(NSArray<IMConversation *> *convs, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error || convs.count == 0) {
            [self im_showToast:error ? @"加载会话失败" : @"暂无可转发的会话"];
            return;
        }
        self->_convs = convs;
        [self->_tableView reloadData];
    }];
}

#pragma mark - 单选 / 多选切换

- (void)updateRightButton {
    if (_multiSelect) {
        NSString *title = _selected.count > 0 ? [NSString stringWithFormat:@"发送(%lu)", (unsigned long)_selected.count] : @"发送";
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithTitle:title style:UIBarButtonItemStyleDone target:self action:@selector(sendTapped)];
        self.navigationItem.rightBarButtonItem.enabled = _selected.count > 0;
    } else {
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithTitle:@"多选" style:UIBarButtonItemStylePlain target:self action:@selector(enterMultiSelect)];
    }
}

- (void)enterMultiSelect {
    _multiSelect = YES;
    [self updateRightButton];
    [_tableView reloadData];
}

- (void)cancelTapped { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)sendTapped {
    if (_selected.count == 0) { return; }
    NSArray<IMConversation *> *result = [_selected copy];
    void (^done)(NSArray<IMConversation *> *) = _onDone;
    [self dismissViewControllerAnimated:YES completion:^{ if (done) { done(result); } }];
}

#pragma mark - 展示

- (NSString *)displayNameFor:(IMConversation *)c {
    if (c.isGroup) { return c.name.length > 0 ? c.name : @"群聊"; }
    return c.peerNickname.length > 0 ? c.peerNickname : (c.peer ?: @"");
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return _convs.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"conv" forIndexPath:ip];
    IMConversation *c = _convs[ip.row];
    cell.textLabel.text = [self displayNameFor:c];
    if (_multiSelect) {
        cell.accessoryType = [_selected containsObject:c] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    } else {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tableView deselectRowAtIndexPath:ip animated:YES];
    IMConversation *c = _convs[ip.row];
    if (!_multiSelect) { // 单选：确认后立即回调
        __weak typeof(self) ws = self;
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"转发"
            message:[NSString stringWithFormat:@"发送给「%@」？", [self displayNameFor:c]]
            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:@"发送" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            __strong typeof(ws) self = ws;
            void (^done)(NSArray<IMConversation *> *) = self->_onDone;
            [self dismissViewControllerAnimated:YES completion:^{ if (done) { done(@[c]); } }];
        }]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    // 多选：切换选中，上限 9。
    if ([_selected containsObject:c]) {
        [_selected removeObject:c];
    } else {
        if (_selected.count >= kIMForwardMaxSelection) {
            [self im_showToast:[NSString stringWithFormat:@"最多选择 %lu 个会话", (unsigned long)kIMForwardMaxSelection]];
            return;
        }
        [_selected addObject:c];
    }
    [tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
    [self updateRightButton];
}

@end
