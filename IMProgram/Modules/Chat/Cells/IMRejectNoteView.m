#import "IMRejectNoteView.h"
#import "IMTheme.h"

/// 拒收码是否带可自助恢复的动作。
/// 当前只有「非好友」可恢复（发好友申请）；**被拉黑(200102) 刻意不给**——服务端对拉黑与非好友
/// 返回同样的模糊文案就是为了不泄露拉黑，给了入口反而会因申请被 200102 拒而暴露。
/// 禁言(300004)/非群成员(300203)/全员禁言(300206) 均无自助动作。
static BOOL IMNoteCodeIsActionable(NSInteger code) { return code == 200103; }

@implementation IMRejectNoteView {
    UILabel *_label;
    BOOL _actionable;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _label = [UILabel new];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _label.font = [UIFont systemFontOfSize:12];
        _label.textColor = IMTheme.textSecondary;
        _label.textAlignment = NSTextAlignmentCenter;
        _label.numberOfLines = 0;
        [self addSubview:_label];
        [NSLayoutConstraint activateConstraints:@[
            [_label.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_label.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        ]];
        // 整行热区，而非精确命中动作文字——12pt 文字逐字命中太难点，且该行没有别的可点元素。
        [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)]];
        // 默认不可交互：不可恢复的系统行不该拦住落到气泡/表格的手势（长按菜单等）。
        self.userInteractionEnabled = NO;
    }
    return self;
}

- (void)configureWithNote:(NSString *)note code:(NSInteger)code {
    _hasContent = note.length > 0;
    _actionable = _hasContent && IMNoteCodeIsActionable(code);
    self.userInteractionEnabled = _actionable;
    self.hidden = !_hasContent;
    if (!_hasContent) {
        _label.attributedText = nil;
        _label.text = nil;
        return;
    }
    if (!_actionable) {
        // 先清 attributedText：否则它会盖住 label 自身的 font/textColor（上一次可恢复渲染的残留）。
        _label.attributedText = nil;
        _label.text = note;
        return;
    }
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
    ps.alignment = NSTextAlignmentCenter;
    ps.paragraphSpacingBefore = 2;
    NSMutableAttributedString *s = [[NSMutableAttributedString alloc] initWithString:note attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:12],
        NSForegroundColorAttributeName: IMTheme.textSecondary,
        NSParagraphStyleAttributeName: ps,
    }];
    [s appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n发送好友申请" attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:12 weight:UIFontWeightMedium],
        NSForegroundColorAttributeName: IMTheme.accent,
        NSParagraphStyleAttributeName: ps,
    }]];
    _label.attributedText = s;
}

- (void)handleTap {
    if (_actionable && self.onActionTap) { self.onActionTap(); }
}

@end
