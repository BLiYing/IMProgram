//  IMCircleCheckbox.m

#import "IMCircleCheckbox.h"
#import "IMTheme.h"

@implementation IMCircleCheckbox

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.contentMode = UIViewContentModeScaleAspectFit;
        self.preferredSymbolConfiguration =
            [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular];
        _checked = NO;
        [self applyState]; // 初始为未选空心圈
    }
    return self;
}

// 覆写合成 setter：改 ivar + 刷新外观。内部用 _checked，不走 self.checked（避免自递归）。
- (void)setChecked:(BOOL)checked {
    _checked = checked;
    [self applyState];
}

- (void)applyState {
    self.image = [UIImage systemImageNamed:(_checked ? @"checkmark.circle.fill" : @"circle")];
    self.tintColor = _checked ? IMTheme.accent : IMTheme.textSecondary;
}

@end
