#import "IMSystemCell.h"

#import "IMBubbleCell.h"   // IMMentionUIDAttributeName + TextKit 反查（与 @昵称 点击同一套）
#import "IMMessageModel.h" // IMSysSegment
#import "IMTheme.h"

@implementation IMSystemCell {
    UIView  *_pill;
    UILabel *_label;
    UIButton *_reeditButton;
    void (^_reeditHandler)(void);
    void (^_tapUIDHandler)(NSString *uid);
    UITapGestureRecognizer *_nameTap;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _pill = [UIView new];
        _pill.translatesAutoresizingMaskIntoConstraints = NO;
        _pill.backgroundColor = IMTheme.datePillBg;
        _pill.layer.cornerRadius = 11;
        _pill.layer.masksToBounds = YES;
        [self.contentView addSubview:_pill];
        _label = [UILabel new];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _label.font = [UIFont systemFontOfSize:12];
        _label.textColor = IMTheme.datePillText;
        _label.textAlignment = NSTextAlignmentCenter;
        _label.numberOfLines = 0;
        [_pill addSubview:_label];
        [NSLayoutConstraint activateConstraints:@[
            [_pill.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
            [_pill.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6],
            [_pill.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_pill.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.leadingAnchor constant:40],
            [_pill.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-40],
            [_label.topAnchor constraintEqualToAnchor:_pill.topAnchor constant:4],
            [_label.bottomAnchor constraintEqualToAnchor:_pill.bottomAnchor constant:-4],
            [_label.leadingAnchor constraintEqualToAnchor:_pill.leadingAnchor constant:10],
            [_label.trailingAnchor constraintEqualToAnchor:_pill.trailingAnchor constant:-10],
        ]];
        _reeditButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _reeditButton.translatesAutoresizingMaskIntoConstraints = NO;
        _reeditButton.titleLabel.font = [UIFont systemFontOfSize:12];
        [_reeditButton setTitle:@"重新编辑" forState:UIControlStateNormal];
        [_reeditButton addTarget:self action:@selector(onReedit) forControlEvents:UIControlEventTouchUpInside];
        _reeditButton.hidden = YES;
        [self.contentView addSubview:_reeditButton];
        [NSLayoutConstraint activateConstraints:@[
            [_reeditButton.leadingAnchor constraintEqualToAnchor:_pill.trailingAnchor constant:6],
            [_reeditButton.centerYAnchor constraintEqualToAnchor:_pill.centerYAnchor],
        ]];
    }
    return self;
}
- (void)configureWithText:(NSString *)text {
    [self configureWithText:text reeditHandler:nil];
}
- (void)configureWithText:(NSString *)text reeditHandler:(void (^)(void))reeditHandler {
    _label.attributedText = nil;
    _label.text = text.length > 0 ? text : @"";
    _reeditHandler = [reeditHandler copy];
    _reeditButton.hidden = (reeditHandler == nil);
    _tapUIDHandler = nil;
}

- (void)configureWithSegments:(NSArray<IMSysSegment *> *)segments
                 fallbackText:(NSString *)fallbackText
            displayNameForUID:(NSString *(^)(NSString *, NSString *))displayNameForUID
                     onTapUID:(void (^)(NSString *))onTapUID {
    // 历史系统消息没有分段（服务端当时没存）→ 走整句老路：名字仍是当时的昵称、不可点。
    if (segments.count == 0) {
        [self configureWithText:fallbackText reeditHandler:nil];
        return;
    }
    NSDictionary *base = @{ NSForegroundColorAttributeName: IMTheme.datePillText,
                            NSFontAttributeName: [UIFont systemFontOfSize:12] };
    NSMutableAttributedString *out = [NSMutableAttributedString new];
    for (IMSysSegment *seg in segments) {
        NSString *text = seg.text ?: @"";
        if (seg.uid.length == 0) { // 固定文案：原样
            [out appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:base]];
            continue;
        }
        // 名字段：换成本地显示名（我给他设了备注就显备注——仅本机渲染，不改消息内容）。
        NSString *shown = displayNameForUID ? displayNameForUID(seg.uid, text) : text;
        NSMutableDictionary *attrs = [base mutableCopy];
        // 名字段用**浅琥珀 + 半粗**，不用 accent：胶囊底是主题绿（datePillBg = 0x5C8A4C@55%），
        // 再把名字染成同样是绿的 accent，两者色相几乎重合，看不出哪几个字是名字（用户 2026-08-30 反馈）。
        // 也不用白——那与胶囊正文同色，只剩粗细之差。琥珀在绿胶囊与黑胶囊上都跳得出来。
        attrs[NSForegroundColorAttributeName] = IMTheme.datePillNameText;
        attrs[NSFontAttributeName] = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        if (onTapUID) { attrs[IMMentionUIDAttributeName] = seg.uid; } // 无点击回调就只染色不挂 uid
        [out appendAttributedString:[[NSAttributedString alloc] initWithString:(shown.length > 0 ? shown : text)
                                                                   attributes:attrs]];
    }
    _label.attributedText = out;
    _reeditHandler = nil;
    _reeditButton.hidden = YES;
    _tapUIDHandler = [onTapUID copy];
    if (!_nameTap) {
        _nameTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onLabelTap:)];
        _label.userInteractionEnabled = YES;
        [_label addGestureRecognizer:_nameTap];
    }
}

/// 点在名字上才响应（TextKit 反查落点字符的 uid 属性），点在固定文案上不动作。
/// 复用 IMBubbleCell 那套 @昵称 命中判定，避免再写一份坐标换算。
- (void)onLabelTap:(UITapGestureRecognizer *)g {
    if (!_tapUIDHandler) { return; }
    NSRange hit = NSMakeRange(NSNotFound, 0);
    NSString *uid = [IMBubbleCell mentionUIDInLabel:_label atPoint:[g locationInView:_label] range:&hit];
    if (uid.length == 0) { return; }
    [IMBubbleCell flashMentionHighlightInLabel:_label range:hit]; // 点击回执：没有它，点下去到资料页出来之前毫无反应
    _tapUIDHandler(uid);
}
- (void)onReedit {
    if (_reeditHandler) { _reeditHandler(); }
}
- (void)prepareForReuse {
    [super prepareForReuse];
    _reeditHandler = nil;
    _tapUIDHandler = nil;
    _reeditButton.hidden = YES;
    // 富文本残留会让下一条纯文本系统行继承上一条的强调色名字段（复用池的经典坑）。
    _label.attributedText = nil;
    _label.text = @"";
}
@end
