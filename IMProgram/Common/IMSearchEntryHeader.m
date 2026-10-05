//  IMSearchEntryHeader.m

#import "IMSearchEntryHeader.h"
#import "IMGlass.h"
#import "IMTheme.h"

const CGFloat kIMSearchEntryHeaderHeight = 56;

UIView *IMMakeSearchEntryHeader(CGFloat width, NSString *placeholder, id target, SEL action) {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, kIMSearchEntryHeaderHeight)];
    UIVisualEffectView *capsule = IMGlassEffectView(NO);
    capsule.frame = CGRectMake(16, 6, width - 32, 44);
    capsule.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    capsule.layer.cornerRadius = kIMSearchFieldCornerRadius;
    capsule.layer.cornerCurve = kCACornerCurveContinuous;
    capsule.clipsToBounds = YES;
    UIImageView *mag = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:@"magnifyingglass"
                withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightMedium]]];
    mag.tintColor = IMTheme.textSecondary;
    mag.frame = CGRectMake(14, 13, 18, 18);
    [capsule.contentView addSubview:mag];
    UILabel *ph = [UILabel new];
    ph.text = placeholder;
    ph.font = [UIFont systemFontOfSize:17];          // 同 searchMode 输入框字号
    ph.textColor = IMTheme.textSecondary;             // 同占位色
    ph.frame = CGRectMake(38, 0, 240, 44);
    ph.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [capsule.contentView addSubview:ph];
    [header addSubview:capsule];
    [header addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:target action:action]];
    header.isAccessibilityElement = YES;
    header.accessibilityLabel = placeholder;
    header.accessibilityTraits = UIAccessibilityTraitSearchField | UIAccessibilityTraitButton;
    return header;
}
