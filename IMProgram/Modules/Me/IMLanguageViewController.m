//  IMLanguageViewController.m
//
//  各语言用**自己的语言**写（简体中文 / English），不随界面语言翻译——用户切错了还认得出来。
//  选定后只改偏好；界面重建由 SceneDelegate 监听 IMLanguageDidChangeNotification 统一做
//  （不逐个 VC 监听刷新：漏一个就是半中半英），重建后会自动回到本页。
//  不用 UITableViewController：注入的液态标题栏会把它的表格下移（见项目记忆）。

#import "IMLanguageViewController.h"
#import "IMLocalization.h"

@interface IMLanguageViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation IMLanguageViewController

+ (NSArray<NSString *> *)options {
    return @[IMLanguagePrefSystem, IMLanguagePrefZhHans, IMLanguagePrefEnglish];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = IMLocalized(@"settings.language.title");
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [IMLanguageViewController options].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return IMLocalized(@"settings.language.footer");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *pref = [IMLanguageViewController options][indexPath.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if ([pref isEqualToString:IMLanguagePrefSystem]) {
        cell.textLabel.text = IMLocalized(@"settings.language.option_system");
        cell.detailTextLabel.text = IMLocalization.shared.systemLanguageNativeName;
    } else {
        cell.textLabel.text = [IMLocalization nativeNameForLanguage:pref];
    }
    cell.accessoryType = [pref isEqualToString:IMLocalization.shared.preference]
        ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [IMLocalization.shared setPreference:[IMLanguageViewController options][indexPath.row]];
    // 偏好没变时 setPreference 是空操作、也不发通知——本页不重建，这里就地刷新勾选即可；
    // 偏好变了则整个根控制器会被重建，本页随之被新实例取代。
    [self.tableView reloadData];
}

@end
