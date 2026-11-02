//  IMAboutViewController.m

#import "IMAboutViewController.h"
#import <SafariServices/SafariServices.h>
#import "IMAppInfo.h"
#import "IMSettingsIcon.h"
#import "IMLocalization.h"
#import "UIViewController+IMToast.h"
#import "IMLog.h"

typedef NS_ENUM(NSInteger, IMAboutRow) {
    IMAboutRowPrivacy,
    IMAboutRowTerms,
    IMAboutRowSupport,
    IMAboutRowVersion,
    IMAboutRowCount,
};

@interface IMAboutViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation IMAboutViewController

- (instancetype)initWithHost:(NSString *)host {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = IMLocalized(@"about.title");
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    // push 出去的页面不用 UITableViewController（液态标题栏会被下移一截，见 docs/UI_COLOR.md §2）
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];
}

#pragma mark - 行内容

- (NSString *)titleForRow:(IMAboutRow)row {
    switch (row) {
        case IMAboutRowPrivacy: return IMLocalized(@"about.privacy_policy");
        case IMAboutRowTerms:   return IMLocalized(@"about.terms");
        case IMAboutRowSupport: return IMLocalized(@"about.support");
        default:                return IMLocalized(@"about.version");
    }
}

- (UIImage *)iconForRow:(IMAboutRow)row {
    switch (row) {
        case IMAboutRowPrivacy: return IMSettingsIconImage(@"hand.raised.fill", UIColor.systemBlueColor);
        case IMAboutRowTerms:   return IMSettingsIconImage(@"doc.text.fill", UIColor.systemGrayColor);
        case IMAboutRowSupport: return IMSettingsIconImage(@"lifepreserver.fill", UIColor.systemGreenColor);
        default:                return IMSettingsIconImage(@"info.circle.fill", UIColor.systemGrayColor);
    }
}

- (nullable NSString *)legalPathForRow:(IMAboutRow)row {
    switch (row) {
        case IMAboutRowPrivacy: return IMLegalPathPrivacy;
        case IMAboutRowTerms:   return IMLegalPathTerms;
        case IMAboutRowSupport: return IMLegalPathSupport;
        default:                return nil;
    }
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return IMAboutRowCount; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMAboutRow row = (IMAboutRow)indexPath.row;
    BOOL isVersion = (row == IMAboutRowVersion);
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:isVersion ? @"value" : @"link"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:isVersion ? UITableViewCellStyleValue1 : UITableViewCellStyleDefault
                                      reuseIdentifier:isVersion ? @"value" : @"link"];
    }
    cell.imageView.image = [self iconForRow:row];
    cell.textLabel.text = [self titleForRow:row];
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.text = isVersion ? IMAppInfo.versionString : nil;
    cell.accessoryType = isVersion ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
    cell.accessibilityIdentifier = [NSString stringWithFormat:@"about.row.%ld", (long)row];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    IMAboutRow row = (IMAboutRow)indexPath.row;
    if (row == IMAboutRowVersion) { [self copyVersion]; return; }
    NSString *path = [self legalPathForRow:row];
    if (path) { [self openLegalPath:path]; }
}

#pragma mark - 动作

/// 应用内浏览器打开（SFSafariViewController，与聊天页 openLink: 同一套呈现；法务页是公开静态页，不带 token / Cookie）。
- (void)openLegalPath:(NSString *)path {
    NSURL *url = [IMAppInfo legalURLForPath:path host:self.host language:IMLocalization.shared.language];
    if (!url) {
        IMLogWarnWithTag(IMLogTagUI, @"about_open_failed path=%@ reason=no_url", path);
        [self im_showToast:IMLocalized(@"about.open_failed")];
        return;
    }
    [self presentViewController:[[SFSafariViewController alloc] initWithURL:url] animated:YES completion:nil];
}

- (void)copyVersion {
    UIPasteboard.generalPasteboard.string = IMAppInfo.versionClipboardString;
    [self im_showToast:IMLocalized(@"about.version_copied")];
}

@end
