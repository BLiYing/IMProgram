//
//  IMFavoriteVoiceCell.m
//

#import "IMFavoriteVoiceCell.h"
#import "IMMessageModel.h"
#import "IMTheme.h"
#import "IMWaveformView.h"
#import "IMVoicePlayer.h"

@interface IMFavoriteVoiceCell ()
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) IMWaveformView *waveform;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, copy, nullable) NSString *messageID;
@property (nonatomic, assign) int64_t totalDurationMillis;
@end

@implementation IMFavoriteVoiceCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        [self buildUI];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onPlayerChanged:)
                                                     name:IMVoicePlayerDidChangeStateNotification object:nil];
    }
    return self;
}

- (void)buildUI {
    UIView *cv = self.contentView;

    _playButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _playButton.translatesAutoresizingMaskIntoConstraints = NO;
    _playButton.backgroundColor = IMTheme.accent;
    _playButton.tintColor = UIColor.whiteColor;
    _playButton.layer.cornerRadius = 18;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightBold];
    [_playButton setImage:[UIImage systemImageNamed:@"play.fill" withConfiguration:cfg] forState:UIControlStateNormal];
    [_playButton addTarget:self action:@selector(playTapped) forControlEvents:UIControlEventTouchUpInside];
    [cv addSubview:_playButton];

    _waveform = [IMWaveformView new];
    _waveform.translatesAutoresizingMaskIntoConstraints = NO;
    _waveform.activeColor = IMTheme.accent;
    _waveform.inactiveColor = [IMTheme.textSecondary colorWithAlphaComponent:0.45];
    [cv addSubview:_waveform];

    _durationLabel = [UILabel new];
    _durationLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _durationLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    _durationLabel.textColor = IMTheme.textSecondary;
    [_durationLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [cv addSubview:_durationLabel];

    _metaLabel = [UILabel new];
    _metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _metaLabel.font = [UIFont systemFontOfSize:12];
    _metaLabel.textColor = IMTheme.textSecondary;
    [cv addSubview:_metaLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_playButton.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:16],
        [_playButton.topAnchor constraintEqualToAnchor:cv.topAnchor constant:14],
        [_playButton.widthAnchor constraintEqualToConstant:36],
        [_playButton.heightAnchor constraintEqualToConstant:36],
        [_waveform.leadingAnchor constraintEqualToAnchor:_playButton.trailingAnchor constant:10],
        [_waveform.centerYAnchor constraintEqualToAnchor:_playButton.centerYAnchor],
        [_waveform.heightAnchor constraintEqualToConstant:26],
        [_waveform.trailingAnchor constraintEqualToAnchor:_durationLabel.leadingAnchor constant:-10],
        [_durationLabel.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-16],
        [_durationLabel.centerYAnchor constraintEqualToAnchor:_playButton.centerYAnchor],
        [_metaLabel.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:16],
        [_metaLabel.trailingAnchor constraintLessThanOrEqualToAnchor:cv.trailingAnchor constant:-16],
        [_metaLabel.topAnchor constraintEqualToAnchor:_playButton.bottomAnchor constant:9],
    ]];
}

- (void)configureWithMessage:(IMMessageModel *)message sourceText:(NSString *)sourceText timeText:(NSString *)timeText {
    self.messageID = IMVoicePlayerPlayableIDForMessage(message);
    self.totalDurationMillis = MAX((int64_t)0, message.duration);
    self.waveform.amplitudes = [IMWaveformView amplitudesFromBase64:message.waveform];
    self.waveform.progress = 0;
    self.durationLabel.text = [self formatDur:self.totalDurationMillis];
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (sourceText.length > 0) { [parts addObject:[@"来自" stringByAppendingString:sourceText]]; }
    if (timeText.length > 0) { [parts addObject:timeText]; }
    self.metaLabel.text = [parts componentsJoinedByString:@" · "];
    // 同步当前播放器状态（列表滚动复用时保持进度/图标）。
    IMVoicePlayerState st = [[IMVoicePlayer sharedPlayer] stateForMessageID:self.messageID];
    [self applyState:st progress:[[IMVoicePlayer sharedPlayer] progressForMessageID:self.messageID]];
}

- (NSString *)formatDur:(int64_t)ms {
    NSInteger s = MAX(0, (NSInteger)(ms / 1000));
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(s / 60), (long)(s % 60)];
}

- (void)playTapped { if (self.onPlayTap) { self.onPlayTap(); } }

- (void)onPlayerChanged:(NSNotification *)n {
    NSString *mid = n.userInfo[@"messageID"];
    if (!mid || ![mid isEqualToString:self.messageID]) { return; }
    [self applyState:(IMVoicePlayerState)[n.userInfo[@"state"] integerValue]
            progress:[n.userInfo[@"progress"] doubleValue]];
}

- (void)applyState:(IMVoicePlayerState)state progress:(double)progress {
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightBold];
    NSString *sym = (state == IMVoicePlayerStatePlaying) ? @"pause.fill" : @"play.fill";
    [self.playButton setImage:[UIImage systemImageNamed:sym withConfiguration:cfg] forState:UIControlStateNormal];
    BOOL active = (state == IMVoicePlayerStatePlaying || state == IMVoicePlayerStatePaused);
    self.waveform.progress = active ? progress : 0;
    int64_t shown = active
        ? MAX((int64_t)0, self.totalDurationMillis - (int64_t)(progress * self.totalDurationMillis))
        : self.totalDurationMillis;
    self.durationLabel.text = [self formatDur:shown];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
