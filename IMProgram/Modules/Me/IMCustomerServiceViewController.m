//  IMCustomerServiceViewController.m

#import "IMCustomerServiceViewController.h"
#import <WebKit/WebKit.h>
#import "IMAboutLinks.h"
#import "IMLocalization.h"
#import "IMLog.h"
#import "IMActionListSheet.h"
#import "IMWorkbench.h"

/// 禁双击/捏合缩放：强制 viewport（与 scrollView 侧的限制双保险）。
static NSString *const kNoZoomScript =
    @"(function(){var m=document.querySelector('meta[name=viewport]');"
    @"var c='width=device-width,initial-scale=1,maximum-scale=1,minimum-scale=1,user-scalable=no';"
    @"if(!m){m=document.createElement('meta');m.name='viewport';(document.head||document.documentElement).appendChild(m);}"
    @"m.setAttribute('content',c);})();";

@interface IMCustomerServiceViewController () <WKNavigationDelegate, WKUIDelegate>
@property (nonatomic, strong) NSURL *startURL;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UIView *errorView;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, assign) BOOL observing;
@property (nonatomic, copy, nullable) NSString *fixedTitle;
@property (nonatomic, copy, nullable) NSString *initialTitle; // 工作台：先显示应用名，网页 <title> 到了替换
@property (nonatomic, assign) BOOL workbench;
@end

@implementation IMCustomerServiceViewController

- (instancetype)initWithURL:(NSURL *)url {
    return [self initWithURL:url title:nil];
}

- (instancetype)initWithURL:(NSURL *)url title:(NSString *)title {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _startURL = url;
        _fixedTitle = title.length > 0 ? [title copy] : nil;
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (instancetype)initWorkbenchWithURL:(NSURL *)url title:(NSString *)title {
    self = [self initWithURL:url title:nil];
    if (self) {
        _workbench = YES;
        _initialTitle = [title copy];
    }
    return self;
}

- (void)dealloc { [self teardownWebView]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.fixedTitle ?: (self.initialTitle ?: IMLocalized(@"about.customer_service")); // 无公司名时网页 <title> 到了再替换，不显示服务器 IP
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    UIBarButtonItem *close = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"] style:UIBarButtonItemStylePlain
                                                              target:self action:@selector(closeTapped)];
    close.accessibilityLabel = IMLocalized(@"common.close");
    close.accessibilityIdentifier = @"customerService.close";
    if (self.workbench) { // 交互稿 I-5：左 ✕ 关闭，右 ⋯ 菜单
        close.style = UIBarButtonItemStyleDone;
        self.navigationItem.leftBarButtonItem = close;
        UIBarButtonItem *more = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis"] style:UIBarButtonItemStylePlain
                                                                target:self action:@selector(moreTapped)];
        more.accessibilityLabel = IMLocalized(@"common.more");
        more.accessibilityIdentifier = @"workbench.web.more";
        self.navigationItem.rightBarButtonItem = more;
    } else {
        self.navigationItem.rightBarButtonItem = close;
    }

    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    // 保持默认持久 data store：localStorage 存访客身份，不能清。
    cfg.websiteDataStore = WKWebsiteDataStore.defaultDataStore;
    // 公开 API：系统会把它追加在默认 UA 末尾（形如 "… Mobile/15E148 BeaconApp/1.0 (iOS)"），Beacon 只认 BeaconApp/ 标记。
    // 不用 KVC 读私有 userAgent 属性（上架审核风险）。
    if (!self.workbench) { cfg.applicationNameForUserAgent = [self beaconAppName]; } // 工作台应用不是 Beacon 访客页
    WKUserScript *script = [[WKUserScript alloc] initWithSource:kNoZoomScript injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
    [cfg.userContentController addUserScript:script];

    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:cfg];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
    self.webView.allowsBackForwardNavigationGestures = YES;
    UIScrollView *sv = self.webView.scrollView;
    sv.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever; // 避免与键盘布局双重内缩
    sv.minimumZoomScale = 1;
    sv.maximumZoomScale = 1;
    sv.bouncesZoom = NO;
    sv.pinchGestureRecognizer.enabled = NO;
    [self.view addSubview:self.webView];
    // 底边贴键盘顶：键盘弹起 → 布局视口变矮，底部输入栏的发送按钮始终在可见区（键盘收起时等于安全区底）。
    [NSLayoutConstraint activateConstraints:@[
        [self.webView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.webView.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],
    ]];

    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
    self.progressView.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressView.progressTintColor = self.view.tintColor;
    self.progressView.trackTintColor = UIColor.clearColor;
    [self.view addSubview:self.progressView];
    [NSLayoutConstraint activateConstraints:@[
        [self.progressView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.progressView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.progressView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    [self buildErrorView];

    [self.webView addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:NULL];
    [self.webView addObserver:self forKeyPath:@"title" options:NSKeyValueObservingOptionNew context:NULL];
    self.observing = YES;

    [self load];
}

- (NSString *)beaconAppName {
    NSString *ver = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return [IMAboutLinks beaconUserAgentWithBase:nil version:ver];
}

#pragma mark - 失败页

- (void)buildErrorView {
    UIView *box = [[UIView alloc] init];
    box.translatesAutoresizingMaskIntoConstraints = NO;
    box.backgroundColor = UIColor.systemBackgroundColor;
    box.hidden = YES;
    self.errorLabel = [[UILabel alloc] init];
    self.errorLabel.textColor = UIColor.secondaryLabelColor;
    self.errorLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.errorLabel.textAlignment = NSTextAlignmentCenter;
    self.errorLabel.numberOfLines = 0;
    self.errorLabel.text = IMLocalized(@"common.load_failed");
    UIButton *retry = [UIButton buttonWithType:UIButtonTypeSystem];
    [retry setTitle:IMLocalized(@"common.retry") forState:UIControlStateNormal];
    retry.accessibilityIdentifier = @"customerService.retry";
    [retry addTarget:self action:@selector(retryTapped) forControlEvents:UIControlEventTouchUpInside];
    UIButton *open = [UIButton buttonWithType:UIButtonTypeSystem];
    [open setTitle:IMLocalized(@"common.open_in_browser") forState:UIControlStateNormal];
    open.accessibilityIdentifier = @"customerService.openInBrowser";
    [open addTarget:self action:@selector(openInBrowserTapped) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.errorLabel, retry, open]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 16;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:stack];
    [self.view addSubview:box];
    [NSLayoutConstraint activateConstraints:@[
        [box.topAnchor constraintEqualToAnchor:self.webView.topAnchor],
        [box.bottomAnchor constraintEqualToAnchor:self.webView.bottomAnchor],
        [box.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [box.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [stack.centerXAnchor constraintEqualToAnchor:box.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:box.centerYAnchor constant:-40],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:box.leadingAnchor constant:24],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:box.trailingAnchor constant:-24],
    ]];
    self.errorView = box;
}

- (void)showError:(BOOL)show {
    self.errorView.hidden = !show;
    if (show) { [self.view endEditing:YES]; }
}

#pragma mark - 动作

- (void)load {
    [self showError:NO];
    [self.webView loadRequest:[NSURLRequest requestWithURL:self.startURL]];
    // 工作台：票据只用一次（应用后端已兑换），之后的重载 / 重试一律用不带票据的地址，否则应用会报票据无效
    if (self.workbench) { self.startURL = [IMWorkbench urlByRemovingTicket:self.startURL]; }
}

- (void)retryTapped {
    NSURL *cur = self.webView.URL;
    BOOL curOK = cur && [self decisionForURL:cur] == IMAboutNavDecisionAllow && ![cur.absoluteString isEqualToString:@"about:blank"];
    if (self.workbench) { // 刷新 / 重试 / 进程崩溃恢复：当前页去掉票据再载入（reload 会把用过的票据原样再发一次）
        [self showError:NO];
        [self.webView loadRequest:[NSURLRequest requestWithURL:[IMWorkbench urlByRemovingTicket:(curOK ? cur : self.startURL)]]];
    } else if (curOK) {
        [self showError:NO];
        [self.webView reload];
    } else {
        [self load];
    }
}

- (void)openInBrowserTapped {
    NSURL *url = self.webView.URL ?: self.startURL;
    if ([IMAboutLinks navigationDecisionForURL:url] != IMAboutNavDecisionAllow) { url = self.startURL; }
    if (self.workbench) { url = [IMWorkbench urlByRemovingTicket:url]; } // 一次性票据不带出 App
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

- (void)moreTapped {
    __weak typeof(self) weak = self;
    [IMActionListSheet presentFrom:self title:nil items:@[
        [IMActionListItem itemWithTitle:IMLocalized(@"common.refresh") destructive:NO handler:^{ [weak retryTapped]; }],
        [IMActionListItem itemWithTitle:IMLocalized(@"common.open_in_browser") destructive:NO handler:^{ [weak openInBrowserTapped]; }],
    ]];
}

/// 本页的导航判定：在线客服沿用 IMAboutLinks；工作台另把「允许」收窄到 https 与本机 / 内网 http，其余 http 交给系统打开。
- (IMAboutNavDecision)decisionForURL:(NSURL *)url {
    IMAboutNavDecision d = [IMAboutLinks navigationDecisionForURL:url];
    if (self.workbench && d == IMAboutNavDecisionAllow && ![url.scheme.lowercaseString isEqualToString:@"about"]
        && ![IMWorkbench isAllowedWebURL:url]) {
        return IMAboutNavDecisionExternal;
    }
    return d;
}

- (void)closeTapped {
    [self teardownWebView];
    if (self.navigationController.viewControllers.firstObject != self) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

/// 解除 KVO 与 delegate，停止加载；幂等（close 与 dealloc 都会走）。
- (void)teardownWebView {
    if (self.observing) {
        [self.webView removeObserver:self forKeyPath:@"estimatedProgress"];
        [self.webView removeObserver:self forKeyPath:@"title"];
        self.observing = NO;
    }
    self.webView.navigationDelegate = nil;
    self.webView.UIDelegate = nil;
    [self.webView stopLoading];
}

- (void)didMoveToParentViewController:(UIViewController *)parent {
    [super didMoveToParentViewController:parent];
    if (!parent) { [self teardownWebView]; } // 系统返回手势/按钮离开
}

#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"estimatedProgress"]) {
        float p = (float)self.webView.estimatedProgress;
        self.progressView.hidden = NO;
        [self.progressView setProgress:p animated:p > self.progressView.progress];
        if (p >= 1.0f) {
            __weak typeof(self) weak = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (weak.webView.estimatedProgress >= 1.0) { weak.progressView.hidden = YES; [weak.progressView setProgress:0 animated:NO]; }
            });
        }
    } else if ([keyPath isEqualToString:@"title"]) {
        NSString *t = [self.webView.title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        // 网页没设 title 时 WebKit 会回落成 host（服务器 IP），不显示。
        if (!self.fixedTitle && t.length > 0 && ![t isEqualToString:self.webView.URL.host] && ![t isEqualToString:self.webView.URL.absoluteString]) {
            self.title = t;
        }
    }
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))handler {
    NSURL *url = action.request.URL;
    switch ([self decisionForURL:url]) {
        case IMAboutNavDecisionAllow:
            if (!action.targetFrame) { [webView loadRequest:action.request]; handler(WKNavigationActionPolicyCancel); return; } // target=_blank
            handler(WKNavigationActionPolicyAllow);
            return;
        case IMAboutNavDecisionExternal:
            // 子框架（iframe 里的统计 / 广告）要去的外部地址只拦不外开：否则每次打开页面都被拽去 Safari
            if (action.targetFrame && !action.targetFrame.isMainFrame) { handler(WKNavigationActionPolicyCancel); return; }
            IMLogWarnWithTag(IMLogTagUI, @"cs_external_open scheme=%@", url.scheme);
            [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
            handler(WKNavigationActionPolicyCancel);
            return;
        case IMAboutNavDecisionBlock:
            IMLogWarnWithTag(IMLogTagUI, @"cs_nav_blocked scheme=%@", url.scheme ?: @"(nil)");
            handler(WKNavigationActionPolicyCancel);
            return;
    }
}

- (nullable WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
            forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)features {
    // window.open / target=_blank：本页打开，不新建 webview。
    if (!action.targetFrame) {
        IMAboutNavDecision d = [self decisionForURL:action.request.URL];
        if (d == IMAboutNavDecisionAllow) { [webView loadRequest:action.request]; }
        else if (d == IMAboutNavDecisionExternal) {
            [UIApplication.sharedApplication openURL:action.request.URL options:@{} completionHandler:nil];
        }
    }
    return nil;
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation { [self showError:NO]; }

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self handleFailure:error];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self handleFailure:error];
}

- (void)handleFailure:(NSError *)error {
    if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) { return; }
    if ([error.domain isEqualToString:@"WebKitErrorDomain"] && error.code == 102) { return; } // 帧加载被中断（外部 scheme 拦截）
    IMLogWarnWithTag(IMLogTagUI, @"cs_load_failed domain=%@ code=%ld", error.domain, (long)error.code);
    [self showError:YES];
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    if (self.workbench) { [self retryTapped]; } else { [webView reload]; }
}

@end
