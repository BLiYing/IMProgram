//  IMMediaPickLogic.h
//  自建相册选择器的纯逻辑（不碰 Photos / UIKit，可单测）。与 Android `media-picker/.../MediaPick.kt`
//  口径逐条一致（对称登记在 IMServer docs/SYMMETRY.md）；规格见 docs/design/MEDIA_PICKER_IOS_DESIGN.md。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 单次最多选几个。与 Android `MediaPick.LIMIT`、聊天相册宫格上限同值 9（IMMediaPickLogicTests 钉死）。
extern const NSInteger kIMMediaPickLimit;

/// 「全部」这个伪相册的桶 ID（不是 PHAssetCollection 的真实 localIdentifier）。
extern NSString * const kIMMediaPickAllBucketID;

/// 体积未知（PHAssetResource 取不到 fileSize）。**未知 ≠ 不可选**——与 Android 的「0 = 坏行」不同：
/// iOS 没有公开的文件大小 API，取不到是常态，不能因此把整个相册置灰。
extern const long long kIMMediaSizeUnknown;

/// 视频转码的实际结局（日志与告警据此区分，别拿「想转码」当「转码了」）。
typedef NS_ENUM(NSInteger, IMVideoTranscodeOutcome) {
    IMVideoTranscodeOutcomeSkipped = 0,  ///< 不需要转码（原图模式且已是 H.264 等）
    IMVideoTranscodeOutcomeDone,         ///< 转码并产出了文件
    IMVideoTranscodeOutcomeFellBack,     ///< 需要转码但导出失败/超时，回落发原文件（原编码）
};

@interface IMMediaPickLogic : NSObject

/// wanted = 是否需要转码；exported = 导出是否真的产出了文件。
+ (IMVideoTranscodeOutcome)transcodeOutcomeWanted:(BOOL)wanted exported:(BOOL)exported;

/// 有序选中（不是 Set）：编号 1..n 就是发送顺序，取消中间一张后后面的编号顺延。
/// 超限返回 nil（调用方吐司，别静默丢弃）；已选则取消。
+ (nullable NSArray<NSString *> *)toggledSelection:(NSArray<NSString *> *)selected
                                          assetID:(NSString *)assetID
                                            limit:(NSInteger)limit;

/// 编号（1-based）；未选中返回 0。
+ (NSInteger)numberOfAssetID:(NSString *)assetID inSelection:(NSArray<NSString *> *)selected;

/// 能不能选：只有超过 2GB 不可选；体积未知与 0 都可选（iOS 选择时判不出 0 字节坏文件，发送时校验标失败，
/// 与 Android「0 = MediaStore 坏行」在选择时就置灰不同，见 docs/UI_SPEC.md §6.4）。
+ (BOOL)isSelectableWithSizeBytes:(long long)sizeBytes;

/// 是否超上限（「超过 2.00 GB」）。当前它是 isSelectable 的补集，单列是为了提示文案不依赖那条规则的实现。
+ (BOOL)isTooLargeWithSizeBytes:(long long)sizeBytes;

/// 「原图」旁边的总字节数：只累加**已知**的选中项（>0）；全部未知返回 0（调用方据此不显示括号）。
+ (long long)totalBytesForSelection:(NSArray<NSString *> *)selected
                              sizes:(NSDictionary<NSString *, NSNumber *> *)sizes;

/// 人类可读体积，1024 进制（与系统相册一致）。保留一位小数（GB 两位）。
+ (NSString *)sizeLabelForBytes:(long long)bytes;

/// 视频时长 `m:ss`（秒数向下取整）。
+ (NSString *)durationLabelForSeconds:(NSTimeInterval)seconds;

/// 列数：compact 宽度固定 4；更宽按每格约 100pt 取整，且不少于 4。
+ (NSInteger)columnCountForWidth:(CGFloat)width;

@end

NS_ASSUME_NONNULL_END
