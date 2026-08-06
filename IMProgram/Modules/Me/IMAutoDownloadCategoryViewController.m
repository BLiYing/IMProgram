//  IMAutoDownloadCategoryViewController.m

#import "IMAutoDownloadCategoryViewController.h"
#import "IMDownloadSettingsUI.h"
#import "IMDownloadSettingsStore.h"

@interface IMAutoDownloadCategoryViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation IMAutoDownloadCategoryViewController {
    IMDownloadNetworkKind _net;
    IMDownloadCategoryKind _cat;
    IMDownloadSettings *_working;      // 编辑副本（进页/变更时从 store 深拷贝）
    __weak UILabel *_sizeTitleLabel;   // "上限 X" 实时刷新
}

- (instancetype)initWithNetwork:(IMDownloadNetworkKind)network category:(IMDownloadCategoryKind)category {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _net = network;
        _cat = category;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = IMDownloadCategoryName(_cat);
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

- (IMDownloadCategoryRule *)rule { return IMRuleForCategory(IMPolicyForNetwork(_working, _net), _cat); }

- (BOOL)hasSizeLimit { return _cat != IMDownloadCategoryImage; } // 图片无大小上限

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return [self hasSizeLimit] ? 2 : 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 2 : 1; // 0: 单聊/群聊；1: 大小上限
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? [@"自动下载" stringByAppendingString:IMDownloadCategoryName(_cat)] : @"大小上限";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (_cat == IMDownloadCategoryImage) { return @"图片体积小，建议保持自动下载（无大小上限）。"; }
    if (section == 1) { return @"超过上限的媒体不自动下载，卡片显“未下载”，可手动点 ↓。上限设为“关”即完全手动。"; }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMDownloadCategoryRule *rule = [self rule];
    if (indexPath.section == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = indexPath.row == 0 ? @"单聊" : @"群聊";
        UISwitch *sw = [UISwitch new];
        sw.on = indexPath.row == 0 ? rule.single : rule.group;
        sw.tag = indexPath.row; // 0=单聊,1=群聊
        [sw addTarget:self action:@selector(chatSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        return cell;
    }
    // 大小上限滑块
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = [UIFont systemFontOfSize:15];
    title.text = [NSString stringWithFormat:@"上限 %@", IMDownloadSizeLabel(rule.maxBytes)];
    _sizeTitleLabel = title;
    UISlider *slider = [[UISlider alloc] init];
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    slider.minimumValue = 0;
    slider.maximumValue = (float)(IMDownloadSizeStops().count - 1);
    slider.value = (float)IMDownloadSizeStopIndex(rule.maxBytes);
    [slider addTarget:self action:@selector(sizeSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [slider addTarget:self action:@selector(sizeSliderCommitted:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
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

#pragma mark - 编辑 → 保存

- (void)chatSwitchChanged:(UISwitch *)sw {
    IMDownloadCategoryRule *rule = [self rule];
    if (sw.tag == 0) { rule.single = sw.isOn; } else { rule.group = sw.isOn; }
    [[IMDownloadSettingsStore shared] saveSettings:_working];
}

- (void)sizeSliderChanged:(UISlider *)slider {
    NSInteger idx = (NSInteger)lroundf(slider.value);
    int64_t bytes = IMDownloadSizeStops()[idx].longLongValue;
    [self rule].maxBytes = bytes; // 本地即时（PUT 留到松手）
    _sizeTitleLabel.text = [NSString stringWithFormat:@"上限 %@", IMDownloadSizeLabel(bytes)];
}

- (void)sizeSliderCommitted:(UISlider *)slider {
    NSInteger idx = (NSInteger)lroundf(slider.value);
    slider.value = (float)idx; // 吸附到档位
    [self rule].maxBytes = IMDownloadSizeStops()[idx].longLongValue;
    [[IMDownloadSettingsStore shared] saveSettings:_working];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

@end
