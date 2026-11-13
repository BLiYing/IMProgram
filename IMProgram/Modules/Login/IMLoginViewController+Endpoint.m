//  IMLoginViewController+Endpoint.m
//  登录页：长按 Logo 改服务器 / 音视频地址、只读地址行、底部《服务条款》《隐私政策》链接（ABOUT_LEGAL_DESIGN 批②）。
//  从 IMLoginViewController.m 切出（体量 + 内聚：与登录流程无共享状态，只读写 hostInput）。

#import "IMLoginViewController+Private.h"
#import "IMLocalization.h"
#import "IMServerEndpoint.h"
#import "IMAboutLinks.h"
#import "IMAppInfo.h"
#import "IMRtcConfig.h"
#import "IMTheme.h"
#import "IMLog.h"
#import <SafariServices/SafariServices.h>

@implementation IMLoginViewController (Endpoint)

/// 内置默认地址：Release 连生产服务器；Debug 模拟器恒用 127.0.0.1（避免 localhost DNS 解析在 iOS 模拟器偶发失败——
/// Go WS/HTTP 与 IMRemoteLogSink 都会静默挂掉。见 current_task.md 已知坑 / memory 记录）；Debug 真机给个占位让用户改成 Mac 当前局域网 IP。
- (NSString *)builtinHost {
#ifndef DEBUG
    return @"47.250.219.159:8081";
#elif TARGET_OS_SIMULATOR
    return @"127.0.0.1:8080";
#else
    return @"192.168.1.x:8080";
#endif
}

/// 优先用上次保存 / 成功填过的地址（切网 / 切端口时无需每次改），没有才回退内置默认。
- (NSString *)defaultHost {
    NSString *last = [NSUserDefaults.standardUserDefaults stringForKey:kIMLastHostKey];
    return last.length > 0 ? last : [self builtinHost];
}

- (void)refreshServerLabel {
    self.serverLabel.text = IMLocalizedFormat(@"login.server_summary", self.hostInput);
}

#pragma mark - 长按 Logo：配置服务器 / 音视频地址

- (void)logoLongPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan || self.submitting || self.presentedViewController) { return; }
    [self.view endEditing:YES];
    [self presentEndpointConfigWithHost:self.hostInput rtc:IMRtcConfig.load.wsURL error:nil];
}

- (void)presentEndpointConfigWithHost:(NSString *)host rtc:(NSString *)rtc error:(nullable NSString *)error {
    NSString *hint = IMLocalized(@"login.endpoint_config.hint");
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:IMLocalized(@"login.endpoint_config.title")
                                                                message:error.length > 0 ? [NSString stringWithFormat:@"%@\n%@", error, hint] : hint
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *field) {
        [self configureEndpointField:field text:host placeholder:IMLocalized(@"login.host.placeholder")];
    }];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *field) {
        [self configureEndpointField:field text:rtc placeholder:IMLocalized(@"login.rtc_address.placeholder")];
    }];
    [ac addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    __weak UIAlertController *weakAlert = ac;
    [ac addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.save") style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *action) {
        [weakSelf saveEndpointHost:weakAlert.textFields[0].text rtc:weakAlert.textFields[1].text];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)configureEndpointField:(UITextField *)field text:(NSString *)text placeholder:(NSString *)placeholder {
    field.text = text;
    field.placeholder = placeholder;
    field.keyboardType = UIKeyboardTypeURL;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
}

/// 两项都合法才落盘，否则重新弹窗并保留已填内容。留空 = 恢复默认。
/// 服务器协议**不写**全局 IMServerEndpoint——真正提交地址在点登录/注册时才发生（同 openLegalPath:）。
- (void)saveEndpointHost:(NSString *)rawHost rtc:(NSString *)rawRTC {
    NSString *hostText = [self trimmed:rawHost];
    NSString *rtcText = [self trimmed:rawRTC];
    NSString *scheme = nil, *host = nil;
    if (hostText.length > 0 && ![IMServerEndpoint parseInput:hostText scheme:&scheme host:&host]) {
        [self presentEndpointConfigWithHost:hostText rtc:rtcText error:IMLocalized(@"login.error.host_invalid")];
        return;
    }
    NSString *rtcURL = [IMRtcConfig normalizedWSURL:rtcText];
    if (rtcText.length > 0 && !rtcURL) {
        [self presentEndpointConfigWithHost:hostText rtc:rtcText error:IMLocalized(@"login.error.rtc_url_invalid")];
        return;
    }
    NSString *remembered = host ? [IMServerEndpoint rememberedInputForScheme:scheme host:host] : nil;
    [NSUserDefaults.standardUserDefaults setObject:remembered forKey:kIMLastHostKey]; // nil = 删除，回退内置默认
    [IMRtcConfig saveWSURLOverride:rtcURL];
    self.hostInput = remembered ?: [self builtinHost];
    [self refreshServerLabel];
    [self showError:@""];
    // 换了服务器：旧地址的开关 / 短信结论作废，按新地址重读（在途的旧请求由 IMPublicConfig 丢弃）。
    [self applyRegisterClosed:NO];
    [self reloadLoginConfigHostChanged:YES];
    IMLogUI(@"login_endpoint_saved host=%@ rtc=%@", self.hostInput, IMRtcConfig.load.wsURL);
}

#pragma mark - 同意提示（隐式同意，批②）

/// 不可编辑/不可滚动的 UITextView：两段链接可点，走应用内浏览器。无勾选框——点「登录/注册」即视为同意（见 ABOUT_LEGAL_DESIGN §0 批②）。
- (UITextView *)buildAgreeFooter {
    UITextView *tv = [UITextView new];
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    tv.scrollEnabled = NO;
    tv.editable = NO;
    tv.backgroundColor = UIColor.clearColor;
    tv.textContainerInset = UIEdgeInsetsZero;
    tv.textContainer.lineFragmentPadding = 0;
    tv.delegate = self;
    tv.accessibilityIdentifier = @"login.agree_footer";
    tv.linkTextAttributes = @{ NSForegroundColorAttributeName: IMTheme.accent };
    tv.attributedText = [self agreeFooterText];
    return tv;
}

/// 「继续即表示同意《服务条款》和《隐私政策》」：复用 about.terms / about.privacy_policy 作链接文案；
/// 中文的《》在格式串里，链接范围只覆盖文字本身。链接值用自定义 scheme，点击分流到对应法务页。
- (NSAttributedString *)agreeFooterText {
    NSString *terms = IMLocalized(@"about.terms");
    NSString *privacy = IMLocalized(@"about.privacy_policy");
    NSString *full = [NSString stringWithFormat:IMLocalized(@"about.agree_footer"), terms, privacy];
    NSMutableParagraphStyle *para = [NSMutableParagraphStyle new];
    para.alignment = NSTextAlignmentCenter;
    NSMutableAttributedString *s = [[NSMutableAttributedString alloc] initWithString:full attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:13],
        NSForegroundColorAttributeName: UIColor.secondaryLabelColor,
        NSParagraphStyleAttributeName: para,
    }];
    [self linkify:s label:terms url:@"imlegal://terms"];
    [self linkify:s label:privacy url:@"imlegal://privacy"];
    return s;
}

- (void)linkify:(NSMutableAttributedString *)s label:(NSString *)label url:(NSString *)url {
    NSRange r = [s.string rangeOfString:label];
    if (r.location != NSNotFound) { [s addAttribute:NSLinkAttributeName value:[NSURL URLWithString:url] range:r]; }
}

- (BOOL)textView:(UITextView *)textView shouldInteractWithURL:(NSURL *)URL inRange:(NSRange)range interaction:(UITextItemInteraction)interaction {
    NSString *path = [URL.host isEqualToString:@"terms"] ? IMLegalPathTerms
                   : [URL.host isEqualToString:@"privacy"] ? IMLegalPathPrivacy : nil;
    if (path) { [self openLegalPath:path]; }
    return NO; // 自己用 SFSafariViewController 呈现，不交给系统
}

/// 用登录页当前的服务器地址拼法务页链接并在应用内浏览器打开（法务页是公开静态页，不带 token / Cookie）。
- (void)openLegalPath:(NSString *)path {
    NSString *raw = [self trimmed:self.hostInput];
    NSString *scheme = nil, *host = nil;
    if (raw.length == 0 || ![IMServerEndpoint parseInput:raw scheme:&scheme host:&host]) {
        [self showError:IMLocalized(@"login.error.host_required")];
        return;
    }
    // 用用户此刻填的 scheme/host 匿名拉一次后台配置的链接（失败 / 老服务端回退内置路径）；
    // 同样**不改**全局 IMServerEndpoint——真正提交地址在点登录/注册时才发生。
    NSString *field = [path isEqualToString:IMLegalPathTerms] ? IMAboutLinkFieldTerms : IMAboutLinkFieldPrivacy;
    __weak typeof(self) weakSelf = self;
    [IMAboutLinks.shared refreshWithScheme:scheme host:host token:nil timeout:5 completion:^(BOOL ok) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self.presentedViewController) { return; } // 5s 内连点会叠出多个 Safari
        NSDictionary *links = [IMAboutLinks.shared cachedLinksForScheme:scheme host:host];
        NSURL *url = [IMAboutLinks URLForField:field links:links host:host scheme:scheme language:IMLocalization.shared.language];
        if (!url) {
            IMLogWarnWithTag(IMLogTagUI, @"login_legal_open_failed path=%@", path);
            [self showError:IMLocalized(@"about.open_failed")];
            return;
        }
        [self presentViewController:[[SFSafariViewController alloc] initWithURL:url] animated:YES completion:nil];
    }];
}

@end
