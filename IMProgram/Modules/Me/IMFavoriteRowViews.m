//  IMFavoriteRowViews.m
//  实现见 .h。逐字从 IMFavoritesViewController.m 平移（拆分只为过体量门禁，行为零变化）。

#import "IMFavoriteRowViews.h"
#import "IMMediaUtil.h"        // IMFormatFileDateTime / IMChatRecordSnippet
#import "IMTheme.h"
#import "UILabel+IMAvatar.h"

#pragma mark - 收藏阅读器（点文本 → 全文只读页，§5.6）

@implementation IMFavoriteReaderViewController { NSString *_text; }
- (instancetype)initWithText:(NSString *)text {
    self = [super init];
    if (self) { _text = [text copy]; self.title = @"收藏"; }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = IMTheme.groupedBackground;
    UITextView *tv = [UITextView new];
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    tv.editable = NO; tv.selectable = YES;
    tv.backgroundColor = UIColor.clearColor;
    tv.textColor = IMTheme.textPrimary;
    tv.font = [UIFont systemFontOfSize:IMTheme.chatFontSize];
    tv.text = _text;
    tv.textContainerInset = UIEdgeInsetsMake(16, 16, 16, 16);
    [self.view addSubview:tv];
    [NSLayoutConstraint activateConstraints:@[
        [tv.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [tv.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [tv.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tv.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}
@end

#pragma mark - 行 Cell（链接 / 文本 / 聊天记录 / 语音：统一 52pt 图标列，§4.1 / §12）

@implementation IMFavoriteRowCell { UIView *_tile; UIImageView *_glyph; UILabel *_title; UILabel *_time; UILabel *_source; }
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        _tile = [UIView new];
        _tile.translatesAutoresizingMaskIntoConstraints = NO;
        _tile.layer.cornerRadius = 10; _tile.clipsToBounds = YES;
        _tile.backgroundColor = IMTheme.accentSoft;
        [self.contentView addSubview:_tile];
        _glyph = [UIImageView new];
        _glyph.translatesAutoresizingMaskIntoConstraints = NO;
        _glyph.contentMode = UIViewContentModeScaleAspectFit;
        _glyph.tintColor = IMTheme.accent;
        [_tile addSubview:_glyph];
        _title = [UILabel new];
        _title.font = [UIFont systemFontOfSize:15];
        _title.textColor = IMTheme.textPrimary;
        _title.numberOfLines = 3;
        // 时间与「来自X」**分两行**（§收藏页副行规范）：备注名/群昵称一长，一行「来自X · 年月日时分」
        // 会把时间挤出屏幕（用户反馈看不全）。颜色也分开——来自=accent（与链接分类的来源行同色），
        // 时间=tertiary，一眼能分出两条信息。
        _time = [UILabel new];
        _time.font = [UIFont systemFontOfSize:12];
        _time.textColor = IMTheme.textTertiary;
        _source = [UILabel new];
        _source.font = [UIFont systemFontOfSize:12];
        _source.textColor = IMTheme.accent;
        _source.lineBreakMode = NSLineBreakByTruncatingTail;
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_title, _time, _source]];
        stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 3;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [_tile.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_tile.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_tile.widthAnchor constraintEqualToConstant:52], [_tile.heightAnchor constraintEqualToConstant:52],
            [_glyph.centerXAnchor constraintEqualToAnchor:_tile.centerXAnchor],
            [_glyph.centerYAnchor constraintEqualToAnchor:_tile.centerYAnchor],
            [_glyph.widthAnchor constraintEqualToConstant:26], [_glyph.heightAnchor constraintEqualToConstant:26],
            [stack.leadingAnchor constraintEqualToAnchor:_tile.trailingAnchor constant:12],
            [stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [stack.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [stack.topAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.topAnchor constant:8],
            [stack.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-8],
        ]];
    }
    return self;
}
- (void)configureWithFavorite:(NSDictionary *)fav kind:(IMFavoriteCategory)kind source:(NSString *)source {
    NSString *content = [fav[@"content"] isKindOfClass:NSString.class] ? fav[@"content"] : @"";
    int64_t createdAt = [fav[@"created_at"] respondsToSelector:@selector(longLongValue)] ? [fav[@"created_at"] longLongValue] : 0;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightSemibold];
    _title.textColor = IMTheme.textPrimary;
    _title.numberOfLines = 2; // 文本封顶 2 行，给副行「来自X · 时间」留位（#1）
    NSString *symbol = @"text.quote";
    switch (kind) {
        // Links 分类走独立 IMFavoriteLinkCell（草图 §D），cellForRow 已 kind 分流后不会到这里；
        // 老兜底分支已删（死代码——若 register 失误应立刻构建期暴露，不该在此偷偷渲染个错样式）。
        case IMFavoriteCategoryRecord: {
            symbol = @"bubble.left.and.bubble.right"; _title.numberOfLines = 2;
            NSString *snippet = IMChatRecordSnippet(content);
            _title.text = snippet.length > 0 ? snippet : @"聊天记录"; break;
        }
        case IMFavoriteCategoryVoice:
            symbol = @"waveform"; _title.numberOfLines = 1; _title.text = @"语音消息"; break;
        default:
            _title.text = content; break;
    }
    _glyph.image = [[UIImage systemImageNamed:symbol withConfiguration:cfg] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    NSString *when = createdAt > 0 ? IMFormatFileDateTime(createdAt) : @"";
    _time.text = when;
    _time.hidden = when.length == 0;
    _source.text = source.length > 0 ? [@"来自" stringByAppendingString:source] : nil;
    _source.hidden = source.length == 0;
}
@end

#pragma mark - 来源会话行（聊天模式）

@implementation IMFavoriteSourceCell { UILabel *_avatar; UILabel *_name; UILabel *_preview; UILabel *_count; }
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        _avatar = [UILabel new];
        _avatar.translatesAutoresizingMaskIntoConstraints = NO;
        // 复用会话列表 cell 的头像视觉：im_setAvatarURL: 只设首字母文本+底色，字号/白字/居中/圆裁剪须调用方给（否则首字母黑字小号左对齐）。
        _avatar.textColor = UIColor.whiteColor;
        _avatar.textAlignment = NSTextAlignmentCenter;
        _avatar.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
        _avatar.layer.cornerRadius = 23; _avatar.layer.masksToBounds = YES;
        [self.contentView addSubview:_avatar];
        _name = [UILabel new]; _name.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold]; _name.textColor = IMTheme.textPrimary;
        _preview = [UILabel new]; _preview.font = [UIFont systemFontOfSize:13]; _preview.textColor = IMTheme.textSecondary; _preview.lineBreakMode = NSLineBreakByTruncatingTail;
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_name, _preview]];
        stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 2;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:stack];
        _count = [UILabel new]; _count.font = [UIFont systemFontOfSize:13]; _count.textColor = IMTheme.textTertiary;
        _count.translatesAutoresizingMaskIntoConstraints = NO;
        [_count setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [self.contentView addSubview:_count];
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        [NSLayoutConstraint activateConstraints:@[
            [_avatar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_avatar.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:46], [_avatar.heightAnchor constraintEqualToConstant:46],
            [stack.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:12],
            [stack.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_count.leadingAnchor constraintEqualToAnchor:stack.trailingAnchor constant:8],
            [_count.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8],
            [_count.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        ]];
    }
    return self;
}
- (void)configureWithName:(NSString *)name avatarURL:(NSString *)avatarURL seed:(NSString *)seed preview:(NSString *)preview count:(NSInteger)count {
    [_avatar im_setAvatarURL:avatarURL seed:seed displayName:name];
    _name.text = name; _preview.text = preview;
    _count.text = [NSString stringWithFormat:@"%ld", (long)count];
}
@end