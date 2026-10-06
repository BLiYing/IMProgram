//  IMMediaPickerCell.m

#import "IMMediaPickerCell.h"
#import "IMMediaPickLogic.h"
#import "IMTheme.h"

static const CGFloat kBadgeInset = 4;      // 编号圆 / 时长角标距格边
static const CGFloat kBadgeSize = 22;      // 编号圆直径（Android MediaTile 22dp）
static const CGFloat kDimmedAlpha = 0.35;  // 不可选格的缩略图透明度

@implementation IMMediaPickerCell {
    UIImageView *_imageView;
    UIView *_selectionDim;
    UILabel *_numberLabel;
    UILabel *_durationLabel;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.contentView.backgroundColor = UIColor.tertiarySystemFillColor; // 缩略图未加载时的底色（subtleFill）
        self.contentView.clipsToBounds = YES;

        _imageView = [UIImageView new];
        _imageView.contentMode = UIViewContentModeScaleAspectFill;
        _imageView.clipsToBounds = YES;
        [self.contentView addSubview:_imageView];

        _selectionDim = [UIView new];
        _selectionDim.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.4]; // overlay：仅媒体场景
        _selectionDim.hidden = YES;
        [self.contentView addSubview:_selectionDim];

        _durationLabel = [UILabel new];
        _durationLabel.font = [UIFont systemFontOfSize:10];
        _durationLabel.textColor = IMTheme.mediaBadgeText;
        _durationLabel.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.4];
        _durationLabel.layer.cornerRadius = 3;
        _durationLabel.clipsToBounds = YES;
        _durationLabel.textAlignment = NSTextAlignmentCenter;
        _durationLabel.hidden = YES;
        [self.contentView addSubview:_durationLabel];

        _numberLabel = [UILabel new];
        _numberLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        _numberLabel.textColor = UIColor.whiteColor; // onAccent
        _numberLabel.textAlignment = NSTextAlignmentCenter;
        _numberLabel.layer.cornerRadius = kBadgeSize / 2;
        _numberLabel.clipsToBounds = YES;
        [self.contentView addSubview:_numberLabel];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.contentView.bounds;
    _imageView.frame = b;
    _selectionDim.frame = b;
    _numberLabel.frame = CGRectMake(CGRectGetWidth(b) - kBadgeInset - kBadgeSize, kBadgeInset, kBadgeSize, kBadgeSize);
    CGSize fit = [_durationLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
    CGFloat w = fit.width + 8, h = fit.height + 2; // 内边距 横 4 竖 1
    _durationLabel.frame = CGRectMake(CGRectGetWidth(b) - kBadgeInset - w, CGRectGetHeight(b) - kBadgeInset - h, w, h);
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.assetID = nil;
    _imageView.image = nil;
}

- (void)setThumbnail:(nullable UIImage *)image { _imageView.image = image; }

- (void)configureWithNumber:(NSInteger)number videoDuration:(NSTimeInterval)duration dimmed:(BOOL)dimmed {
    BOOL selected = number > 0;
    _selectionDim.hidden = !selected;
    _imageView.alpha = dimmed ? kDimmedAlpha : 1;
    _numberLabel.text = selected ? [NSString stringWithFormat:@"%ld", (long)number] : nil;
    // 未选 = 黑 40% 填充；已选 = accent 填充 + 编号（Android MediaTile 同）
    _numberLabel.backgroundColor = selected ? IMTheme.accent : [UIColor.blackColor colorWithAlphaComponent:0.4];
    BOOL isVideo = duration >= 0;
    _durationLabel.hidden = !isVideo;
    if (isVideo) {
        _durationLabel.text = [@"▶ " stringByAppendingString:[IMMediaPickLogic durationLabelForSeconds:duration]];
        [self setNeedsLayout];
    }
}

@end
