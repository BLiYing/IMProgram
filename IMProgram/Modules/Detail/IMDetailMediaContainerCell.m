//  IMDetailMediaContainerCell.m

#import "IMDetailMediaContainerCell.h"
#import "IMConversationMediaViewController.h"  // IMMediaItem
#import "IMMediaTileCell.h"
#import "IMDownloadProgress.h"

@interface IMDetailMediaContainerCell () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@end

@implementation IMDetailMediaContainerCell {
    UICollectionView *_cv; NSArray<IMMediaItem *> *_items;
    CGFloat _lastReportedWidth; // 已上报给外部的内容宽（去抖，避免每次布局都回调）
}

/// 内容宽首次确定/变化时上报（旋转、iPad 分屏）。
/// 存在的理由：行高由外部按「假设的 InsetGrouped 内缩」估算，而格子按 cell 真实宽度排布；
/// 两者一旦不一致，行高就会比宫格内容高出几 pt，卡片底部露出白边。以真实宽度为准即可消除。
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    if (w > 0 && ABS(w - _lastReportedWidth) > 0.5) {
        _lastReportedWidth = w;
        if (self.onContentWidthChanged) { self.onContentWidthChanged(w); }
    }
}
+ (CGFloat)tileForWidth:(CGFloat)width { CGFloat cols = 3, sp = 2; return floor((width - (cols - 1) * sp) / cols); }
+ (CGFloat)heightForCount:(NSInteger)count width:(CGFloat)width {
    if (count == 0) { return 0; }
    CGFloat tile = [self tileForWidth:width];
    NSInteger rows = (count + 2) / 3;
    return rows * tile + (rows - 1) * 2;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
        UICollectionViewFlowLayout *l = [UICollectionViewFlowLayout new];
        l.minimumInteritemSpacing = 2; l.minimumLineSpacing = 2;
        _cv = [[UICollectionView alloc] initWithFrame:self.contentView.bounds collectionViewLayout:l];
        _cv.backgroundColor = UIColor.clearColor; _cv.scrollEnabled = NO;
        _cv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _cv.dataSource = self; _cv.delegate = self;
        [_cv registerClass:IMMediaTileCell.class forCellWithReuseIdentifier:@"g"];
        [self.contentView addSubview:_cv];
    }
    return self;
}
- (void)setItems:(NSArray<IMMediaItem *> *)items { _items = items; [_cv reloadData]; }
- (void)refreshItemAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_items.count) { return; }
    [_cv reloadItemsAtIndexPaths:@[[NSIndexPath indexPathForItem:index inSection:0]]];
}
- (void)updateItemAtIndex:(NSInteger)index download:(IMDownloadProgress *)dp {
    if (index < 0 || index >= (NSInteger)_items.count) { return; }
    IMMediaTileCell *c = (IMMediaTileCell *)[_cv cellForItemAtIndexPath:[NSIndexPath indexPathForItem:index inSection:0]];
    if ([c isKindOfClass:IMMediaTileCell.class]) { [c updateDownload:dp]; }
}
- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s { return _items.count; }
- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    IMMediaTileCell *c = [cv dequeueReusableCellWithReuseIdentifier:@"g" forIndexPath:ip];
    IMDownloadProgress *dp = self.stateForItemIndex ? self.stateForItemIndex(ip.item) : nil;
    NSString *thumb = (dp && self.thumbForItemIndex) ? self.thumbForItemIndex(ip.item) : nil;
    [c configureWithItem:_items[ip.item] download:dp thumb:thumb];
    // pick 模式勾选框（收藏「从收藏发送」）：configure 之后覆盖设置，避免被 prepareForReuse 清掉。
    if (self.pickMode) {
        BOOL on = self.isItemSelectedAtIndex ? self.isItemSelectedAtIndex(ip.item) : NO;
        NSInteger idx = ip.item;
        __weak typeof(self) ws = self;
        [c setPickMode:YES selected:on onCheckboxTap:^{
            __strong typeof(ws) ss = ws;
            if (ss && ss.onToggleSelectionAtIndex) { ss.onToggleSelectionAtIndex(idx); }
        }];
    } else {
        [c setPickMode:NO selected:NO onCheckboxTap:nil];
    }
    return c;
}
- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)l sizeForItemAtIndexPath:(NSIndexPath *)ip {
    CGFloat t = [IMDetailMediaContainerCell tileForWidth:cv.bounds.size.width];
    return CGSizeMake(t, t);
}
- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    // 门控格：点击=就地下载（铁律①不跳页），**不**进查看器；就绪格才打开（铁律②完成即止）。
    IMDownloadProgress *dp = self.stateForItemIndex ? self.stateForItemIndex(ip.item) : nil;
    if (dp && dp.phase != IMDownloadPhaseDone) {
        if (self.onDownloadItemIndex) { self.onDownloadItemIndex(ip.item); }
        return;
    }
    if (self.onPick) { self.onPick(_items[ip.item]); }
}
/// 逐格长按菜单（任务2）：转发/定位/取消下载/删除——与文件行同一套，由 VC 按该格消息构造。
- (UIContextMenuConfiguration *)collectionView:(UICollectionView *)cv
    contextMenuConfigurationForItemAtIndexPath:(NSIndexPath *)ip point:(CGPoint)point {
    return self.contextMenuForItemIndex ? self.contextMenuForItemIndex(ip.item) : nil;
}
@end
