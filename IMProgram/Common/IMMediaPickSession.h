//  IMMediaPickSession.h
//  自建选择器一次会话的选择状态：有序选中 + 「原图」开关 + 已读到的体积。宫格页与预览页共用一份，
//  所以两页永远讲同一套规则（编号、上限、总大小）。规则本体在 IMMediaPickLogic。

#import <Foundation/Foundation.h>
#import <Photos/Photos.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMMediaPickSession : NSObject

/// 选中项 localIdentifier，**按选中顺序**（编号 = 下标 + 1，也是发送顺序）。
@property (nonatomic, copy, readonly) NSArray<NSString *> *selectedIDs;
@property (nonatomic, assign) BOOL sendOriginal;

/// 选中 / 取消。返回 NO = 超过上限（调用方吐司，不要静默丢弃）。
- (BOOL)toggleAsset:(PHAsset *)asset;

/// 编号（1-based）；未选中 0。
- (NSInteger)numberOfAsset:(PHAsset *)asset;

/// 体积（读 PHAssetResource，带缓存）；未知为 kIMMediaSizeUnknown。
- (long long)sizeBytesOfAsset:(PHAsset *)asset;
/// 点击时判定：视频同步取体积（>2GB / 0 字节不可选）。
- (BOOL)isSelectableAsset:(PHAsset *)asset;
/// 格子绘制时判定是否置灰：**只看缓存**（不同步查资源，绘制路径不能卡）；体积由格子在后台补读。
- (BOOL)isDimmedAsset:(PHAsset *)asset;

/// 「原图」旁边的总字节数（只累加已知项；全部未知 = 0）。
- (long long)totalBytes;

/// 剔掉已不可访问的选中项（相册里被删 / 有限访问下被取消授权）。有变化返回 YES。相册内容变化后调用。
- (BOOL)pruneUnavailableSelection;

/// 选中的 PHAsset，按选中顺序（相册里已被删除的直接跳过）。
- (NSArray<PHAsset *> *)orderedAssets;

@end

NS_ASSUME_NONNULL_END
