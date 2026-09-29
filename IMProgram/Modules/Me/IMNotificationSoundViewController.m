//  IMNotificationSoundViewController.m

#import "IMNotificationSoundViewController.h"
#import "IMNotificationSettings.h"
#import "IMAlertPlayer.h"
#import "IMTheme.h"
#import "IMLocalization.h"

// ⚠️ 普通 UIViewController + 内嵌 UITableView（不用 UITableViewController）：导航容器会给 push 页注入
// IMLiquidNavigationBar 到 vc.view 上，UITableViewController 的 vc.view 本身就是滚动的 tableView，
// 注入栏会被初始负 contentOffset 推下导致标题栏下移（IMAppearanceViewController 同坑注释，CODING_STYLE §9）。
@interface IMNotificationSoundViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, assign) BOOL isGroup;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<NSString *> *soundIDs;
@property (nonatomic, copy) NSString *selectedSoundID;
@end

@implementation IMNotificationSoundViewController

- (instancetype)initForGroup:(BOOL)isGroup {
    self = [super initWithNibName:nil bundle:nil];
    if (self) { _isGroup = isGroup; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = IMLocalized(@"notif.sound.title");
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.soundIDs = @[IMNotificationSoundIDNone, IMNotificationSoundIDDefault, IMNotificationSoundIDChord,
                       IMNotificationSoundIDChime, IMNotificationSoundIDRise, IMNotificationSoundIDDrop];
    IMNotificationTypeSettings *type = self.isGroup ? IMNotificationSettings.shared.groupType : IMNotificationSettings.shared.privateType;
    self.selectedSoundID = type.sound;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"sound"];
    [self.view addSubview:self.tableView];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [IMAlertPlayer.shared stopPreview]; // 见 IMAlertPlayer.h：系统音效无停止 API，此调用为接口完整性预留
}

- (NSString *)nameForSoundID:(NSString *)soundID {
    if ([soundID isEqualToString:IMNotificationSoundIDNone]) { return IMLocalized(@"notif.sound.none"); }
    if ([soundID isEqualToString:IMNotificationSoundIDChord]) { return IMLocalized(@"notif.sound.chord"); }
    if ([soundID isEqualToString:IMNotificationSoundIDChime]) { return IMLocalized(@"notif.sound.chime"); }
    if ([soundID isEqualToString:IMNotificationSoundIDRise]) { return IMLocalized(@"notif.sound.rise"); }
    if ([soundID isEqualToString:IMNotificationSoundIDDrop]) { return IMLocalized(@"notif.sound.drop"); }
    return IMLocalized(@"notif.sound.default");
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return (NSInteger)self.soundIDs.count; }

- (nullable NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return IMLocalized(@"notif.sound.footer");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"sound" forIndexPath:indexPath];
    NSString *soundID = self.soundIDs[indexPath.row];
    cell.textLabel.text = [self nameForSoundID:soundID];
    cell.textLabel.textColor = IMTheme.textPrimary;
    cell.accessoryType = [soundID isEqualToString:self.selectedSoundID] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.tintColor = IMTheme.accent;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *soundID = self.soundIDs[indexPath.row];
    self.selectedSoundID = soundID;
    IMNotificationTypeSettings *type = self.isGroup ? IMNotificationSettings.shared.groupType : IMNotificationSettings.shared.privateType;
    // 只改 sound 一个字段：enabled/preview 原样带回（CODING_STYLE §8「整体替换写接口必须回传所有字段」）。
    [IMNotificationSettings.shared setEnabled:type.enabled preview:type.preview sound:soundID forGroup:self.isGroup];
    [tableView reloadData];
    [IMAlertPlayer.shared previewSoundNamed:soundID]; // "无" 内部已判空，不会真的发声
}

@end
