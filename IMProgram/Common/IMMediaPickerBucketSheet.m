//  IMMediaPickerBucketSheet.m

#import "IMMediaPickerBucketSheet.h"
#import "IMMediaPickerPhotos.h"
#import "IMTheme.h"

static const CGFloat kRowCover = 48;
static const CGFloat kSheetMaxHeight = 360;
static NSString * const kBucketCellID = @"bucket";

@interface IMMediaBucketCell : UITableViewCell
@property (nonatomic, copy, nullable) NSString *bucketID;
@property (nonatomic, assign) int32_t requestID;
@property (nonatomic, strong, readonly) UIImageView *cover;
@property (nonatomic, strong, readonly) UILabel *countLabel;
@end

@implementation IMMediaBucketCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = IMTheme.surfaceElevated;
        self.selectionStyle = UITableViewCellSelectionStyleDefault;
        _cover = [UIImageView new];
        _cover.contentMode = UIViewContentModeScaleAspectFill;
        _cover.clipsToBounds = YES;
        _cover.layer.cornerRadius = 4;
        _cover.backgroundColor = UIColor.tertiarySystemFillColor;
        _cover.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_cover];
        self.textLabel.font = [UIFont systemFontOfSize:15];
        self.textLabel.textColor = IMTheme.textPrimary;
        self.textLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _countLabel = [UILabel new];
        _countLabel.font = [UIFont systemFontOfSize:13];
        _countLabel.textColor = IMTheme.textSecondary;
        _countLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_countLabel];
        [NSLayoutConstraint activateConstraints:@[
            [_cover.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_cover.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
            [_cover.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8],
            [_cover.widthAnchor constraintEqualToConstant:kRowCover],
            [_cover.heightAnchor constraintEqualToConstant:kRowCover],
            [self.textLabel.leadingAnchor constraintEqualToAnchor:_cover.trailingAnchor constant:12],
            [self.textLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_countLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.textLabel.trailingAnchor constant:8],
            [_countLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [_countLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        ]];
    }
    return self;
}
@end

@interface IMMediaPickerBucketSheet () <UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate>
@end

@implementation IMMediaPickerBucketSheet {
    NSArray<IMMediaPickBucket *> *_buckets;
    UITableView *_table;
    NSLayoutConstraint *_tableHeight;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.4]; // overlay
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissTapped)];
        tap.delegate = self;
        [self addGestureRecognizer:tap];
        _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
        _table.backgroundColor = IMTheme.surfaceElevated;
        _table.dataSource = self;
        _table.delegate = self;
        _table.rowHeight = kRowCover + 16;
        _table.separatorStyle = UITableViewCellSeparatorStyleNone;
        _table.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_table];
        _tableHeight = [_table.heightAnchor constraintEqualToConstant:0];
        [NSLayoutConstraint activateConstraints:@[
            [_table.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_table.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_table.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            _tableHeight,
        ]];
    }
    return self;
}

- (void)setBuckets:(NSArray<IMMediaPickBucket *> *)buckets {
    _buckets = [buckets copy];
    _tableHeight.constant = MIN(kSheetMaxHeight, buckets.count * _table.rowHeight);
    [_table reloadData];
}

- (void)dismissTapped { if (self.onDismiss) { self.onDismiss(); } }

// 点在面板列表之外才收起（列表自己的点击由 table 处理）。
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    return ![touch.view isDescendantOfView:_table];
}

#pragma mark UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return (NSInteger)_buckets.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMMediaBucketCell *cell = [tableView dequeueReusableCellWithIdentifier:kBucketCellID];
    if (!cell) { cell = [[IMMediaBucketCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kBucketCellID]; }
    IMMediaPickBucket *b = _buckets[indexPath.row];
    cell.bucketID = b.bucketID;
    cell.textLabel.text = b.title;
    cell.countLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)b.assets.count];
    cell.cover.image = nil;
    if (cell.requestID != PHInvalidImageRequestID) { [IMMediaPickerPhotos.cachingManager cancelImageRequest:cell.requestID]; }
    PHAsset *coverAsset = b.cover;
    if (coverAsset) {
        CGFloat scale = UIScreen.mainScreen.scale;
        __weak IMMediaBucketCell *weakCell = cell;
        NSString *bucketID = b.bucketID;
        cell.requestID = [IMMediaPickerPhotos.cachingManager requestImageForAsset:coverAsset
            targetSize:CGSizeMake(kRowCover * scale, kRowCover * scale) contentMode:PHImageContentModeAspectFill
            options:IMMediaPickerPhotos.thumbnailOptions resultHandler:^(UIImage *image, NSDictionary *info) {
            if ([weakCell.bucketID isEqualToString:bucketID]) { weakCell.cover.image = image; }
        }];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.onPick) { self.onPick(_buckets[indexPath.row].bucketID); }
}

@end
