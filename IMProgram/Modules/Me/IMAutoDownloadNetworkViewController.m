//  IMAutoDownloadNetworkViewController.m

#import "IMAutoDownloadNetworkViewController.h"
#import "IMDownloadSettingsUI.h"
#import "IMDownloadSettingsStore.h"

@interface IMAutoDownloadNetworkViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation IMAutoDownloadNetworkViewController {
    IMDownloadNetworkKind _net;
    IMDownloadSettings *_working;
    __weak UILabel *_presetLabel; // "流量使用情况：中"
}

- (instancetype)initWithNetwork:(IMDownloadNetworkKind)network {
    if ((self = [super initWithNibName:nil bundle:nil])) { _net = network; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = IMDownloadNetworkTitle(_net);
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reloadFromStore)
                                               name:IMDownloadSettingsDidChangeNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reloadFromStore]; }

- (void)reloadFromStore {
    _working = [[IMDownloadSettingsStore shared].settings deepCopy];
    [self.tableView reloadData];
}

- (IMDownloadNetworkPolicy *)policy { return IMPolicyForNetwork(_working, _net); }

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 2 ? 3 : 1; // 0: 总开关；1: 档位滑块；2: 图片/视频/文件
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 1) { return @"流量档位"; }
    if (section == 2) { return @"媒体文件类型"; }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1) { return @"“低”只自动下图片，视频/文件手动；“中/高”自动下更大的视频与文件。可进各类微调。"; }
    if (section == 2) { return @"语音消息占用小，始终自动下载。"; }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMDownloadNetworkPolicy *p = [self policy];
    if (indexPath.section == 0) { // 总开关
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = @"自动下载媒体文件";
        UISwitch *sw = [UISwitch new];
        sw.on = p.enabled;
        [sw addTarget:self action:@selector(masterSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        return cell;
    }
    if (indexPath.section == 1) { // 低/中/高
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        NSArray<NSString *> *names = @[ @"低", @"中", @"高" ];
        NSInteger preset = IMTrafficPresetForPolicy(p);
        UILabel *title = [[UILabel alloc] init];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        title.font = [UIFont systemFontOfSize:15];
        title.text = [@"流量使用情况：" stringByAppendingString:names[preset]];
        _presetLabel = title;
        UISlider *slider = [[UISlider alloc] init];
        slider.translatesAutoresizingMaskIntoConstraints = NO;
        slider.minimumValue = 0;
        slider.maximumValue = 2;
        slider.value = (float)preset;
        [slider addTarget:self action:@selector(presetSliderChanged:) forControlEvents:UIControlEventValueChanged];
        [slider addTarget:self action:@selector(presetSliderCommitted:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
        [cell.contentView addSubview:title];
        [cell.contentView addSubview:slider];
        [NSLayoutConstraint activateConstraints:@[
            [title.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
            [title.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:10],
            [slider.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
            [slider.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
            [slider.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8],
            [slider.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-10],
        ]];
        return cell;
    }
    // 类别入口
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    IMDownloadCategoryKind cat = (IMDownloadCategoryKind)indexPath.row;
    cell.textLabel.text = IMDownloadCategoryName(cat);
    if (cat == IMDownloadCategoryImage) {
        cell.detailTextLabel.text = @"对所有聊天启用";
    } else {
        IMDownloadCategoryRule *r = IMRuleForCategory(p, cat);
        cell.detailTextLabel.text = [@"最大 " stringByAppendingString:IMDownloadSizeLabel(r.maxBytes)];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 2) { return; }
    IMAutoDownloadCategoryViewController *vc = [[IMAutoDownloadCategoryViewController alloc]
        initWithNetwork:_net category:(IMDownloadCategoryKind)indexPath.row];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - 编辑 → 保存

- (void)masterSwitchChanged:(UISwitch *)sw {
    [self policy].enabled = sw.isOn;
    [[IMDownloadSettingsStore shared] saveSettings:_working];
}

- (void)presetSliderChanged:(UISlider *)slider {
    NSInteger preset = (NSInteger)lroundf(slider.value);
    IMApplyTrafficPreset([self policy], preset); // 本地即时
    NSArray<NSString *> *names = @[ @"低", @"中", @"高" ];
    _presetLabel.text = [@"流量使用情况：" stringByAppendingString:names[preset]];
}

- (void)presetSliderCommitted:(UISlider *)slider {
    NSInteger preset = (NSInteger)lroundf(slider.value);
    slider.value = (float)preset;
    IMApplyTrafficPreset([self policy], preset);
    [[IMDownloadSettingsStore shared] saveSettings:_working]; // 触发 change 通知 → reloadFromStore 刷新类别行 detail
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

@end
