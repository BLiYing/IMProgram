//  IMMediaPickerPhotos.m

#import "IMMediaPickerPhotos.h"
#import "IMMediaPickLogic.h"
#import "IMLog.h"

@interface IMMediaPickBucket ()
- (instancetype)initWithID:(NSString *)bucketID title:(NSString *)title
                    assets:(PHFetchResult<PHAsset *> *)assets;
@end

@implementation IMMediaPickBucket
- (instancetype)initWithID:(NSString *)bucketID title:(NSString *)title
                    assets:(PHFetchResult<PHAsset *> *)assets {
    self = [super init];
    if (self) {
        _bucketID = [bucketID copy];
        _title = [title copy];
        _assets = assets;
    }
    return self;
}
- (nullable PHAsset *)cover { return self.assets.firstObject; }
@end

@implementation IMMediaPickerPhotos

+ (PHAuthorizationStatus)authorizationStatus {
    return [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
}

+ (void)requestAuthorization:(void (^)(PHAuthorizationStatus))completion {
    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:^(PHAuthorizationStatus status) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(status); });
    }];
}

/// 只取图片与视频，按创建时间倒序。
+ (PHFetchOptions *)assetFetchOptions {
    PHFetchOptions *opt = [PHFetchOptions new];
    opt.predicate = [NSPredicate predicateWithFormat:@"mediaType == %d OR mediaType == %d",
                     PHAssetMediaTypeImage, PHAssetMediaTypeVideo];
    opt.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
    return opt;
}

+ (NSArray<IMMediaPickBucket *> *)loadBucketsWithAllTitle:(NSString *)allTitle
                                              unnamedTitle:(NSString *)unnamedTitle {
    PHAuthorizationStatus status = [self authorizationStatus];
    if (status != PHAuthorizationStatusAuthorized && status != PHAuthorizationStatusLimited) { return @[]; }

    PHFetchResult<PHAsset *> *all = [PHAsset fetchAssetsWithOptions:[self assetFetchOptions]];
    if (all.count == 0) { return @[]; }
    IMMediaPickBucket *allBucket = [[IMMediaPickBucket alloc] initWithID:kIMMediaPickAllBucketID
                                                                   title:allTitle assets:all];

    NSMutableArray<IMMediaPickBucket *> *rest = [NSMutableArray array];
    void (^collect)(PHFetchResult<PHAssetCollection *> *, BOOL) = ^(PHFetchResult<PHAssetCollection *> *cols, BOOL smart) {
        [cols enumerateObjectsUsingBlock:^(PHAssetCollection *c, NSUInteger idx, BOOL *stop) {
            // 「已隐藏」需要额外授权才可读且不该出现在聊天选图里；「全部照片」已由伪相册承担，剔除免得重复。
            if (smart && (c.assetCollectionSubtype == PHAssetCollectionSubtypeSmartAlbumAllHidden ||
                          c.assetCollectionSubtype == PHAssetCollectionSubtypeSmartAlbumUserLibrary)) { return; }
            PHFetchResult<PHAsset *> *assets = [PHAsset fetchAssetsInAssetCollection:c options:[self assetFetchOptions]];
            if (assets.count == 0) { return; }
            NSString *title = c.localizedTitle.length > 0 ? c.localizedTitle : unnamedTitle;
            [rest addObject:[[IMMediaPickBucket alloc] initWithID:c.localIdentifier title:title assets:assets]];
        }];
    };
    collect([PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum
                                                     subtype:PHAssetCollectionSubtypeAny options:nil], YES);
    collect([PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum
                                                     subtype:PHAssetCollectionSubtypeAny options:nil], NO);

    // 按桶内最新一项时间倒序（不按数量：数量最多的往往是截图，而刚拍的那个相册才是要找的）。
    [rest sortUsingComparator:^NSComparisonResult(IMMediaPickBucket *a, IMMediaPickBucket *b) {
        NSDate *da = a.cover.creationDate ?: NSDate.distantPast;
        NSDate *db = b.cover.creationDate ?: NSDate.distantPast;
        return [db compare:da];
    }];
    IMLogDebugWithTag(IMLogTagMedia, @"picker_buckets total=%lu buckets=%lu",
                      (unsigned long)all.count, (unsigned long)rest.count);
    return [@[allBucket] arrayByAddingObjectsFromArray:rest];
}

#pragma mark 体积

+ (NSCache<NSString *, NSNumber *> *)sizeCache {
    static NSCache<NSString *, NSNumber *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; cache.countLimit = 4000; });
    return cache;
}

+ (nullable NSNumber *)cachedSizeBytesOfAsset:(PHAsset *)asset {
    return [[self sizeCache] objectForKey:asset.localIdentifier];
}

+ (nullable PHAssetResource *)primaryResourceOfAsset:(PHAsset *)asset {
    PHAssetResource *picked = nil;
    for (PHAssetResource *r in [PHAssetResource assetResourcesForAsset:asset]) {
        // 编辑过的取「当前版本」(FullSize*)，否则取原件；其余（配对视频/音频/调整数据）不算。
        BOOL fullSize = r.type == PHAssetResourceTypeFullSizePhoto || r.type == PHAssetResourceTypeFullSizeVideo;
        BOOL original = r.type == PHAssetResourceTypePhoto || r.type == PHAssetResourceTypeVideo;
        if (fullSize) { return r; }
        if (original && !picked) { picked = r; }
    }
    return picked;
}

+ (long long)sizeBytesOfAsset:(PHAsset *)asset {
    NSNumber *cached = [self cachedSizeBytesOfAsset:asset];
    if (cached) { return cached.longLongValue; }
    long long size = kIMMediaSizeUnknown;
    PHAssetResource *picked = [self primaryResourceOfAsset:asset];
    if (picked) {
        @try {
            id v = [picked valueForKey:@"fileSize"];
            // 0 当未知：PHAssetResource 对取不到体积的资源会给 0，不能因此把它置灰成「读不出来」。
            if ([v respondsToSelector:@selector(longLongValue)] && [v longLongValue] > 0) { size = [v longLongValue]; }
        } @catch (NSException *e) {
            IMLogWarnWithTag(IMLogTagMedia, @"picker_size_kvc_unavailable name=%@", e.name);
        }
    }
    [[self sizeCache] setObject:@(size) forKey:asset.localIdentifier];
    return size;
}

#pragma mark 缩略图

+ (PHCachingImageManager *)cachingManager {
    static PHCachingImageManager *mgr;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ mgr = [PHCachingImageManager new]; });
    return mgr;
}

+ (PHImageRequestOptions *)thumbnailOptions {
    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;
    opt.resizeMode = PHImageRequestOptionsResizeModeFast;
    opt.networkAccessAllowed = NO; // 宫格里不触发 iCloud 下载；未下载的资源显示系统给的低清缩略图
    return opt;
}

@end
