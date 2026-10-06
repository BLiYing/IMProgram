//  IMMediaPickerPhotos.h
//  自建相册选择器的 Photos 数据层：权限、相册（桶）列表、缩略图、体积。
//  **只有这一层碰 PhotoKit**，选择逻辑在 IMMediaPickLogic（可单测）。不引用聊天业务。

#import <UIKit/UIKit.h>
#import <Photos/Photos.h>

NS_ASSUME_NONNULL_BEGIN

/// 一个相册（含「全部」伪相册）：assets 是惰性 PHFetchResult（按创建时间倒序），不需要分页。
@interface IMMediaPickBucket : NSObject
@property (nonatomic, copy, readonly) NSString *bucketID;
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, strong, readonly) PHFetchResult<PHAsset *> *assets;
@property (nonatomic, strong, readonly, nullable) PHAsset *cover; ///< 桶内最新一项
@end

@interface IMMediaPickerPhotos : NSObject

/// 相册权限（readWrite 级别）。notDetermined / authorized / limited / denied / restricted。
+ (PHAuthorizationStatus)authorizationStatus;

/// 申请相册权限（仅 notDetermined 时系统才会弹窗）；主线程回调最终状态。
+ (void)requestAuthorization:(void (^)(PHAuthorizationStatus status))completion;

/// 构建相册列表：「全部」恒首位，其余按桶内最新一项时间倒序；空相册与「已隐藏」剔除。
/// 可能较慢（遍历全部相册），**在后台线程调用**。无权限时返回空数组。
+ (NSArray<IMMediaPickBucket *> *)loadBucketsWithAllTitle:(NSString *)allTitle
                                              unnamedTitle:(NSString *)unnamedTitle;

/// 文件字节数；取不到返回 kIMMediaSizeUnknown。进程内缓存。
/// 公共 API 没有文件大小，这里读 PHAssetResource 的 `fileSize`（KVC，业界通行做法，取不到按未知处理）。
+ (long long)sizeBytesOfAsset:(PHAsset *)asset;

/// 相册资源的主文件（编辑过取「当前版本」FullSize*，否则取原件）；nil = 没有可导出的资源。
/// 取体积与导出原件共用这一个判据，免得两处对「哪份才是要发的文件」说法不一。
+ (nullable PHAssetResource *)primaryResourceOfAsset:(PHAsset *)asset;

/// 缓存里的体积（不触发读取），没有返回 nil。
+ (nullable NSNumber *)cachedSizeBytesOfAsset:(PHAsset *)asset;

/// 宫格缩略图管理器（PHCachingImageManager，可预热可见区）。
+ (PHCachingImageManager *)cachingManager;

/// 宫格缩略图请求参数：不联网（宫格里不触发 iCloud 下载），机会式交付（先低清后高清）。
+ (PHImageRequestOptions *)thumbnailOptions;

@end

NS_ASSUME_NONNULL_END
