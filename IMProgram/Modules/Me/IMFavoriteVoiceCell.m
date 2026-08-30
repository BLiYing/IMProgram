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
@property (nonatomic, strong) UILabel *timeLabel;         ///< 收藏时间（tertiary）
@property (nonatomic, strong) UILabel *sourceLabel;      ///< "来自X"（accent，与链接分类来源行同色）
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

    // 时间与「来自X」分两行、颜色分开：长备注名/群昵称会把单行「来自X · 年月日时分」的时间挤出屏幕。
    _timeLabel = [UILabel new];
    _timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _timeLabel.font = [UIFont systemFontOfSize:12];
    _timeLabel.textColor = IMTheme.textTertiary;
    [cv addSubview:_timeLabel];

    _sourceLabel = [UILabel new];
    _sourceLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _sourceLabel.font = [UIFont systemFontOfSize:12];
    _sourceLabel.textColor = IMTheme.accent;
    _sourceLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [cv addSubview:_sourceLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_mini.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:16],
        [_mini.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-16],
        [_mini.topAnchor constraintEqualToAnchor:cv.topAnchor constant:12],
        [_mini.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        [_timeLabel.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:16],
        [_timeLabel.trailingAnchor constraintLessThanOrEqualToAnchor:cv.trailingAnchor constant:-16],
        [_timeLabel.topAnchor constraintEqualToAnchor:_mini.bottomAnchor constant:6],
        [_sourceLabel.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:16],
        [_sourceLabel.trailingAnchor constraintLessThanOrEqualToAnchor:cv.trailingAnchor constant:-16],
        [_sourceLabel.topAnchor constraintEqualToAnchor:_timeLabel.bottomAnchor constant:2],
        [_sourceLabel.bottomAnchor constraintLessThanOrEqualToAnchor:cv.bottomAnchor constant:-8],
    ]];
}

- (void)configureWithMessage:(IMMessageModel *)message sourceText:(NSString *)sourceText timeText:(NSString *)timeText {
    // 收藏 = 对方视角展示（mine=NO 不显勾）；peerReadSeq/isGroup 无关。
    [self.mini configureWithMessage:message mine:NO peerReadSeq:0 isGroupContext:NO];
    self.timeLabel.text = timeText ?: @"";
    self.sourceLabel.text = sourceText.length > 0 ? [@"来自" stringByAppendingString:sourceText] : nil;
    __weak typeof(self) ws = self;
    self.mini.onPlayTap = ^{ __strong typeof(ws) sself = ws; if (sself && sself->_onPlayTap) { sself->_onPlayTap(); } };
}

@end
