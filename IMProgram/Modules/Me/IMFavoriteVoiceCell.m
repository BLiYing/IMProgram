//
//  IMFavoriteVoiceCell.m
//  重构（2026-08-27）：复用 IMVoiceMiniPlayerView，不再平行实现 playButton+waveform+durationLabel
//  三件套（code-review reuse #10）。整个 cell 只剩"上面装 mini 播放器 + 下方 meta 行"两块。
//

#import "IMFavoriteVoiceCell.h"
#import "IMMessageModel.h"
#import "IMTheme.h"
#import "IMTimeUtil.h"
#import "IMVoiceMiniPlayerView.h"

@interface IMFavoriteVoiceCell ()
@property (nonatomic, strong) IMVoiceMiniPlayerView *mini; ///< ▶+波形+时长/时间——与详情页语音 tab 共用组件
@property (nonatomic, strong) UILabel *metaLabel;         ///< "来自 X · 收藏时间"
@end

@implementation IMFavoriteVoiceCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        [self buildUI];
    }
    return self;
}

- (void)buildUI {
    UIView *cv = self.contentView;

    _mini = [IMVoiceMiniPlayerView new];
    _mini.translatesAutoresizingMaskIntoConstraints = NO;
    [cv addSubview:_mini];

    _metaLabel = [UILabel new];
    _metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _metaLabel.font = [UIFont systemFontOfSize:12];
    _metaLabel.textColor = IMTheme.textSecondary;
    [cv addSubview:_metaLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_mini.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:16],
        [_mini.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-16],
        [_mini.topAnchor constraintEqualToAnchor:cv.topAnchor constant:12],
        [_mini.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        [_metaLabel.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:16],
        [_metaLabel.trailingAnchor constraintLessThanOrEqualToAnchor:cv.trailingAnchor constant:-16],
        [_metaLabel.topAnchor constraintEqualToAnchor:_mini.bottomAnchor constant:6],
        [_metaLabel.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-10],
    ]];
}

- (void)configureWithMessage:(IMMessageModel *)message sourceText:(NSString *)sourceText timeText:(NSString *)timeText {
    // 收藏 = 对方视角展示（mine=NO 不显勾）；peerReadSeq/isGroup 无关。
    [self.mini configureWithMessage:message mine:NO peerReadSeq:0 isGroupContext:NO];
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (sourceText.length > 0) { [parts addObject:[@"来自" stringByAppendingString:sourceText]]; }
    if (timeText.length > 0) { [parts addObject:timeText]; }
    self.metaLabel.text = [parts componentsJoinedByString:@" · "];
    __weak typeof(self) ws = self;
    self.mini.onPlayTap = ^{ __strong typeof(ws) sself = ws; if (sself && sself->_onPlayTap) { sself->_onPlayTap(); } };
}

@end
