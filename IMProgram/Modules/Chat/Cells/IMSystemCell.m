#import "IMSystemCell.h"
#import "IMTheme.h"

@implementation IMSystemCell {
    UIView  *_pill;
    UILabel *_label;
    UIButton *_reeditButton;
    void (^_reeditHandler)(void);
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
    _label.text = text.length > 0 ? text : @"";
    _reeditHandler = [reeditHandler copy];
    _reeditButton.hidden = (reeditHandler == nil);
}
- (void)onReedit {
    if (_reeditHandler) { _reeditHandler(); }
}
- (void)prepareForReuse {
    [super prepareForReuse];
    _reeditHandler = nil;
    _reeditButton.hidden = YES;
}
@end
