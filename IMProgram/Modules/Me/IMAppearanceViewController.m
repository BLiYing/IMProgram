//  IMAppearanceViewController.m
//  Telegram 风格外观设置：预览 + 显示模式/主题/壁纸/字号/圆角/动画/应用图标。

#import "IMAppearanceViewController.h"
#import "IMAppearance.h"
#import "IMChatBackgroundView.h"
#import "IMTheme.h"
#import "UIViewController+IMToast.h"

@interface IMAppearancePreviewView : UIView
- (void)refresh;
@end

@interface IMBubblePreviewLabel : UILabel
@end

@implementation IMBubblePreviewLabel
- (CGSize)intrinsicContentSize {
    CGSize size = [super intrinsicContentSize];
    return CGSizeMake(size.width + 26, size.height + 20);
}
- (void)drawTextInRect:(CGRect)rect {
    [super drawTextInRect:UIEdgeInsetsInsetRect(rect, UIEdgeInsetsMake(10, 13, 10, 13))];
}
@end

@implementation IMAppearancePreviewView {
    IMChatBackgroundView *_background;
    UILabel *_incoming;
    UILabel *_outgoing;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.layer.cornerRadius = 22;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.masksToBounds = YES;
        _background = [IMChatBackgroundView new];
        _background.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_background];
        _incoming = [self bubble:@"收到，新主题看起来很舒服。"];
        _outgoing = [self bubble:@"现在可以随心定制聊天啦 ✓✓"];
        [self addSubview:_incoming];
        [self addSubview:_outgoing];
        [NSLayoutConstraint activateConstraints:@[
            [_background.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_background.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_background.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_background.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_incoming.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
            [_incoming.topAnchor constraintEqualToAnchor:self.topAnchor constant:34],
            [_incoming.widthAnchor constraintLessThanOrEqualToAnchor:self.widthAnchor multiplier:0.72],
            [_outgoing.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
            [_outgoing.topAnchor constraintEqualToAnchor:_incoming.bottomAnchor constant:14],
            [_outgoing.widthAnchor constraintLessThanOrEqualToAnchor:self.widthAnchor multiplier:0.78],
        ]];
        [self refresh];
    }
    return self;
}

- (UILabel *)bubble:(NSString *)text {
    UILabel *label = [IMBubblePreviewLabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    label.numberOfLines = 0;
    label.textColor = IMTheme.textPrimary;
    label.layer.masksToBounds = YES;
    return label;
}

- (void)refresh {
    _incoming.backgroundColor = IMTheme.bubbleThem;
    _outgoing.backgroundColor = IMTheme.bubbleMe;
    _incoming.font = [UIFont systemFontOfSize:IMTheme.chatFontSize];
    _outgoing.font = [UIFont systemFontOfSize:IMTheme.chatFontSize];
    _incoming.layer.cornerRadius = IMAppearance.shared.bubbleRadius;
    _outgoing.layer.cornerRadius = IMAppearance.shared.bubbleRadius;
    [_background refreshAppearance];
}

@end

@interface IMAppearanceViewController ()
@property (nonatomic, strong) IMAppearancePreviewView *preview;
@property (nonatomic, strong) UILabel *fontValue;
@property (nonatomic, strong) UILabel *radiusValue;
@end

@implementation IMAppearanceViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"外观";
    self.view.backgroundColor = IMTheme.groupedBackground;
    self.tableView.rowHeight = 58;
    self.tableView.sectionHeaderTopPadding = 12;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"还原" style:UIBarButtonItemStylePlain target:self action:@selector(resetTapped)];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appearanceChanged)
                                               name:IMAppearanceDidChangeNotification object:nil];

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1, 236)];
    self.preview = [IMAppearancePreviewView new];
    self.preview.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:self.preview];
    [NSLayoutConstraint activateConstraints:@[
        [self.preview.topAnchor constraintEqualToAnchor:header.topAnchor constant:12],
        [self.preview.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-12],
        [self.preview.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [self.preview.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
    ]];
    self.tableView.tableHeaderView = header;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 7; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 1; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"显示模式", @"聊天主题", @"聊天壁纸", @"聊天字号", @"信息框圆角", @"动效", @"应用图标"][section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (indexPath.section == 0) {
        UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"系统", @"浅色", @"深色"]];
        seg.selectedSegmentIndex = IMAppearance.shared.mode;
        [seg addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = seg;
        cell.textLabel.text = @"界面";
    } else if (indexPath.section == 1) {
        UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"经典", @"海洋", @"紫晶", @"深海"]];
        NSArray *ids = @[@"classic", @"ocean", @"violet", @"midnight"];
        NSUInteger selected = [ids indexOfObject:IMAppearance.shared.themeID];
        seg.selectedSegmentIndex = selected == NSNotFound ? 0 : selected;
        [seg addTarget:self action:@selector(themeChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = seg;
    } else if (indexPath.section == 2) {
        UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"涂鸦", @"渐变", @"纯色"]];
        NSArray *ids = @[@"doodle", @"gradient", @"plain"];
        NSUInteger selected = [ids indexOfObject:IMAppearance.shared.wallpaperID];
        seg.selectedSegmentIndex = selected == NSNotFound ? 0 : selected;
        [seg addTarget:self action:@selector(wallpaperChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = seg;
    } else if (indexPath.section == 3) {
        cell.textLabel.text = @"Aa";
        UISlider *slider = [self sliderWithMin:14 max:22 value:IMAppearance.shared.chatFontSize action:@selector(fontChanged:)];
        cell.accessoryView = [self sliderContainer:slider value:&_fontValue text:[NSString stringWithFormat:@"%.0f", IMAppearance.shared.chatFontSize]];
    } else if (indexPath.section == 4) {
        cell.textLabel.text = @"圆角";
        UISlider *slider = [self sliderWithMin:6 max:24 value:IMAppearance.shared.bubbleRadius action:@selector(radiusChanged:)];
        cell.accessoryView = [self sliderContainer:slider value:&_radiusValue text:[NSString stringWithFormat:@"%.0f", IMAppearance.shared.bubbleRadius]];
    } else if (indexPath.section == 5) {
        cell.textLabel.text = @"界面动画";
        UISwitch *toggle = [UISwitch new];
        toggle.on = IMAppearance.shared.animationsEnabled;
        [toggle addTarget:self action:@selector(animationChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    } else {
        cell.textLabel.text = @"选择图标";
        UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"默认", @"蓝色", @"紫色", @"深色"]];
        NSArray *names = @[@"", @"AppIconOcean", @"AppIconViolet", @"AppIconMidnight"];
        NSString *current = UIApplication.sharedApplication.alternateIconName ?: @"";
        NSUInteger selected = [names indexOfObject:current];
        seg.selectedSegmentIndex = selected == NSNotFound ? 0 : selected;
        [seg addTarget:self action:@selector(iconChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = seg;
    }
    return cell;
}

- (UISlider *)sliderWithMin:(CGFloat)min max:(CGFloat)max value:(CGFloat)value action:(SEL)action {
    UISlider *slider = [UISlider new];
    slider.minimumValue = min; slider.maximumValue = max; slider.value = value;
    slider.continuous = YES;
    [slider addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    return slider;
}

- (UIView *)sliderContainer:(UISlider *)slider value:(UILabel * __strong *)output text:(NSString *)text {
    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 220, 44)];
    slider.frame = CGRectMake(0, 4, 178, 36);
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(184, 0, 36, 44)];
    label.textAlignment = NSTextAlignmentRight; label.textColor = IMTheme.textSecondary; label.text = text;
    [box addSubview:slider]; [box addSubview:label];
    *output = label;
    return box;
}

- (void)modeChanged:(UISegmentedControl *)sender { IMAppearance.shared.mode = sender.selectedSegmentIndex; }
- (void)themeChanged:(UISegmentedControl *)sender {
    IMAppearance.shared.themeID = @[@"classic", @"ocean", @"violet", @"midnight"][sender.selectedSegmentIndex];
}
- (void)wallpaperChanged:(UISegmentedControl *)sender {
    IMAppearance.shared.wallpaperID = @[@"doodle", @"gradient", @"plain"][sender.selectedSegmentIndex];
}
- (void)fontChanged:(UISlider *)sender {
    CGFloat value = round(sender.value);
    IMAppearance.shared.chatFontSize = value; self.fontValue.text = [NSString stringWithFormat:@"%.0f", value];
}
- (void)radiusChanged:(UISlider *)sender {
    CGFloat value = round(sender.value);
    IMAppearance.shared.bubbleRadius = value; self.radiusValue.text = [NSString stringWithFormat:@"%.0f", value];
}
- (void)animationChanged:(UISwitch *)sender { IMAppearance.shared.animationsEnabled = sender.on; }

- (void)iconChanged:(UISegmentedControl *)sender {
    NSArray *names = @[[NSNull null], @"AppIconOcean", @"AppIconViolet", @"AppIconMidnight"];
    id selected = names[sender.selectedSegmentIndex];
    NSString *name = selected == NSNull.null ? nil : selected;
    if (!UIApplication.sharedApplication.supportsAlternateIcons) {
        [self im_showToast:@"当前系统不支持切换图标"];
        return;
    }
    [UIApplication.sharedApplication setAlternateIconName:name completionHandler:^(NSError *error) {
        if (error) { dispatch_async(dispatch_get_main_queue(), ^{ [self im_showToast:error.localizedDescription]; }); }
    }];
}

- (void)appearanceChanged {
    [self.preview refresh];
    self.view.backgroundColor = IMTheme.groupedBackground;
}

- (void)resetTapped {
    [IMAppearance.shared resetToDefaults];
    [self.tableView reloadData];
    [self.preview refresh];
}

@end
