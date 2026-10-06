//  IMMediaPickSession.m

#import "IMMediaPickSession.h"
#import "IMMediaPickLogic.h"
#import "IMMediaPickerPhotos.h"

@implementation IMMediaPickSession {
    NSArray<NSString *> *_selectedIDs;
    NSMutableDictionary<NSString *, PHAsset *> *_assetsByID;
    NSMutableDictionary<NSString *, NSNumber *> *_sizes;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _selectedIDs = @[];
        _assetsByID = [NSMutableDictionary dictionary];
        _sizes = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSArray<NSString *> *)selectedIDs { return _selectedIDs; }

- (BOOL)toggleAsset:(PHAsset *)asset {
    NSArray<NSString *> *next = [IMMediaPickLogic toggledSelection:_selectedIDs
                                                           assetID:asset.localIdentifier
                                                             limit:kIMMediaPickLimit];
    if (!next) { return NO; }
    _selectedIDs = next;
    if ([next containsObject:asset.localIdentifier]) {
        _assetsByID[asset.localIdentifier] = asset;
        _sizes[asset.localIdentifier] = @([self sizeBytesOfAsset:asset]);
    }
    return YES;
}

- (NSInteger)numberOfAsset:(PHAsset *)asset {
    return [IMMediaPickLogic numberOfAssetID:asset.localIdentifier inSelection:_selectedIDs];
}

- (long long)sizeBytesOfAsset:(PHAsset *)asset {
    return [IMMediaPickerPhotos sizeBytesOfAsset:asset];
}

- (BOOL)isSelectableAsset:(PHAsset *)asset {
    // 图片不可能超 2GB，省掉一次资源查询；只有视频才按体积判定（点击时同步取，之后命中缓存）。
    if (asset.mediaType != PHAssetMediaTypeVideo) { return YES; }
    return [IMMediaPickLogic isSelectableWithSizeBytes:[self sizeBytesOfAsset:asset]];
}

- (BOOL)isDimmedAsset:(PHAsset *)asset {
    if (asset.mediaType != PHAssetMediaTypeVideo) { return NO; }
    NSNumber *cached = [IMMediaPickerPhotos cachedSizeBytesOfAsset:asset]; // 只看缓存：格子绘制路径不能同步查资源
    return cached && ![IMMediaPickLogic isSelectableWithSizeBytes:cached.longLongValue];
}

- (long long)totalBytes {
    return [IMMediaPickLogic totalBytesForSelection:_selectedIDs sizes:_sizes];
}

- (BOOL)pruneUnavailableSelection {
    if (_selectedIDs.count == 0) { return NO; }
    NSMutableSet<NSString *> *alive = [NSMutableSet set];
    PHFetchResult<PHAsset *> *found = [PHAsset fetchAssetsWithLocalIdentifiers:_selectedIDs options:nil];
    [found enumerateObjectsUsingBlock:^(PHAsset *a, NSUInteger idx, BOOL *stop) { [alive addObject:a.localIdentifier]; }];
    NSMutableArray<NSString *> *kept = [NSMutableArray arrayWithCapacity:_selectedIDs.count];
    for (NSString *assetID in _selectedIDs) {
        if ([alive containsObject:assetID]) { [kept addObject:assetID]; }
    }
    if (kept.count == _selectedIDs.count) { return NO; }
    _selectedIDs = [kept copy];
    return YES;
}

- (NSArray<PHAsset *> *)orderedAssets {
    // 选中后、发送前相册里可能删了东西：以相册当前存在的为准（缺失的直接跳过，不把已删资源交给下游）。
    PHFetchResult<PHAsset *> *alive = [PHAsset fetchAssetsWithLocalIdentifiers:_selectedIDs options:nil];
    NSMutableSet<NSString *> *aliveIDs = [NSMutableSet setWithCapacity:alive.count];
    for (PHAsset *a in alive) { [aliveIDs addObject:a.localIdentifier]; }
    NSMutableArray<PHAsset *> *out = [NSMutableArray arrayWithCapacity:_selectedIDs.count];
    for (NSString *assetID in _selectedIDs) {
        PHAsset *a = _assetsByID[assetID];
        if (a && [aliveIDs containsObject:assetID]) { [out addObject:a]; }
    }
    return out;
}

@end
