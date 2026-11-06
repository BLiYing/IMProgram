//  IMAboutViewController.m

#import "IMAboutViewController.h"
#import <SafariServices/SafariServices.h>
#import "IMAppInfo.h"
#import "IMAboutLinks.h"
#import "IMCustomerServiceViewController.h"
#import "IMServerEndpoint.h"
#import "IMHTTPService.h"
#import "IMSettingsIcon.h"
#import "IMLocalization.h"
#import "UIViewController+IMToast.h"
#import "IMLog.h"

typedef NS_ENUM(NSInteger, IMAboutRow) {
    IMAboutRowPrivacy,
    IMAboutRowTerms,
    IMAboutRowSupport,
    IMAboutRowCustomerService,
    IMAboutRowVersion,
};

@interface IMAboutViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, strong) UITableView *tableView;
/// 当前显示的行（NSNumber 包 IMAboutRow）；在线客服只在后台配了地址时出现。
@property (nonatomic, copy) NSArray<NSNumber *> *rows;
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
    [self rebuildRows];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshLinks];
}

/// 每次出现都拉一次后台配置的链接（带登录 token 才会拿到客服地址）；失败静默沿用缓存/内置路径。
- (void)refreshLinks {
    __weak typeof(self) weakSelf = self;
    [IMAboutLinks.shared refreshWithScheme:IMServerEndpoint.shared.scheme host:self.host
                                     token:IMHTTPService.sharedService.currentToken timeout:8
                                completion:^(BOOL ok) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !ok) { return; }
        [self rebuildRows];
        [self.tableView reloadData];
    }];
}

- (nullable NSDictionary<NSString *, NSString *> *)links {
    return [IMAboutLinks.shared cachedLinksForScheme:IMServerEndpoint.shared.scheme host:self.host];
}

- (nullable NSString *)fieldForRow:(IMAboutRow)row {
    switch (row) {
        case IMAboutRowPrivacy:         return IMAboutLinkFieldPrivacy;
        case IMAboutRowTerms:           return IMAboutLinkFieldTerms;
        case IMAboutRowSupport:         return IMAboutLinkFieldSupport;
        case IMAboutRowCustomerService: return IMAboutLinkFieldCustomerService;
        default:                        return nil;
    }
}

- (nullable NSURL *)URLForRow:(IMAboutRow)row {
    NSString *field = [self fieldForRow:row];
    if (!field) { return nil; }
    return [IMAboutLinks URLForField:field links:self.links host:self.host
                              scheme:IMServerEndpoint.shared.scheme language:IMLocalization.shared.language];
}

- (void)rebuildRows {
    NSMutableArray<NSNumber *> *rows = [@[@(IMAboutRowPrivacy), @(IMAboutRowTerms), @(IMAboutRowSupport)] mutableCopy];
    if ([self URLForRow:IMAboutRowCustomerService]) { [rows addObject:@(IMAboutRowCustomerService)]; }
    [rows addObject:@(IMAboutRowVersion)];
    self.rows = rows;
}

#pragma mark - 行内容

- (NSString *)titleForRow:(IMAboutRow)row {
    switch (row) {
        case IMAboutRowPrivacy: return IMLocalized(@"about.privacy_policy");
        case IMAboutRowTerms:   return IMLocalized(@"about.terms");
        case IMAboutRowSupport: return IMLocalized(@"about.support");
        case IMAboutRowCustomerService: return IMLocalized(@"about.customer_service");
        default:                return IMLocalized(@"about.version");
    }
}

- (UIImage *)iconForRow:(IMAboutRow)row {
    switch (row) {
        case IMAboutRowPrivacy: return IMSettingsIconImage(@"hand.raised.fill", UIColor.systemBlueColor);
        case IMAboutRowTerms:   return IMSettingsIconImage(@"doc.text.fill", UIColor.systemGrayColor);
        case IMAboutRowSupport: return IMSettingsIconImage(@"lifepreserver.fill", UIColor.systemGreenColor);
        case IMAboutRowCustomerService: return IMSettingsIconImage(@"headphones", UIColor.systemOrangeColor);
        default:                return IMSettingsIconImage(@"info.circle.fill", UIColor.systemGrayColor);
    }
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return (NSInteger)self.rows.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMAboutRow row = (IMAboutRow)self.rows[indexPath.row].integerValue;
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
    IMAboutRow row = (IMAboutRow)self.rows[indexPath.row].integerValue;
    if (row == IMAboutRowVersion) { [self copyVersion]; return; }
    [self openRow:row];
}

#pragma mark - 动作

/// 应用内浏览器打开（SFSafariViewController，与聊天页 openLink: 同一套呈现；法务页与在线客服共用，仅 http/https，
/// 不带 token / Cookie）。
- (void)openRow:(IMAboutRow)row {
    NSURL *url = [self URLForRow:row];
    if (!url) {
        IMLogWarnWithTag(IMLogTagUI, @"about_open_failed row=%ld reason=no_url", (long)row);
        [self im_showToast:IMLocalized(@"about.open_failed")];
        return;
    }
    if (row == IMAboutRowCustomerService) {
        // 客服页用自有 WKWebView（键盘上方留位 / 禁缩放 / UA 标记）；法务三项仍走 SFSafariViewController。
        [self.navigationController pushViewController:[[IMCustomerServiceViewController alloc] initWithURL:url] animated:YES];
        return;
    }
    [self presentViewController:[[SFSafariViewController alloc] initWithURL:url] animated:YES completion:nil];
}

- (void)copyVersion {
    UIPasteboard.generalPasteboard.string = IMAppInfo.versionClipboardString;
    [self im_showToast:IMLocalized(@"about.version_copied")];
}

@end
