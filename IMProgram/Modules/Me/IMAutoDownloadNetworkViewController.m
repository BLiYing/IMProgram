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
    __weak UISlider *_presetSlider;    // 档位滑杆（总开关关闭时置灰禁用）
    __weak UILabel *_presetLabel;      // "流量使用情况：中"
    __weak UIStackView *_presetTicks;  // 低/中/高（+自定义）刻度行，拖动时联动高亮
    BOOL _presetCustom;                // 当前是否处于自定义（滑杆显第四档）
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

// 仅在**外部变更**（多端同步 / 子页编辑返回）时整表重载；本页自己保存触发的回声（乐观值/服务端回显）
// 与本地 _working 一致 → 直接跳过，避免整表 reloadData 让总开关等其他卡片闪烁（见滑杆提交处的定向刷新）。
- (void)reloadFromStore {
    IMDownloadSettings *cur = [IMDownloadSettingsStore shared].settings;
    BOOL equivalent = [cur isEquivalentTo:_working];
    _working = [cur deepCopy]; // 始终隔离独立副本：拖动只改副本、绝不触到全局 store（否则未落库的中间值会外泄）
    if (equivalent) { return; } // 值未变（自身保存的回声）→ 跳过 reloadData 防其他卡片闪烁（定向刷新在提交处）
    [self.tableView reloadData];
}

// 总开关关闭时：档位滑杆置淡、禁滑；打开时恢复。
- (void)applyTierEnabled:(BOOL)enabled {
    _presetSlider.enabled = enabled;
    _presetSlider.alpha = enabled ? 1.0 : 0.4;
    _presetLabel.textColor = enabled ? UIColor.labelColor : UIColor.tertiaryLabelColor;
    for (UIView *t in _presetTicks.arrangedSubviews) { t.alpha = enabled ? 1.0 : 0.4; }
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
    if (indexPath.section == 1) { // 低/中/高（+ 仅自定义时临时出现的第四档）
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        IMTrafficPreset preset = IMTrafficPresetForPolicy(p);
        _presetCustom = (preset == IMTrafficPresetCustom);
        NSArray<NSString *> *names = [self presetTickNames]; // 自定义时含第四档
        UILabel *title = [[UILabel alloc] init];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        title.font = [UIFont systemFontOfSize:15];
        title.text = [@"流量使用情况：" stringByAppendingString:names[preset]];
        _presetLabel = title;
        UISlider *slider = [[UISlider alloc] init];
        slider.translatesAutoresizingMaskIntoConstraints = NO;
        slider.minimumValue = 0;
        slider.maximumValue = (float)(names.count - 1); // 三档=2；自定义时=3
        slider.value = (float)preset;
        [slider addTarget:self action:@selector(presetSliderChanged:) forControlEvents:UIControlEventValueChanged];
        [slider addTarget:self action:@selector(presetSliderCommitted:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
        // 档位刻度：末档右对齐、首档左对齐，与滑杆两端对齐；当前档高亮。
        UIStackView *ticks = [[UIStackView alloc] init];
        ticks.translatesAutoresizingMaskIntoConstraints = NO;
        ticks.axis = UILayoutConstraintAxisHorizontal;
        ticks.distribution = UIStackViewDistributionFillEqually;
        for (NSUInteger i = 0; i < names.count; i++) {
            UILabel *t = [[UILabel alloc] init];
            t.font = [UIFont systemFontOfSize:11];
            t.text = names[i];
            t.textColor = ((NSInteger)i == preset) ? UIColor.labelColor : UIColor.secondaryLabelColor;
            t.textAlignment = (i == 0) ? NSTextAlignmentLeft
                : (i == names.count - 1 ? NSTextAlignmentRight : NSTextAlignmentCenter);
            [ticks addArrangedSubview:t];
        }
        _presetTicks = ticks;
        _presetSlider = slider;
        [cell.contentView addSubview:title];
        [cell.contentView addSubview:slider];
        [cell.contentView addSubview:ticks];
        [NSLayoutConstraint activateConstraints:@[
            [title.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
            [title.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:10],
            [slider.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
            [slider.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
            [slider.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8],
            [ticks.leadingAnchor constraintEqualToAnchor:slider.leadingAnchor],
            [ticks.trailingAnchor constraintEqualToAnchor:slider.trailingAnchor],
            [ticks.topAnchor constraintEqualToAnchor:slider.bottomAnchor constant:2],
            [ticks.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-10],
        ]];
        [self applyTierEnabled:p.enabled]; // 总开关关闭 → 档位置淡禁滑
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
    [self applyTierEnabled:sw.isOn]; // 就地联动档位禁/启用（不整表重载，避免闪烁）
}

// 自定义时含第四档；仅命中预设时为三档。
- (NSArray<NSString *> *)presetTickNames {
    return _presetCustom ? @[ @"低", @"中", @"高", @"自定义" ] : @[ @"低", @"中", @"高" ];
}

// 拖动中：只更新文字/刻度高亮（不落库，PUT 留到松手），不重建控件（档数不变，避免抖动）。
- (void)presetSliderChanged:(UISlider *)slider {
    NSArray<NSString *> *names = [self presetTickNames];
    NSInteger idx = (NSInteger)lroundf(slider.value);
    idx = MAX(0, MIN(idx, (NSInteger)names.count - 1));
    _presetLabel.text = [@"流量使用情况：" stringByAppendingString:names[idx]];
    for (NSUInteger i = 0; i < _presetTicks.arrangedSubviews.count; i++) {
        UILabel *t = (UILabel *)_presetTicks.arrangedSubviews[i];
        t.textColor = ((NSInteger)i == idx) ? UIColor.labelColor : UIColor.secondaryLabelColor;
    }
}

- (void)presetSliderCommitted:(UISlider *)slider {
    NSInteger idx = (NSInteger)lroundf(slider.value);
    // 停在“自定义”这一档：它是只读指示、无预设可套用 → 吸附回第四档、保持现状不落库。
    if (_presetCustom && idx == IMTrafficPresetCustom) {
        slider.value = (float)IMTrafficPresetCustom;
        return;
    }
    idx = MAX(0, MIN(idx, (NSInteger)IMTrafficPresetHigh)); // 只有低/中/高可套用
    slider.value = (float)idx;
    IMApplyTrafficPreset([self policy], idx);
    [[IMDownloadSettingsStore shared] saveSettings:_working];
    // 自身保存的通知被 reloadFromStore 跳过（防闪烁）→ 这里只定向刷新档位(1)与类别汇总(2)：
    // 套预设后档位可能从四档退回三档、类别行"最大 X"随之更新；总开关(0)不动、不闪。
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, 2)]
                  withRowAnimation:UITableViewRowAnimationNone];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

@end
